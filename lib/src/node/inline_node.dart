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

/// `<a href="...">` 链接,可嵌套行内子节点。
///
/// 点击行为不由子包决定 —— 渲染时通过 [NodeFactory.linkHandler] 注入,
/// 主项目负责 URL 路由(launchUrl / 内部话题跳转 / 用户卡跳转 等)。
///
/// 阶段 1 暂不带 click_count 注入(那是 post.linkCounts 数据,跟主项目
/// model 强耦合),留到阶段 2 link 体系细化时再加。
@immutable
class LinkRun extends InlineNode {
  const LinkRun({required this.href, required this.children});

  /// 已解析的链接 URL(parser 阶段不做 CDN 重写,显示给 LinkHandler)。
  final String href;

  /// 链接显示内容,可嵌套样式(em/strong)。
  final List<InlineNode> children;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LinkRun &&
          runtimeType == other.runtimeType &&
          href == other.href &&
          listEquals(children, other.children);

  @override
  int get hashCode => Object.hash(href, Object.hashAll(children));

  @override
  String toString() => 'LinkRun($href, ${children.length} children)';
}
