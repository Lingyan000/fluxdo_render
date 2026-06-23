/// 渲染节点的根类型族。
///
/// 数据模型设计原则:
/// - sealed class + Dart 3 switch exhaustiveness,新增节点必须改所有 dispatch
/// - 全部 immutable,`==`/`hashCode` 让 widget rebuild diff 廉价
/// - 块级与行内严格分层:`BlockNode` 顶层渲染,行内只在某 `BlockNode` 内
/// - 每个 `BlockNode` 自带稳定 `id` — 为阶段 5 自研选区
///   (`LogicalPosition { blockId, inlineIndex, charOffset }`)铺路
///
/// 阶段 1.1 范围:Paragraph + 行内 Text/Em/Strong/LineBreak
/// 后续阶段会扩展 HeadingNode / ListNode / CodeBlockNode 等。

library;

import 'package:flutter/foundation.dart';

import 'inline_node.dart';

export 'inline_node.dart';

/// 所有块级节点的基类。
///
/// 一份 cooked HTML 解析后产物是 `List<BlockNode>`。每个 BlockNode
/// 自带稳定 [id],由 parser 在解析时分配("b_0", "b_1", ...),同一份
/// HTML 解析两次 id 相同。
///
/// id 仅作"节点身份"用,**不参与 ==/hashCode**(让节点 immutable +
/// 内容比较仍然便宜)。阶段 5 自研选区时 `LogicalPosition` 用 id
/// 寻址,行内通过 (id, inlineIndex, charOffset) 三元组定位。
@immutable
sealed class BlockNode {
  const BlockNode({required this.id});

  final String id;
}

/// 段落 — 一段连续的行内内容。
///
/// 对应 HTML 中的 `<p>...</p>`。
@immutable
class ParagraphNode extends BlockNode {
  const ParagraphNode({required super.id, required this.inlines});

  /// 段落内的行内节点序列。
  final List<InlineNode> inlines;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ParagraphNode &&
          runtimeType == other.runtimeType &&
          listEquals(inlines, other.inlines);

  @override
  int get hashCode => Object.hashAll(inlines);

  @override
  String toString() => 'ParagraphNode($id, ${inlines.length} inlines)';
}

/// 标题 — h1/h2/h3/h4/h5/h6,字号由 [level] 决定。
///
/// 对应 HTML 中的 `<h1>` - `<h6>`。
@immutable
class HeadingNode extends BlockNode {
  const HeadingNode({
    required super.id,
    required this.level,
    required this.inlines,
  }) : assert(level >= 1 && level <= 6, 'heading level must be 1..6');

  /// 标题级别,1-6。
  final int level;

  /// 标题内的行内节点序列。
  final List<InlineNode> inlines;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HeadingNode &&
          runtimeType == other.runtimeType &&
          level == other.level &&
          listEquals(inlines, other.inlines);

  @override
  int get hashCode => Object.hash(level, Object.hashAll(inlines));

  @override
  String toString() => 'HeadingNode($id, h$level, ${inlines.length} inlines)';
}

/// 列表项 — 一行 inline 内容 + 可选嵌套子列表(li 内 ul/ol)。
///
/// 不是 BlockNode,只是 ListNode 内部的数据结构。
@immutable
class ListItem {
  const ListItem({
    required this.inlines,
    this.children,
  });

  /// 列表项的 inline 内容(li 直属 text/em/link/...)。
  final List<InlineNode> inlines;

  /// 嵌套子列表(li 内含 ul/ol),null 表示叶子项。
  final List<ListNode>? children;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ListItem &&
          runtimeType == other.runtimeType &&
          listEquals(inlines, other.inlines) &&
          listEquals(children, other.children);

  @override
  int get hashCode => Object.hash(
        Object.hashAll(inlines),
        children == null ? 0 : Object.hashAll(children!),
      );

  @override
  String toString() => 'ListItem(${inlines.length} inlines'
      '${children == null ? "" : ", ${children!.length} sub-lists"})';
}

/// 列表 — `<ul>` 或 `<ol>`,可嵌套。
///
/// 对应 HTML 中的 `<ul>...</ul>` / `<ol>...</ol>`。深度 [depth] 由 parser
/// 在递归时填(顶层 0,每嵌套一层 +1),renderer 用 depth 决定缩进倍数。
///
/// 视觉对齐 legacy(DiscourseHtmlContentWidget customStylesBuilder):
///   ul/ol: padding-left 20px, margin 8px 上下
///   li:    margin 4px 上下, line-height 1.5
///   有序列表 marker 用等宽数字(FontFeature.tabularFigures)。
@immutable
class ListNode extends BlockNode {
  const ListNode({
    required super.id,
    required this.ordered,
    required this.items,
    this.depth = 0,
  });

  /// true = `<ol>`(有序,marker 是数字),false = `<ul>`(无序,marker 是 ·)
  final bool ordered;

  /// 列表项序列。
  final List<ListItem> items;

  /// 嵌套深度(顶层 = 0)。
  final int depth;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ListNode &&
          runtimeType == other.runtimeType &&
          ordered == other.ordered &&
          depth == other.depth &&
          listEquals(items, other.items);

  @override
  int get hashCode => Object.hash(ordered, depth, Object.hashAll(items));

  @override
  String toString() =>
      'ListNode($id, ${ordered ? "ol" : "ul"}, depth=$depth, ${items.length} items)';
}
