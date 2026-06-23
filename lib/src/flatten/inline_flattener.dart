/// 把 `List<InlineNode>` 压平成 Flutter 的 InlineSpan 树。
///
/// 阶段 1 范围:Text / Em / Strong / LineBreak / Link / InlineCode 六种 +
/// 嵌套样式合并。后续阶段会加 MentionRun / EmojiRun / ImageRun 等。
///
/// 设计:
/// - 输出 InlineSpan 树而不是 widget list — 让一个段落的所有文字共享一个
///   RichText,文本布局/选区/换行才能正常工作。
/// - Em/Strong 用 TextStyle 合并(`merge`)而不是嵌套 WidgetSpan,
///   性能 + 选区表现更好。
/// - LineBreak 渲染为 `\n` 文本字符。
/// - LinkRun 产出带 TapGestureRecognizer 的 TextSpan,recognizer 是
///   stateful 资源,通过 [FlattenResult.recognizers] 暴露给调用方,
///   由 widget dispose 时统一 dispose。
/// - InlineCodeRun 输出 monospace + 灰底 TextSpan,圆角/padding 留到阶段 5
///   自研选区+绘制层实现(目前用 TextStyle.background 的纯矩形灰底)。
///
/// 不处理 whitespace 折叠 — 阶段 1.1 输入是 Discourse cooked HTML,
/// 已经是规整 markdown 输出,标签间空白由 paragraph 边界自然分隔。
/// 阶段 1.2(加 inline_code)再视情况引入 fwfh 的 whitespace 折叠。

library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../node/inline_node.dart';
import '../render/link_handler.dart';

/// 压平结果 — InlineSpan 树 + 需要 dispose 的 recognizers。
class FlattenResult {
  FlattenResult({required this.span, required this.recognizers});

  final TextSpan span;

  /// 这次 flatten 创建的所有 GestureRecognizer,调用方必须在 widget
  /// dispose 时遍历 `recognizer.dispose()`。
  final List<GestureRecognizer> recognizers;
}

class InlineFlattener {
  const InlineFlattener();

  /// 把 inline 节点列表压平,根 span 用 baseStyle 作 fallback。
  ///
  /// [linkHandler]:点击链接时执行的回调(主项目注入)。null 时用
  /// [defaultLinkHandler](仅 debugPrint)。
  /// [context]:link 点击时传给 handler 用;null 时 link 不可点。
  FlattenResult flatten(
    List<InlineNode> inlines,
    TextStyle baseStyle, {
    LinkActionHandler? linkHandler,
    BuildContext? context,
  }) {
    final recognizers = <GestureRecognizer>[];
    final children = <InlineSpan>[];
    final handler = linkHandler ?? defaultLinkHandler;
    for (final node in inlines) {
      children.add(_toSpan(node, handler, context, recognizers));
    }
    return FlattenResult(
      span: TextSpan(style: baseStyle, children: children),
      recognizers: recognizers,
    );
  }

  List<InlineSpan> _build(
    List<InlineNode> nodes,
    LinkActionHandler handler,
    BuildContext? context,
    List<GestureRecognizer> recognizers, {
    GestureRecognizer? inheritedRecognizer,
  }) {
    return [
      for (final node in nodes)
        _toSpan(
          node,
          handler,
          context,
          recognizers,
          inheritedRecognizer: inheritedRecognizer,
        ),
    ];
  }

  InlineSpan _toSpan(
    InlineNode node,
    LinkActionHandler handler,
    BuildContext? context,
    List<GestureRecognizer> recognizers, {
    GestureRecognizer? inheritedRecognizer,
  }) {
    return switch (node) {
      TextRun(:final text) => TextSpan(
          text: text,
          recognizer: inheritedRecognizer,
        ),
      EmRun(:final children) => TextSpan(
          style: const TextStyle(fontStyle: FontStyle.italic),
          children: _build(
            children,
            handler,
            context,
            recognizers,
            inheritedRecognizer: inheritedRecognizer,
          ),
        ),
      StrongRun(:final children) => TextSpan(
          style: const TextStyle(fontWeight: FontWeight.bold),
          children: _build(
            children,
            handler,
            context,
            recognizers,
            inheritedRecognizer: inheritedRecognizer,
          ),
        ),
      LineBreakRun() => TextSpan(
          text: '\n',
          recognizer: inheritedRecognizer,
        ),
      LinkRun(:final href, :final children) => _buildLinkSpan(
          href,
          children,
          handler,
          context,
          recognizers,
        ),
      InlineCodeRun(:final text) => _buildInlineCodeSpan(
          text,
          context,
          inheritedRecognizer: inheritedRecognizer,
        ),
    };
  }

  TextSpan _buildLinkSpan(
    String href,
    List<InlineNode> children,
    LinkActionHandler handler,
    BuildContext? context,
    List<GestureRecognizer> recognizers,
  ) {
    final ctx = context;
    final recognizer = ctx == null
        ? null
        : (TapGestureRecognizer()..onTap = () => handler(ctx, href));
    if (recognizer != null) recognizers.add(recognizer);

    // 样式对齐 legacy(DiscourseHtmlContentWidget customStylesBuilder):
    //   `{color: theme.colorScheme.primary, text-decoration: none}`
    // 没有下划线,只用主题主色区分。
    final linkColor =
        ctx == null ? null : Theme.of(ctx).colorScheme.primary;

    // Flutter `TextSpan.recognizer` 不会从父 span 传播到 child:
    // hit test 只对 span 本身的 `text` 字段生效。所以 link 子树里的
    // 所有叶子 span(TextRun / InlineCodeRun / LineBreakRun)都得把
    // 同一个 recognizer 挂上,才能在任意位置 tap 都触发 onTap。
    return TextSpan(
      style: TextStyle(color: linkColor),
      // 父 span 没有 text,recognizer 设了也不响应;但 children 里的
      // 叶子会带同一个 recognizer
      children: _build(
        children,
        handler,
        context,
        recognizers,
        inheritedRecognizer: recognizer,
      ),
    );
  }

  /// 行内代码渲染:monospace + 较小字号 + 主题适配灰色字。
  ///
  /// 样式对齐 legacy `inline_decorator_common.dart::getInlineCodeStyles`:
  ///   font-family: FiraCode, monospace
  ///   font-size: 0.85em
  ///   color: dark=#b0b0b0 / light=#666666
  ///   background-color: transparent(legacy 用独立 CustomPainter 画灰底圆角)
  ///
  /// **TODO(阶段 5)**:legacy 的 InlineCodePainter 用 CustomPainter +
  /// TextPainter rect 探测,实现灰底**圆角** + **跨行 RRect 合并** +
  /// 行内 padding。我现在用 `TextStyle.background` 走纯矩形 fill,
  /// 跨行会出现两个独立矩形、没圆角、贴字。等阶段 5 自研选区 + 自研
  /// paint 时同步上,届时 InlineCodeRun 数据结构不变,只换渲染层。
  TextSpan _buildInlineCodeSpan(
    String text,
    BuildContext? context, {
    GestureRecognizer? inheritedRecognizer,
  }) {
    final isDark = context != null &&
        Theme.of(context).brightness == Brightness.dark;
    final bg = Paint()
      ..style = PaintingStyle.fill
      ..color = isDark ? const Color(0xFF3A3A3A) : const Color(0xFFE8E8E8);
    return TextSpan(
      text: text,
      recognizer: inheritedRecognizer,
      style: TextStyle(
        fontFamily: 'FiraCode',
        fontFamilyFallback: const ['monospace', 'Menlo', 'Courier'],
        fontSize: _inlineCodeFontSize, // baseStyle 14 → 11.9
        color: isDark ? const Color(0xFFB0B0B0) : const Color(0xFF666666),
        background: bg,
      ),
    );
  }

  // 0.85em:相对于父 baseStyle.fontSize。当前实现是绝对值预设,正确做法
  // 是 inherit 父 fontSize 再 * 0.85,留待阶段 5 调整(届时 baseStyle 体系
  // 整理)。14 * 0.85 = 11.9。
  static const _inlineCodeFontSize = 11.9;
}
