/// 把 `List<InlineNode>` 压平成 Flutter 的 InlineSpan 树。
///
/// 阶段 1 范围:Text / Em / Strong / LineBreak / Link / InlineCode / Emoji
/// 七种 + 嵌套样式合并。后续阶段会加 MentionRun / ImageRun 等。
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
/// - EmojiRun 走 WidgetSpan(图片不是文字),由 [EmojiImageBuilder] 注入,
///   尺寸跟随父字号(only-emoji 32dp)。
///
/// 不处理 whitespace 折叠 — 阶段 1.1 输入是 Discourse cooked HTML,
/// 已经是规整 markdown 输出,标签间空白由 paragraph 边界自然分隔。
/// 阶段 1.2(加 inline_code)再视情况引入 fwfh 的 whitespace 折叠。

library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../node/inline_node.dart';
import '../render/emoji_handler.dart';
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
  /// [emojiImageBuilder]:emoji 图片渲染 builder(主项目注入)。null 时用
  /// [defaultEmojiImageBuilder](Image.network 兜底)。
  /// [context]:link 点击 / emoji 字号探测时传给 handler 用;null 时
  /// link 不可点 + emoji 尺寸退化为 baseStyle.fontSize 或 14。
  FlattenResult flatten(
    List<InlineNode> inlines,
    TextStyle baseStyle, {
    LinkActionHandler? linkHandler,
    EmojiImageBuilder? emojiImageBuilder,
    BuildContext? context,
  }) {
    final recognizers = <GestureRecognizer>[];
    final children = <InlineSpan>[];
    final handler = linkHandler ?? defaultLinkHandler;
    final emojiBuilder = emojiImageBuilder ?? defaultEmojiImageBuilder;
    final emojiBaseSize = baseStyle.fontSize ?? 14;
    for (final node in inlines) {
      children.add(_toSpan(
        node,
        handler,
        emojiBuilder,
        emojiBaseSize,
        context,
        recognizers,
      ));
    }
    return FlattenResult(
      span: TextSpan(style: baseStyle, children: children),
      recognizers: recognizers,
    );
  }

  List<InlineSpan> _build(
    List<InlineNode> nodes,
    LinkActionHandler handler,
    EmojiImageBuilder emojiBuilder,
    double emojiBaseSize,
    BuildContext? context,
    List<GestureRecognizer> recognizers, {
    GestureRecognizer? inheritedRecognizer,
  }) {
    return [
      for (final node in nodes)
        _toSpan(
          node,
          handler,
          emojiBuilder,
          emojiBaseSize,
          context,
          recognizers,
          inheritedRecognizer: inheritedRecognizer,
        ),
    ];
  }

  InlineSpan _toSpan(
    InlineNode node,
    LinkActionHandler handler,
    EmojiImageBuilder emojiBuilder,
    double emojiBaseSize,
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
            emojiBuilder,
            emojiBaseSize,
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
            emojiBuilder,
            emojiBaseSize,
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
          emojiBuilder,
          emojiBaseSize,
          context,
          recognizers,
        ),
      InlineCodeRun(:final text) => _buildInlineCodeSpan(
          text,
          context,
          inheritedRecognizer: inheritedRecognizer,
        ),
      EmojiRun() => _buildEmojiSpan(
          node,
          emojiBuilder,
          emojiBaseSize,
          context,
          inheritedRecognizer: inheritedRecognizer,
        ),
    };
  }

  TextSpan _buildLinkSpan(
    String href,
    List<InlineNode> children,
    LinkActionHandler handler,
    EmojiImageBuilder emojiBuilder,
    double emojiBaseSize,
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
        emojiBuilder,
        emojiBaseSize,
        context,
        recognizers,
        inheritedRecognizer: recognizer,
      ),
    );
  }

  /// 行内代码渲染:monospace + 较小字号 + 主题色派生灰色字 + 灰底。
  ///
  /// 颜色策略:**派生自 ColorScheme**,跟主题统一(legacy 用了固定 hex,
  /// 我们在子包内主动升级 — 任何品牌色 / 自定义 seed 都自动适配):
  /// - 字色 ← `colorScheme.onSurfaceVariant`(中性次要文本)
  /// - 底色 ← `colorScheme.surfaceContainerHighest`(M3 灰底容器)
  ///
  /// 字体/字号沿用 legacy:`FiraCode, monospace` + 0.85em。
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
    // 无 context 时退化到固定 fallback(便于纯 unit test 跳过 widget tree)
    final scheme = context == null ? null : Theme.of(context).colorScheme;
    final fgColor = scheme?.onSurfaceVariant;
    final bgColor = scheme?.surfaceContainerHighest;
    final bg = bgColor == null
        ? null
        : (Paint()
          ..style = PaintingStyle.fill
          ..color = bgColor);
    return TextSpan(
      text: text,
      recognizer: inheritedRecognizer,
      style: TextStyle(
        fontFamily: 'FiraCode',
        fontFamilyFallback: const ['monospace', 'Menlo', 'Courier'],
        fontSize: _inlineCodeFontSize, // baseStyle 14 → 11.9
        color: fgColor,
        background: bg,
      ),
    );
  }

  // 0.85em:相对于父 baseStyle.fontSize。当前实现是绝对值预设,正确做法
  // 是 inherit 父 fontSize 再 * 0.85,留待阶段 5 调整(届时 baseStyle 体系
  // 整理)。14 * 0.85 = 11.9。
  static const _inlineCodeFontSize = 11.9;

  /// Emoji 渲染:WidgetSpan 嵌入图片,尺寸跟随父字号(only-emoji 32dp)。
  ///
  /// 对齐 Discourse CSS:
  /// - `img.emoji`:`width: 1em; height: 1em; vertical-align: middle`
  /// - `img.emoji.only-emoji`:`width: 32px; height: 32px`
  ///
  /// 子包不加载图片,实际渲染由 [EmojiImageBuilder] 注入(主项目用
  /// 独立 emojiImageProvider 缓存池 + CDN 重写)。
  ///
  /// 选区注意:WidgetSpan 默认不参与选区文本,这里通过 `placeholder`
  /// 兜底视觉,实际选区文本由 SelectionArea 自处理(阶段 5 自研选区时
  /// 通过 EmojiRun.name 提供 ":heart:" 作选区文本)。
  ///
  /// recognizer 透传:emoji 嵌套在 LinkRun 子树时,WidgetSpan 没有
  /// `recognizer` 字段(那是 TextSpan 才有的),tap 通过 WidgetSpan
  /// 内部的 GestureDetector 处理。当前实现:link 内 emoji **直接显示
  /// 但不可点**(因为 WidgetSpan 不带 inheritedRecognizer)。阶段 2
  /// 加 mention 节点时统一处理(mention 内的状态 emoji 也是同样问题)。
  WidgetSpan _buildEmojiSpan(
    EmojiRun emoji,
    EmojiImageBuilder emojiBuilder,
    double emojiBaseSize,
    BuildContext? context, {
    GestureRecognizer? inheritedRecognizer,
  }) {
    final size = emoji.isOnlyEmoji ? 32.0 : emojiBaseSize;
    return WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: SizedBox(
        width: size,
        height: size,
        child: Builder(
          builder: (ctx) {
            // 优先用从 flattener 传入的 context(确保 Theme 可访问);
            // 但 WidgetSpan child build 时已有自己的 context,两者通常等价
            return emojiBuilder(context ?? ctx, emoji, size);
          },
        ),
      ),
    );
  }
}
