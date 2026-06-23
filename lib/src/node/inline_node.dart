/// 行内节点 sealed family。
///
/// 阶段 1.1 范围:Text / Em / Strong / LineBreak
/// 后续会扩展 LinkRun / MentionRun / EmojiRun / InlineCodeRun / ImageRun 等。

library;

import 'package:flutter/foundation.dart';

/// 所有行内节点的基类。
@immutable
sealed class InlineNode {
  const InlineNode();
}

/// 纯文本片段。
@immutable
class TextRun extends InlineNode {
  const TextRun(this.text);

  final String text;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TextRun &&
          runtimeType == other.runtimeType &&
          text == other.text;

  @override
  int get hashCode => text.hashCode;

  @override
  String toString() => 'TextRun(${text.length} chars)';
}

/// `<em>` / `<i>` 斜体,可包含嵌套行内子节点。
@immutable
class EmRun extends InlineNode {
  const EmRun({required this.children});

  final List<InlineNode> children;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EmRun &&
          runtimeType == other.runtimeType &&
          listEquals(children, other.children);

  @override
  int get hashCode => Object.hashAll(children);

  @override
  String toString() => 'EmRun(${children.length} children)';
}

/// `<strong>` / `<b>` 粗体,可包含嵌套行内子节点。
@immutable
class StrongRun extends InlineNode {
  const StrongRun({required this.children});

  final List<InlineNode> children;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StrongRun &&
          runtimeType == other.runtimeType &&
          listEquals(children, other.children);

  @override
  int get hashCode => Object.hashAll(children);

  @override
  String toString() => 'StrongRun(${children.length} children)';
}

/// `<br>` 强制换行。
@immutable
class LineBreakRun extends InlineNode {
  const LineBreakRun();

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is LineBreakRun;

  @override
  int get hashCode => 0;

  @override
  String toString() => 'LineBreakRun()';
}
