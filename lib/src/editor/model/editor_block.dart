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

/// 编辑文档里的一个块。
@immutable
sealed class EditorBlock {
  const EditorBlock({required this.id});

  final String id;

  /// 选区端点上限:文本块 = 内容长度;孤岛 = 1(整体一个单位)。
  int get selectionLength;
}

/// 可编辑文本块(段落/标题/列表项;引用属性叠加)。
@immutable
class TextBlock extends EditorBlock {
  const TextBlock({
    required super.id,
    required this.content,
    this.kind = TextBlockKind.paragraph,
    this.headingLevel = 1,
    this.ordered = false,
    this.depth = 0,
    this.listStart = 1,
    this.quoteDepth = 0,
  })  : assert(headingLevel >= 1 && headingLevel <= 6),
        assert(depth >= 0),
        assert(quoteDepth >= 0);

  final EditableTextContent content;

  final TextBlockKind kind;

  /// heading 级别(仅 [kind] == heading 时有意义)。
  final int headingLevel;

  /// 列表项属性(仅 [kind] == listItem 时有意义)。
  final bool ordered;
  final int depth;

  /// `<ol start="N">` 还原用(连续 listItem run 的首项生效)。
  final int listStart;

  /// 引用嵌套深度,0 = 不在引用内。对任何 kind 叠加生效。
  final int quoteDepth;

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
    int? quoteDepth,
  }) =>
      TextBlock(
        id: id,
        content: content ?? this.content,
        kind: kind ?? this.kind,
        headingLevel: headingLevel ?? this.headingLevel,
        ordered: ordered ?? this.ordered,
        depth: depth ?? this.depth,
        listStart: listStart ?? this.listStart,
        quoteDepth: quoteDepth ?? this.quoteDepth,
      );

  /// 属性归一化:转换 kind 时清掉不相关属性(防幽灵属性泄漏)。
  TextBlock asParagraph() => TextBlock(
        id: id,
        content: content,
        quoteDepth: quoteDepth,
      );

  TextBlock asHeading(int level) => TextBlock(
        id: id,
        content: content,
        kind: TextBlockKind.heading,
        headingLevel: level,
        quoteDepth: quoteDepth,
      );

  TextBlock asListItem({required bool ordered, int depth = 0, int listStart = 1}) =>
      TextBlock(
        id: id,
        content: content,
        kind: TextBlockKind.listItem,
        ordered: ordered,
        depth: depth,
        listStart: listStart,
        quoteDepth: quoteDepth,
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
          quoteDepth == other.quoteDepth &&
          content == other.content;

  @override
  int get hashCode => Object.hash(
      id, kind, headingLevel, ordered, depth, listStart, quoteDepth, content);

  @override
  String toString() {
    final attrs = switch (kind) {
      TextBlockKind.paragraph => '',
      TextBlockKind.heading => ' h$headingLevel',
      TextBlockKind.listItem =>
        ' ${ordered ? "ol" : "ul"}@$depth${listStart != 1 ? "+$listStart" : ""}',
    };
    return 'TextBlock($id$attrs'
        '${quoteDepth > 0 ? " q$quoteDepth" : ""}, "${content.text}")';
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
