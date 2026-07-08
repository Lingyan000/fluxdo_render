/// 编辑器块模型 v2 —— 扁平块 + 属性(ProseMirror 风)。
///
/// 设计决策(M2 计划):
/// - **扁平**:列表项/引用内段落不是树,是带 `depth`/`quoteDepth` 属性的
///   平铺块 —— 回车/Tab/合并等编辑操作全是 O(1) 属性改写;与阅读端
///   ListNode/BlockquoteNode 树形的互转集中在 doc_converter 一处。
/// - **孤岛**:不可编辑块(codeblock/poll/image...)以 [IslandBlock]
///   原引用直存,渲染走 NodeFactory,选区中占 1 个单位(offset 0/1)。
/// - 有序列表编号是**派生渲染态**(FluxdoEditor build 时按连续 run 扫描
///   计算),模型只存 [TextBlock.listStart](首项还原 `<ol start>`)。
library;

import 'package:flutter/foundation.dart';

import '../../node/node.dart';
import 'editable_text_content.dart';

/// 文本块种类。
enum TextBlockKind { paragraph, heading, listItem }

// ---------------------------------------------------------------------
// 容器帧(M5-B):块的"包裹上下文"栈元素
// ---------------------------------------------------------------------

/// 容器帧:一层可进入的块级包裹(引用/引用卡/剧透/折叠/callout)。
///
/// 对齐官方 ProseMirror composer 的容器语义(quote/spoiler/details 都是
/// `content: "block+"` 的可编辑容器,非只读原子)。TextBlock 持
/// [TextBlock.containers] 栈(外→内),相邻块公共前缀 = 同一个容器 ——
/// 渲染分组画壳,导出时分组重建节点树。
///
/// **相等性 = 分组判据**:两个块的 frame 相等才算同一容器(QuoteCard
/// 的 username 不同 = 两张引用卡)。
@immutable
sealed class ContainerFrame {
  const ContainerFrame();
}

/// 纯引用 `> `(BlockquoteNode)。
@immutable
class QuoteFrame extends ContainerFrame {
  const QuoteFrame();

  @override
  bool operator ==(Object other) => other is QuoteFrame;

  @override
  int get hashCode => (QuoteFrame).hashCode;

  @override
  String toString() => 'Quote';
}

/// 引用卡 `[quote="user, post:N, topic:M"]`(QuoteCardNode 的编辑化)。
///
/// 只持**往返字段**(raw 参数面);头像/分类徽章等展示字段是服务端
/// cook 注入的,编辑态壳不渲染(提交后服务端重新补全)。
@immutable
class QuoteCardFrame extends ContainerFrame {
  const QuoteCardFrame({
    this.username = '',
    this.displayName,
    this.postNumber,
    this.topicId,
    this.full = false,
  });

  final String username;
  final String? displayName;
  final int? postNumber;
  final int? topicId;
  final bool full;

  @override
  bool operator ==(Object other) =>
      other is QuoteCardFrame &&
      username == other.username &&
      displayName == other.displayName &&
      postNumber == other.postNumber &&
      topicId == other.topicId &&
      full == other.full;

  @override
  int get hashCode =>
      Object.hash(username, displayName, postNumber, topicId, full);

  @override
  String toString() => 'QuoteCard(@$username)';
}

/// 块级剧透 `[spoiler]…[/spoiler]`(SpoilerBlockNode)。
@immutable
class SpoilerFrame extends ContainerFrame {
  const SpoilerFrame();

  @override
  bool operator ==(Object other) => other is SpoilerFrame;

  @override
  int get hashCode => (SpoilerFrame).hashCode;

  @override
  String toString() => 'Spoiler';
}

/// 折叠详情 `[details="summary"]…[/details]`(DetailsNode)。
@immutable
class DetailsFrame extends ContainerFrame {
  const DetailsFrame({this.summary = '', this.open = false});

  final String summary;
  final bool open;

  @override
  bool operator ==(Object other) =>
      other is DetailsFrame && summary == other.summary && open == other.open;

  @override
  int get hashCode => Object.hash(summary, open);

  @override
  String toString() => 'Details("$summary")';
}

/// Obsidian callout `> [!type] title`(CalloutNode)。
/// 本质是带首行标记的 blockquote,序列化走 `> ` 前缀 + 首行标记。
@immutable
class CalloutFrame extends ContainerFrame {
  const CalloutFrame({
    required this.kind,
    required this.typeRaw,
    this.title,
    this.foldable,
  });

  final CalloutKind kind;
  final String typeRaw;
  final String? title;
  final bool? foldable;

  @override
  bool operator ==(Object other) =>
      other is CalloutFrame &&
      kind == other.kind &&
      typeRaw == other.typeRaw &&
      title == other.title &&
      foldable == other.foldable;

  @override
  int get hashCode => Object.hash(kind, typeRaw, title, foldable);

  @override
  String toString() => 'Callout($typeRaw)';
}

/// 编辑文档里的一个块。
@immutable
sealed class EditorBlock {
  const EditorBlock({required this.id});

  final String id;

  /// 选区端点上限:文本块 = 内容长度;孤岛 = 1(整体一个单位)。
  int get selectionLength;
}

/// 可编辑文本块(段落/标题/列表项;容器栈叠加)。
@immutable
class TextBlock extends EditorBlock {
  TextBlock({
    required super.id,
    required this.content,
    this.kind = TextBlockKind.paragraph,
    this.headingLevel = 1,
    this.ordered = false,
    this.depth = 0,
    this.listStart = 1,
    List<ContainerFrame> containers = const [],
    int quoteDepth = 0,
  })  : assert(headingLevel >= 1 && headingLevel <= 6),
        assert(depth >= 0),
        assert(quoteDepth == 0 || containers.isEmpty,
            'quoteDepth 便捷参数与 containers 互斥'),
        containers = List.unmodifiable(quoteDepth > 0
            ? List.generate(quoteDepth, (_) => const QuoteFrame())
            : containers);

  final EditableTextContent content;

  final TextBlockKind kind;

  /// heading 级别(仅 [kind] == heading 时有意义)。
  final int headingLevel;

  /// 列表项属性(仅 [kind] == listItem 时有意义)。
  final bool ordered;
  final int depth;

  /// `<ol start="N">` 还原用(连续 listItem run 的首项生效)。
  final int listStart;

  /// 容器栈(外→内):本块被哪些可进入容器包裹(M5-B)。
  /// 空 = 顶层。相邻块的公共前缀 = 同一容器实例(渲染分组画壳,
  /// 导出分组重建树)。构造参数 quoteDepth 是 N 层 QuoteFrame 的便捷写法。
  final List<ContainerFrame> containers;

  /// 引用深度(兼容读取口径):容器栈里 Quote/Callout 系的层数。
  /// 工具栏高亮/序列化 `> ` 前缀计数用。
  int get quoteDepth =>
      containers.where((f) => f is QuoteFrame || f is CalloutFrame).length;

  bool get isParagraph => kind == TextBlockKind.paragraph;
  bool get isHeading => kind == TextBlockKind.heading;
  bool get isListItem => kind == TextBlockKind.listItem;

  @override
  int get selectionLength => content.length;

  TextBlock copyWith({
    EditableTextContent? content,
    TextBlockKind? kind,
    int? headingLevel,
    bool? ordered,
    int? depth,
    int? listStart,
    List<ContainerFrame>? containers,
  }) =>
      TextBlock(
        id: id,
        content: content ?? this.content,
        kind: kind ?? this.kind,
        headingLevel: headingLevel ?? this.headingLevel,
        ordered: ordered ?? this.ordered,
        depth: depth ?? this.depth,
        listStart: listStart ?? this.listStart,
        containers: containers ?? this.containers,
      );

  /// 属性归一化:转换 kind 时清掉不相关属性(防幽灵属性泄漏)。
  TextBlock asParagraph() => TextBlock(
        id: id,
        content: content,
        containers: containers,
      );

  TextBlock asHeading(int level) => TextBlock(
        id: id,
        content: content,
        kind: TextBlockKind.heading,
        headingLevel: level,
        containers: containers,
      );

  TextBlock asListItem({required bool ordered, int depth = 0, int listStart = 1}) =>
      TextBlock(
        id: id,
        content: content,
        kind: TextBlockKind.listItem,
        ordered: ordered,
        depth: depth,
        listStart: listStart,
        containers: containers,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TextBlock &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          kind == other.kind &&
          headingLevel == other.headingLevel &&
          ordered == other.ordered &&
          depth == other.depth &&
          listStart == other.listStart &&
          listEquals(containers, other.containers) &&
          content == other.content;

  @override
  int get hashCode => Object.hash(id, kind, headingLevel, ordered, depth,
      listStart, Object.hashAll(containers), content);

  @override
  String toString() {
    final attrs = switch (kind) {
      TextBlockKind.paragraph => '',
      TextBlockKind.heading => ' h$headingLevel',
      TextBlockKind.listItem =>
        ' ${ordered ? "ol" : "ul"}@$depth${listStart != 1 ? "+$listStart" : ""}',
    };
    return 'TextBlock($id$attrs'
        '${containers.isEmpty ? "" : " [${containers.join(">")}]"}, '
        '"${content.text}")';
  }
}

/// 只读孤岛块:任意阅读端 BlockNode 原引用直存(identity 保真,导出原样吐回)。
@immutable
class IslandBlock extends EditorBlock {
  const IslandBlock({required super.id, required this.node});

  final BlockNode node;

  @override
  int get selectionLength => 1;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is IslandBlock &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          node == other.node;

  @override
  int get hashCode => Object.hash(id, node);

  @override
  String toString() => 'IslandBlock($id, ${node.runtimeType})';
}
