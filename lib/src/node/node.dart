/// 渲染节点的根类型族。
///
/// 数据模型设计原则:
/// - sealed class + Dart 3 switch exhaustiveness,新增节点必须改所有 dispatch
/// - 全部 immutable,`==`/`hashCode` 让 widget rebuild diff 廉价
/// - 块级与行内严格分层:`BlockNode` 顶层渲染,行内只在某 `BlockNode` 内
///
/// 阶段 1.1 范围:Paragraph + 行内 Text/Em/Strong/LineBreak
/// 后续阶段会扩展 HeadingNode / ListNode / CodeBlockNode 等。

library;

import 'package:flutter/foundation.dart';

import 'inline_node.dart';

export 'inline_node.dart';

/// 所有块级节点的基类。
///
/// 一份 cooked HTML 解析后产物是 `List<BlockNode>`。
@immutable
sealed class BlockNode {
  const BlockNode();
}

/// 段落 — 一段连续的行内内容。
///
/// 对应 HTML 中的 `<p>...</p>`。
@immutable
class ParagraphNode extends BlockNode {
  const ParagraphNode({required this.inlines});

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
  String toString() => 'ParagraphNode(${inlines.length} inlines)';
}
