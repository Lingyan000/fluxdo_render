/// 把 `List<InlineNode>` 压平成 Flutter 的 InlineSpan 树。
///
/// 阶段 1 范围:Text / Em / Strong / LineBreak / Link / InlineCode / Emoji /
/// Mention / Image 九种 + 嵌套样式合并。后续阶段会加更多 inline 节点。
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
import '../render/footnote_handler.dart';
import '../render/image_handler.dart';
import '../render/link_handler.dart';
import '../render/local_date_handler.dart';
import '../render/mention_handler.dart';

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
  /// [mentionTapHandler]:点击 mention chip 跳用户卡的回调(主项目注入)。
  /// null 时用 [defaultMentionTapHandler](仅 debugPrint)。
  /// [imageContentBuilder]:内容图片(非 emoji)渲染 builder。null 时用
  /// [defaultImageContentBuilder](Image.network 兜底)。
  /// [totalImagesInPost]:当前 post 内 ImageRun 总数,透传给 imageBuilder
  /// 用作 gallery viewer 的 totalCount(主项目 Hero / 大图浏览用)。
  /// [context]:link/mention 点击 + emoji 字号探测时传给 handler 用。
  FlattenResult flatten(
    List<InlineNode> inlines,
    TextStyle baseStyle, {
    LinkActionHandler? linkHandler,
    EmojiImageBuilder? emojiImageBuilder,
    MentionTapHandler? mentionTapHandler,
    ImageContentBuilder? imageContentBuilder,
    FootnoteTapHandler? footnoteTapHandler,
    LocalDateBuilder? localDateBuilder,
    int totalImagesInPost = 0,
    BuildContext? context,
  }) {
    final recognizers = <GestureRecognizer>[];
    final children = <InlineSpan>[];
    final handler = linkHandler ?? defaultLinkHandler;
    final emojiBuilder = emojiImageBuilder ?? defaultEmojiImageBuilder;
    final mentionHandler = mentionTapHandler ?? defaultMentionTapHandler;
    final imageBuilder = imageContentBuilder ?? defaultImageContentBuilder;
    final footnoteHandler = footnoteTapHandler ?? defaultFootnoteTapHandler;
    final emojiBaseSize = baseStyle.fontSize ?? 14;
    for (final node in inlines) {
      children.add(_toSpan(
        node,
        handler,
        emojiBuilder,
        mentionHandler,
        imageBuilder,
        footnoteHandler,
        localDateBuilder,
        emojiBaseSize,
        totalImagesInPost,
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
    MentionTapHandler mentionHandler,
    ImageContentBuilder imageBuilder,
    FootnoteTapHandler footnoteHandler,
    LocalDateBuilder? localDateBuilder,
    double emojiBaseSize,
    int totalImagesInPost,
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
          mentionHandler,
          imageBuilder,
          footnoteHandler,

          localDateBuilder,
          emojiBaseSize,
          totalImagesInPost,
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
    MentionTapHandler mentionHandler,
    ImageContentBuilder imageBuilder,
    FootnoteTapHandler footnoteHandler,
    LocalDateBuilder? localDateBuilder,
    double emojiBaseSize,
    int totalImagesInPost,
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
            mentionHandler,
            imageBuilder,
            footnoteHandler,

            localDateBuilder,
            emojiBaseSize,
            totalImagesInPost,
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
            mentionHandler,
            imageBuilder,
            footnoteHandler,

            localDateBuilder,
            emojiBaseSize,
            totalImagesInPost,
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
          mentionHandler,
          imageBuilder,
          footnoteHandler,

          localDateBuilder,
          emojiBaseSize,
          totalImagesInPost,
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
      MentionRun() => _buildMentionSpan(
          node,
          emojiBuilder,
          mentionHandler,
          emojiBaseSize,
          context,
        ),
      ImageRun() => _buildImageSpan(
          node,
          imageBuilder,
          totalImagesInPost,
          context,
        ),
      SpoilerRun(:final children) => _buildSpoilerSpan(
          children,
          handler,
          emojiBuilder,
          mentionHandler,
          imageBuilder,
          footnoteHandler,

          localDateBuilder,
          emojiBaseSize,
          totalImagesInPost,
          context,
          recognizers,
        ),
      FootnoteRefRun() => _buildFootnoteRefSpan(
          node,
          footnoteHandler,
          context,
        ),
      LocalDateRun() => _buildLocalDateSpan(
          node,
          localDateBuilder,
        ),
      ClickCountRun() => _buildClickCountSpan(node),
    };
  }

  TextSpan _buildLinkSpan(
    String href,
    List<InlineNode> children,
    LinkActionHandler handler,
    EmojiImageBuilder emojiBuilder,
    MentionTapHandler mentionHandler,
    ImageContentBuilder imageBuilder,
    FootnoteTapHandler footnoteHandler,
    LocalDateBuilder? localDateBuilder,
    double emojiBaseSize,
    int totalImagesInPost,
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
        mentionHandler,
        imageBuilder,
        footnoteHandler,

        localDateBuilder,
        emojiBaseSize,
        totalImagesInPost,
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
  /// 子包不加载图片,实际渲染由 [EmojiImageBuilder] 注入;**约定 builder
  /// 自行用 size 约束尺寸**,这里不外包 SizedBox(否则 fallback 文本
  /// 会被裁剪)。
  ///
  /// **垂直对齐**:用 [PlaceholderAlignment.middle] 让 widget 中点对齐
  /// 字号高度的中线 + 减半行 leading 微调。
  ///
  /// 之前用 baseline + alphabetic 在含中文行里会偏低(中文 visual baseline
  /// 比 alphabetic 高);middle 在纯拉丁行里会偏高(拉丁 x-height 在
  /// 行中线下方)。两者都不完美,中文场景 middle 视觉接受度更高
  /// (Discourse 也是 vertical-align: middle)。
  ///
  /// 选区注意:WidgetSpan 默认不参与选区文本,实际选区文本由 SelectionArea
  /// 自处理(阶段 5 自研选区时通过 EmojiRun.name 提供 ":heart:" 作选区文本)。
  ///
  /// recognizer 透传:emoji 嵌套在 LinkRun 子树时,WidgetSpan 没有
  /// `recognizer` 字段,tap 通过 WidgetSpan 内部的 GestureDetector 处理。
  /// 当前实现:link 内 emoji **直接显示但不可点**。阶段 2 加 mention 节点
  /// 时统一处理(mention 内的状态 emoji 也是同样问题)。
  WidgetSpan _buildEmojiSpan(
    EmojiRun emoji,
    EmojiImageBuilder emojiBuilder,
    double emojiBaseSize,
    BuildContext? context, {
    GestureRecognizer? inheritedRecognizer,
  }) {
    final size = emoji.isOnlyEmoji ? 32.0 : emojiBaseSize;
    // legacy 对齐:普通 emoji 左右各 2px;only-emoji 左右 1px + 上下 0.5em
    final margin = emoji.isOnlyEmoji
        ? EdgeInsets.symmetric(horizontal: 1.0, vertical: emojiBaseSize * 0.5)
        : const EdgeInsets.symmetric(horizontal: 2.0);
    return WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: Padding(
        padding: margin,
        child: Builder(
          builder: (ctx) {
            return emojiBuilder(context ?? ctx, emoji, size);
          },
        ),
      ),
    );
  }

  /// Mention 渲染:chip 样式(灰底圆角 + primary 字 + 0.82em),
  /// 可选状态 emoji 跟在用户名右侧。点击跳用户卡(MentionTapHandler 注入)。
  ///
  /// 样式对齐 legacy `mention_builder.dart::buildMention`:
  ///   font-size: baseStyle.fontSize * 0.82
  ///   padding: horizontal 6, vertical 1
  ///   border-radius: 10
  ///   color: theme.colorScheme.primary
  ///   background: ColorScheme.surfaceContainerHigh(派生升级,legacy 是 hex)
  ///   status emoji: 字号 * 1.2 跟在用户名右
  ///
  /// 用 WidgetSpan 而非 TextSpan 因为是个有内部 padding/border 的整体
  /// chip,不参与文字 baseline 对齐(legacy 同样走 InlineCustomWidget)。
  WidgetSpan _buildMentionSpan(
    MentionRun mention,
    EmojiImageBuilder emojiBuilder,
    MentionTapHandler mentionHandler,
    double emojiBaseSize,
    BuildContext? context,
  ) {
    return WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: Builder(
        builder: (ctx) {
          final effectiveCtx = context ?? ctx;
          final scheme = Theme.of(effectiveCtx).colorScheme;
          final fontSize = emojiBaseSize * 0.82;
          final statusEmojiSize = fontSize * 1.2;
          return GestureDetector(
            onTap: () => mentionHandler(
              effectiveCtx,
              mention.username,
              mention.href,
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '@${mention.username}',
                    style: TextStyle(
                      color: scheme.primary,
                      fontSize: fontSize,
                      height: 1.0,
                    ),
                  ),
                  if (mention.statusEmoji != null) ...[
                    const SizedBox(width: 2),
                    emojiBuilder(
                      effectiveCtx,
                      mention.statusEmoji!,
                      statusEmojiSize,
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// 内容图片渲染:WidgetSpan 嵌入图片,大小完全由 builder 决定。
  ///
  /// 跟 EmojiRun 不同:emoji 是 1em / 32dp 固定尺寸,这里不限制 ——
  /// `<img width=600 height=400>` 应该撑满 600x400,但段宽不够时
  /// builder 自己处理(主项目通常用 BoxFit.contain + 外层 Stack 截宽)。
  ///
  /// 对齐 [PlaceholderAlignment.middle](跟 emoji 一致,避免基线偏移)。
  ///
  /// [totalImagesInPost] 透传给 builder,主项目用它构造 gallery viewer 的
  /// totalCount(配合 [ImageRun.indexInPost] 算 Hero tag + currentIndex)。
  WidgetSpan _buildImageSpan(
    ImageRun image,
    ImageContentBuilder imageBuilder,
    int totalImagesInPost,
    BuildContext? context,
  ) {
    // lightbox 图(典型形态:Discourse cooked 上传图)单独成行,
    // 加上下小 margin 区隔相邻图片 / 文字。普通 inline <img> 不加。
    final isLightbox = image.lightboxUrl != null;
    final child = Builder(
      builder: (ctx) =>
          imageBuilder(context ?? ctx, image, totalImagesInPost),
    );
    return WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: isLightbox
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: child,
            )
          : child,
    );
  }

  /// 行内 spoiler 渲染:WidgetSpan + _SpoilerInlineWidget。
  ///
  /// 未揭示时显示同色色块(看起来一片黑/灰),点击展开后内部子节点
  /// 走 InlineFlattener 重新 flatten 渲染。
  ///
  /// 注意:flatten 期间无法用 const InlineFlattener() 套子节点(因为
  /// 需要透传 handlers),所以 spoiler 子树用 Text.rich + _build 再展平,
  /// recognizer 仍累计到外层 recognizers 列表里(由 InlineSpanText 统一
  /// dispose)。
  WidgetSpan _buildSpoilerSpan(
    List<InlineNode> children,
    LinkActionHandler handler,
    EmojiImageBuilder emojiBuilder,
    MentionTapHandler mentionHandler,
    ImageContentBuilder imageBuilder,
    FootnoteTapHandler footnoteHandler,
    LocalDateBuilder? localDateBuilder,
    double emojiBaseSize,
    int totalImagesInPost,
    BuildContext? context,
    List<GestureRecognizer> recognizers,
  ) {
    // 子节点提前 flatten 成 InlineSpan list,避免 _SpoilerInlineWidget
    // 内部还要依赖 InlineFlattener
    final spans = _build(
      children,
      handler,
      emojiBuilder,
      mentionHandler,
      imageBuilder,
      footnoteHandler,

      localDateBuilder,
      emojiBaseSize,
      totalImagesInPost,
      context,
      recognizers,
    );
    return WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: _SpoilerInlineWidget(spans: spans),
    );
  }

  /// 脚注引用渲染:`[N]` 蓝色上标 + 点击调主项目 [footnoteTapHandler]
  /// 弹 popover(子包不依赖 popover 包)。
  ///
  /// 视觉对齐 legacy `_FootnoteRefWidget`:
  ///   Padding(horizontal 2, vertical 6) + Transform.translate(0, -3)
  ///   蓝色 / fontSize 11 / w600 / height 1
  WidgetSpan _buildFootnoteRefSpan(
    FootnoteRefRun node,
    FootnoteTapHandler footnoteHandler,
    BuildContext? context,
  ) {
    return WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: _FootnoteRefWidget(
        node: node,
        handler: footnoteHandler,
      ),
    );
  }
}

/// 行内脚注引用 widget。
class _FootnoteRefWidget extends StatelessWidget {
  const _FootnoteRefWidget({required this.node, required this.handler});
  final FootnoteRefRun node;
  final FootnoteTapHandler handler;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => handler(context, node.fnId, node.contentHtml),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
        child: Transform.translate(
          offset: const Offset(0, -3),
          child: Text(
            '[${node.number}]',
            style: TextStyle(
              color: scheme.primary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}

/// 行内 spoiler 揭示交互 widget。
class _SpoilerInlineWidget extends StatefulWidget {
  const _SpoilerInlineWidget({required this.spans});
  final List<InlineSpan> spans;

  @override
  State<_SpoilerInlineWidget> createState() => _SpoilerInlineWidgetState();
}

class _SpoilerInlineWidgetState extends State<_SpoilerInlineWidget> {
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final richText = Text.rich(TextSpan(children: widget.spans));
    if (_revealed) {
      // 揭示后给一个浅底点击痕迹(legacy 揭示后仍可点击隐藏)
      return GestureDetector(
        onTap: () => setState(() => _revealed = false),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(3),
          ),
          child: richText,
        ),
      );
    }
    // 遮蔽态:文字本身 + 上方覆盖同色块。用 Stack + IgnorePointer 让 tap
    // 落到 GestureDetector 上,文本不参与选区(选区在阶段 5 自研)
    return GestureDetector(
      onTap: () => setState(() => _revealed = true),
      child: Stack(
        children: [
          // 用 visibility:hidden(Opacity 0.0)占好布局,让色块尺寸自动撑开
          Opacity(opacity: 0.0, child: richText),
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: scheme.onSurface,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

extension on InlineFlattener {
  /// 本地日期渲染:优先调主项目注入的 [localDateBuilder](带时区换算 +
  /// popover);fallback 显示 fallbackText(服务端预渲染)+ 时钟图标。
  ///
  /// 子包不绑 `timezone` / `flutter_timezone` / `popover` 等重依赖。
  WidgetSpan _buildLocalDateSpan(
    LocalDateRun node,
    LocalDateBuilder? localDateBuilder,
  ) {
    return WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: Builder(
        builder: (context) {
          final custom = localDateBuilder?.call(context, node);
          if (custom != null) return custom;
          return _LocalDateFallbackWidget(node: node);
        },
      ),
    );
  }
}

/// 子包内置本地日期 fallback widget — 直接显示服务端预渲染文本 +
/// 时钟图标(无时区换算 / 无 popover)。主项目接入 LocalDateBuilder 后
/// 会被替换。
class _LocalDateFallbackWidget extends StatelessWidget {
  const _LocalDateFallbackWidget({required this.node});
  final LocalDateRun node;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fontSize = theme.textTheme.bodyMedium?.fontSize ?? 14;
    final text = node.fallbackText.isNotEmpty
        ? node.fallbackText
        : (node.time == null ? node.date : '${node.date} ${node.time}');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            node.countdown ? Icons.schedule_rounded : Icons.public_rounded,
            size: fontSize * 0.95,
            color: scheme.primary,
          ),
          const SizedBox(width: 3),
          Text(
            text,
            style: TextStyle(color: scheme.primary, fontSize: fontSize),
          ),
        ],
      ),
    );
  }
}

extension on InlineFlattener {
  /// 链接点击数 chip 渲染(对齐 legacy `buildClickCountWidget`)。
  /// 小灰底圆角(radius 10),h5/v1 padding,10px 字号。
  WidgetSpan _buildClickCountSpan(ClickCountRun node) {
    return WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: _ClickCountWidget(count: node.count),
    );
  }
}

/// 链接点击数 chip widget(纯展示,无 callback)。
class _ClickCountWidget extends StatelessWidget {
  const _ClickCountWidget({required this.count});
  final String count;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor =
        isDark ? const Color(0xFF3A3D47) : const Color(0xFFE8EBEF);
    final textColor =
        isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        count,
        style: TextStyle(color: textColor, fontSize: 10),
      ),
    );
  }
}
