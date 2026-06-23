/// 把 `List<InlineNode>` 压平成 Flutter 的 InlineSpan 树。
///
/// 阶段 1.1 范围:Text / Em / Strong / LineBreak 四种 + 嵌套样式合并。
/// 后续阶段会加 LinkRun(GestureRecognizer)、MentionRun / EmojiRun
/// (InlineCustomWidget WidgetSpan)等。
///
/// 设计:
/// - 输出 InlineSpan 树而不是 widget list — 让一个段落的所有文字共享一个
///   RichText,文本布局/选区/换行才能正常工作。
/// - Em/Strong 用 TextStyle 合并(`merge`)而不是嵌套 WidgetSpan,
///   性能 + 选区表现更好。
/// - LineBreak 渲染为 `\n` 文本字符。
///
/// 不处理 whitespace 折叠 — 阶段 1.1 输入是 Discourse cooked HTML,
/// 已经是规整 markdown 输出,标签间空白由 paragraph 边界自然分隔。
/// 阶段 1.2(加 link / inline_code)再视情况引入 fwfh 的 whitespace 折叠。

library;

import 'package:flutter/painting.dart';

import '../node/inline_node.dart';

class InlineFlattener {
  const InlineFlattener();

  /// 把 inline 节点列表压平成 TextSpan,根 span 用 baseStyle 作 fallback。
  TextSpan flatten(List<InlineNode> inlines, TextStyle baseStyle) {
    return TextSpan(
      style: baseStyle,
      children: _build(inlines),
    );
  }

  List<InlineSpan> _build(List<InlineNode> nodes) {
    return [
      for (final node in nodes) _toSpan(node),
    ];
  }

  InlineSpan _toSpan(InlineNode node) {
    return switch (node) {
      TextRun(:final text) => TextSpan(text: text),
      EmRun(:final children) => TextSpan(
          style: const TextStyle(fontStyle: FontStyle.italic),
          children: _build(children),
        ),
      StrongRun(:final children) => TextSpan(
          style: const TextStyle(fontWeight: FontWeight.bold),
          children: _build(children),
        ),
      LineBreakRun() => const TextSpan(text: '\n'),
    };
  }
}
