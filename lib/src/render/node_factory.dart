/// 把 BlockNode 渲染成 Flutter Widget。
///
/// 阶段 1 范围:Paragraph + Heading,行内含 Text/Em/Strong/LineBreak/Link/
/// InlineCode/Emoji。
/// 设计上预留 sub-class 扩展点 — 主项目场景里(用户卡 bio / 通知 / AI 分享卡
/// 等)可以继承 NodeFactory 在 build* 方法里加 wrapper(如:简化版不让点
/// 链接、AI 分享卡内禁用图片)。
///
/// 后续阶段加新 BlockNode 时,新增对应 buildXxx 并在 build dispatch 里
/// 加 case;sealed class 编译期保证不漏。

library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../flatten/inline_flattener.dart';
import '../node/node.dart';
import 'code_block_handler.dart';
import 'emoji_handler.dart';
import 'image_handler.dart';
import 'inline_span_text.dart';
import 'link_handler.dart';
import 'mention_handler.dart';
import 'onebox_handler.dart';
import 'quote_avatar_handler.dart';

class NodeFactory {
  NodeFactory({
    InlineFlattener? inlineFlattener,
    this.linkHandler,
    this.emojiImageBuilder,
    this.mentionTapHandler,
    this.imageContentBuilder,
    this.codeBlockHighlighter,
    this.quoteAvatarBuilder,
    this.oneboxBuilder,
    this.totalImagesInPost = 0,
    this.compact = false,
  }) : _inlineFlattener = inlineFlattener ?? const InlineFlattener();

  final InlineFlattener _inlineFlattener;

  /// 链接点击 callback,主项目注入。
  /// 不传时用 [defaultLinkHandler](仅 debugPrint)。
  final LinkActionHandler? linkHandler;

  /// Emoji 图片 builder,主项目注入。
  /// 不传时用 [defaultEmojiImageBuilder](Image.network 兜底,无缓存池)。
  final EmojiImageBuilder? emojiImageBuilder;

  /// Mention chip 点击跳用户卡 callback,主项目注入。
  /// 不传时用 [defaultMentionTapHandler](仅 debugPrint)。
  final MentionTapHandler? mentionTapHandler;

  /// 内容图片(非 emoji)builder,主项目注入。
  /// 不传时用 [defaultImageContentBuilder](Image.network + broken-image 占位)。
  final ImageContentBuilder? imageContentBuilder;

  /// 代码块高亮 builder,主项目注入(主项目用 HighlighterService + Mermaid)。
  /// 不传时用 [defaultCodeBlockHighlighter](纯 monospace 无高亮)。
  final CodeBlockHighlighter? codeBlockHighlighter;

  /// 引用卡头像 builder,主项目注入(主项目用 SmartAvatar 走鉴权 +
  /// CDN 重写)。不传时用 [defaultQuoteAvatarBuilder](首字母 chip)。
  final QuoteAvatarBuilder? quoteAvatarBuilder;

  /// Onebox 卡片 builder,主项目注入(根据 OneboxKind dispatch 到 6 种
  /// 子 builder:github / video / social / tech / user / default)。
  /// 返回 null 时子包用内置通用卡片(标题 + 描述 + 缩略图)。
  final OneboxBuilder? oneboxBuilder;

  /// 当前 post 内 ImageRun 总数,由 FluxdoRender 在 parse 完成后算出
  /// 并传入。透传到 ImageContentBuilder,主项目用于构造 gallery viewer。
  ///
  /// 调用方手动构造 NodeFactory(给 user card / AI 分享卡 等场景)时,
  /// 若不需要 image 路由,保持默认 0 即可。
  final int totalImagesInPost;

  /// **紧凑模式**:在容器内(blockquote / quote_card / spoiler 等)递归
  /// 渲染子节点时,paragraph 不再加 `1em 0` 上下 margin,避免与容器
  /// 自己的 padding 叠加产生过大间距。
  ///
  /// 对齐 legacy `DiscourseHtmlContent(compact: true)` 用法。
  final bool compact;

  /// 派生一个"紧凑"版本(给 buildBlockquote / buildQuoteCard / 等
  /// 渲染子节点用)。所有 handlers / builders 完全相同,只是 [compact]
  /// 切到 true。
  NodeFactory _compactCopy() {
    if (compact) return this;
    return NodeFactory(
      inlineFlattener: _inlineFlattener,
      linkHandler: linkHandler,
      emojiImageBuilder: emojiImageBuilder,
      mentionTapHandler: mentionTapHandler,
      imageContentBuilder: imageContentBuilder,
      codeBlockHighlighter: codeBlockHighlighter,
      quoteAvatarBuilder: quoteAvatarBuilder,
      oneboxBuilder: oneboxBuilder,
      totalImagesInPost: totalImagesInPost,
      compact: true,
    );
  }

  /// 入口 dispatch — sealed class exhaustive switch。
  Widget build(BuildContext context, BlockNode node) {
    return switch (node) {
      ParagraphNode() => buildParagraph(context, node),
      HeadingNode() => buildHeading(context, node),
      ListNode() => buildList(context, node),
      BlockquoteNode() => buildBlockquote(context, node),
      HorizontalRuleNode() => buildHorizontalRule(context, node),
      CodeBlockNode() => buildCodeBlock(context, node),
      QuoteCardNode() => buildQuoteCard(context, node),
      SpoilerBlockNode() => buildSpoilerBlock(context, node),
      OneboxNode() => buildOnebox(context, node),
    };
  }

  /// 段落渲染 — InlineSpanText 自动管 GestureRecognizer 生命周期。
  ///
  /// 子类可 override 实现段落级别的定制(如调字号、加 margin)。
  ///
  /// margin 对齐 legacy(fwfh `_tagP`):`1em 0`(上下各一个 em)。
  /// **[compact] 模式下 margin 为 0**(嵌套在容器内,如 blockquote /
  /// quote_card,容器自己已加 padding,不再叠加)。
  Widget buildParagraph(BuildContext context, ParagraphNode node) {
    final theme = Theme.of(context);
    final baseStyle = theme.textTheme.bodyMedium ?? const TextStyle();
    final em = baseStyle.fontSize ?? 14;
    // image-only 段落(全是 ImageRun / LineBreakRun,无真文字)用更小的
    // vertical padding。否则文本 1em margin 叠加 image 自身上下 padding,
    // 与前后段距离过大,跟 fwfh margin-collapsing 行为差距明显。
    final isImageOnly = node.inlines.isNotEmpty &&
        node.inlines.every((n) => n is ImageRun || n is LineBreakRun);
    final vertical = compact
        ? 0.0
        : isImageOnly
            ? 4.0
            : em;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: vertical),
      child: InlineSpanText(
        inlines: node.inlines,
        baseStyle: baseStyle,
        flattener: _inlineFlattener,
        linkHandler: linkHandler,
        emojiImageBuilder: emojiImageBuilder,
        mentionTapHandler: mentionTapHandler,
        imageContentBuilder: imageContentBuilder,
        totalImagesInPost: totalImagesInPost,
      ),
    );
  }

  /// 标题渲染 — 字号按 level 决定,默认值参考浏览器 UA stylesheet。
  ///
  /// h1=2em / h2=1.5em / h3=1.17em / h4=1em / h5=0.83em / h6=0.67em
  /// 字重统一 bold。垂直 padding 按 CSS heading margin(em 倍数)。
  Widget buildHeading(BuildContext context, HeadingNode node) {
    final theme = Theme.of(context);
    final baseStyle = theme.textTheme.bodyMedium ?? const TextStyle();
    final em = baseStyle.fontSize ?? 14;
    final scale = _headingScale[node.level - 1];
    final headingStyle = baseStyle.copyWith(
      fontSize: em * scale,
      fontWeight: FontWeight.bold,
      height: 1.2,
    );
    return Padding(
      padding: EdgeInsets.symmetric(
        vertical: em * _headingMargin[node.level - 1],
      ),
      child: InlineSpanText(
        inlines: node.inlines,
        baseStyle: headingStyle,
        flattener: _inlineFlattener,
        linkHandler: linkHandler,
        emojiImageBuilder: emojiImageBuilder,
        mentionTapHandler: mentionTapHandler,
        imageContentBuilder: imageContentBuilder,
        totalImagesInPost: totalImagesInPost,
      ),
    );
  }

  // 索引 0 对应 h1
  static const _headingScale = [2.0, 1.5, 1.17, 1.0, 0.83, 0.67];

  // CSS heading margin(em 倍数,top/bottom 各一份)
  static const _headingMargin = [0.67, 0.83, 1.0, 1.33, 1.67, 2.33];

  /// 列表渲染 — `<ul>` / `<ol>`,可递归嵌套子 list。
  ///
  /// 样式对齐 legacy(DiscourseHtmlContentWidget customStylesBuilder):
  ///   ul/ol: padding-left 20, margin 上下 8
  ///   li:    margin 上下 4, line-height 1.5
  /// 有序列表 marker 用 `FontFeature.tabularFigures`(等宽数字)
  /// 避免 "1." 比 "10." 窄导致对齐错位。
  ///
  /// 嵌套子列表用 `ListItem.children` 持有,渲染时递归 buildList。
  /// **嵌套层(depth > 0)跳过 outer vertical padding**:CSS 相邻 margin
  /// 折叠取大,Flutter Column padding 累加 —— 不跳过会出现 8(嵌套上)
  /// + 4(父 li 下)的额外空白,视觉上像多了一行。
  Widget buildList(BuildContext context, ListNode node) {
    final theme = Theme.of(context);
    final baseStyle = theme.textTheme.bodyMedium ?? const TextStyle();
    return Padding(
      padding: EdgeInsets.symmetric(vertical: node.depth == 0 ? 8 : 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int i = 0; i < node.items.length; i++)
            _buildListItem(context, node, i, baseStyle),
        ],
      ),
    );
  }

  Widget _buildListItem(
    BuildContext context,
    ListNode list,
    int index,
    TextStyle baseStyle,
  ) {
    final item = list.items[index];
    final markerStyle = baseStyle.copyWith(
      height: 1.5,
      fontFeatures: list.ordered
          ? const [FontFeature.tabularFigures()]
          : null,
    );
    final markerText = list.ordered ? '${index + 1}.' : '•'; // bullet
    final hasChildren = item.children != null;
    return Padding(
      // 有嵌套子 list 时取消底部 padding,避免 inline 行和子 list 之间空一截
      padding: EdgeInsets.fromLTRB(20, 4, 0, hasChildren ? 0 : 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // marker 宽度按"两位数字 + 点"预算,确保 9. 10. 对齐
              SizedBox(
                width: list.ordered ? 24 : 16,
                child: Text(markerText, style: markerStyle),
              ),
              Expanded(
                child: InlineSpanText(
                  inlines: item.inlines,
                  baseStyle: baseStyle.copyWith(height: 1.5),
                  flattener: _inlineFlattener,
                  linkHandler: linkHandler,
                  emojiImageBuilder: emojiImageBuilder,
                  mentionTapHandler: mentionTapHandler,
                  imageContentBuilder: imageContentBuilder,
                  totalImagesInPost: totalImagesInPost,
                ),
              ),
            ],
          ),
          // 嵌套子 list 递归渲染
          if (hasChildren)
            for (final sub in item.children!) buildList(context, sub),
        ],
      ),
    );
  }

  /// 引用块渲染 — `<blockquote>`,内部 BlockNode 递归 build。
  ///
  /// 样式对齐 legacy(`blockquote_builder.dart` 普通引用分支):
  ///   margin 上下 8
  ///   padding L 12 / 上下 8 / R 12
  ///   背景 colorScheme.surfaceContainerHighest @ 0.3
  ///   左边 4px outline 竖条
  ///   右上 / 右下 圆角 4
  ///
  /// 子节点用 DefaultTextStyle 注入 onSurfaceVariant + height 1.5,
  /// 这样子 ParagraphNode 渲染时跟随这个色调(让引用块整体偏次要文本色)。
  Widget buildBlockquote(BuildContext context, BlockquoteNode node) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
        border: Border(
          left: BorderSide(
            color: scheme.outline,
            width: 4,
          ),
        ),
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(4),
          bottomRight: Radius.circular(4),
        ),
      ),
      child: DefaultTextStyle.merge(
        style: TextStyle(
          color: scheme.onSurfaceVariant,
          height: 1.5,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 容器内子节点走 compact factory(消除嵌套 paragraph 多余 margin)
            for (final child in node.children)
              _compactCopy().build(context, child),
          ],
        ),
      ),
    );
  }

  /// 分割线 — `<hr>`。
  ///
  /// 样式对齐 legacy:vertical padding 12 + 1px 高线 +
  /// `colorScheme.outlineVariant @ 0.5`(派生)。
  Widget buildHorizontalRule(
    BuildContext context,
    HorizontalRuleNode node,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Container(
        height: 1,
        color: scheme.outlineVariant.withValues(alpha: 0.5),
      ),
    );
  }

  /// 代码块渲染 — `<pre><code>`。
  ///
  /// 视觉对齐 legacy `code_block_builder.dart`(简化版,无行号/全屏/分享):
  ///   外:Container 灰底 surfaceContainer + 圆角 8 + margin 上下 8
  ///   顶栏:Row(语言 chip(灰色文字 12px 左对齐)+ 复制按钮)
  ///   主体:横向 SingleChildScrollView + monospace 内容
  ///
  /// 高亮 / mermaid 由 [codeBlockHighlighter] callback 接管;不传时纯
  /// monospace 显示。
  Widget buildCodeBlock(BuildContext context, CodeBlockNode node) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final highlighter = codeBlockHighlighter ?? defaultCodeBlockHighlighter;
    final langLabel = (node.language ?? 'TEXT').toUpperCase();
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 顶栏:语言 + 复制按钮
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
            child: Row(
              children: [
                Text(
                  langLabel,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: scheme.onSurfaceVariant,
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                _CopyButton(code: node.code),
              ],
            ),
          ),
          // 分隔线
          Container(
            height: 1,
            color: scheme.outlineVariant.withValues(alpha: 0.3),
          ),
          // 主体:横向滚动 + highlighter widget。
          // 限高 400px 避免长代码撑爆 ListView(legacy 同套路);
          // 含行号列(legacy 同套路),保持基线对齐 + 选择 disabled。
          _CodeBlockBody(
            code: node.code,
            language: node.language,
            highlighter: highlighter,
          ),
        ],
      ),
    );
  }

  /// 引用卡渲染 — `<aside class="quote">`(Discourse 经典"@回复")。
  ///
  /// 样式对齐 legacy `quote_card_builder.dart`:
  ///   外容器:跟 buildBlockquote 同款(灰底 + 左 4px 竖条 + 右上右下圆角)
  ///   顶部:头像(radius 12)+ `username:` + 可选标题(主色,可点)
  ///   内容:子 BlockNode 递归 build,DefaultTextStyle 注入 onSurfaceVariant
  ///
  /// 标题 onTap 走 [linkHandler] + titleHref(主项目走 launchContentLink)。
  /// avatar 走 [quoteAvatarBuilder] callback,默认首字母 chip。
  Widget buildQuoteCard(BuildContext context, QuoteCardNode node) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final avatarBuilder = quoteAvatarBuilder ?? defaultQuoteAvatarBuilder;
    final usernameStyle = theme.textTheme.labelLarge?.copyWith(
      color: scheme.onSurfaceVariant,
      fontWeight: FontWeight.w500,
    );
    final titleStyle = theme.textTheme.labelMedium?.copyWith(
      height: 1.2,
      color: scheme.primary,
    );
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
        border: Border(
          left: BorderSide(color: scheme.outline, width: 4),
        ),
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(4),
          bottomRight: Radius.circular(4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 顶部:头像 + username + 可选标题
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Row(
              children: [
                avatarBuilder(context, node.username, node.avatarUrl, 24),
                const SizedBox(width: 8),
                Text(
                  '${node.username}:',
                  style: usernameStyle,
                ),
                if (node.titleText != null) ...[
                  const SizedBox(width: 4),
                  Expanded(
                    child: _QuoteTitle(
                      text: node.titleText!,
                      href: node.titleHref,
                      style: titleStyle,
                      onTap: node.titleHref == null || linkHandler == null
                          ? null
                          : () => linkHandler!(context, node.titleHref!),
                    ),
                  ),
                ],
              ],
            ),
          ),
          // 内容
          if (node.children.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: DefaultTextStyle.merge(
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  height: 1.5,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // quote_card 内子节点走 compact factory
                    for (final child in node.children)
                      _compactCopy().build(context, child),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 块级 spoiler 渲染 — `<div class="spoiler">`。
  ///
  /// 视觉(子包简化版,无粒子动画):
  ///   未揭示:灰底 + 中心 "点击显示剧透" + 锁图标
  ///   揭示后:子节点正常渲染,左边 4px primary 竖条提示"已揭示"
  ///
  /// 状态由 _SpoilerBlockWidget 内部管。
  Widget buildSpoilerBlock(BuildContext context, SpoilerBlockNode node) {
    return _SpoilerBlockWidget(
      // spoiler 内子节点走 compact factory(消除嵌套 paragraph 多余 margin)
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final c in node.children) _compactCopy().build(context, c),
        ],
      ),
    );
  }

  /// Onebox 卡片渲染。优先走主项目注入的 [oneboxBuilder](dispatch 到
  /// 6 种子 builder);返回 null 时 fallback 到子包内置通用卡片(对齐
  /// legacy `default_onebox_builder`:favicon + 来源 + 标题 + 描述 +
  /// 缩略图)。
  Widget buildOnebox(BuildContext context, OneboxNode node) {
    final custom = oneboxBuilder?.call(context, node);
    if (custom != null) return custom;
    return _DefaultOneboxCard(
      node: node,
      onTap: () {
        final url = node.url;
        if (url != null && url.isNotEmpty && linkHandler != null) {
          linkHandler!(context, url);
        }
      },
    );
  }
}

/// 子包内置 Onebox 通用卡片(主项目不注入 builder 时的 fallback)。
///
/// 视觉对齐 legacy `default_onebox_builder.dart`:
///   外:Container 灰底 surfaceContainerHighest @ 0.5 + 圆角 8 + outline border
///   顶:来源行(favicon + sourceName)
///   主体:标题(titleMedium 加粗) + 描述(bodySmall onSurfaceVariant)
///     + 右侧缩略图 80x80(若有 thumbnailUrl)
class _DefaultOneboxCard extends StatelessWidget {
  const _DefaultOneboxCard({required this.node, required this.onTap});
  final OneboxNode node;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant, width: 1),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (node.sourceName != null || node.faviconUrl != null) ...[
                  _SourceRow(
                    faviconUrl: node.faviconUrl,
                    sourceName: node.sourceName,
                  ),
                  const SizedBox(height: 8),
                ],
                _Body(
                  title: node.title,
                  description: node.description,
                  thumbnailUrl: node.thumbnailUrl,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SourceRow extends StatelessWidget {
  const _SourceRow({required this.faviconUrl, required this.sourceName});
  final String? faviconUrl;
  final String? sourceName;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        if (faviconUrl != null && faviconUrl!.isNotEmpty) ...[
          // 子包不依赖任何 image provider,fallback 直接 Image.network
          // 主项目接入 oneboxBuilder 时会走 emojiImageProvider /
          // discourseImageProvider 体系,这里只是兜底
          SizedBox(
            width: 16,
            height: 16,
            child: Image.network(
              faviconUrl!,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => Icon(
                Icons.public,
                size: 14,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 6),
        ],
        if (sourceName != null && sourceName!.isNotEmpty)
          Flexible(
            child: Text(
              sourceName!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.title,
    required this.description,
    required this.thumbnailUrl,
  });
  final String? title;
  final String? description;
  final String? thumbnailUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasThumb = thumbnailUrl != null && thumbnailUrl!.isNotEmpty;
    final textCol = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (title != null && title!.isNotEmpty) ...[
          Text(
            title!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
        ],
        if (description != null && description!.isNotEmpty)
          Text(
            description!,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
    if (!hasThumb) return textCol;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: textCol),
        const SizedBox(width: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            width: 80,
            height: 80,
            child: Image.network(
              thumbnailUrl!,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                color: theme.colorScheme.surfaceContainerHigh,
                alignment: Alignment.center,
                child: Icon(
                  Icons.broken_image_outlined,
                  size: 24,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
///
/// 设计跟 legacy `_CodeBlockWidget.build` 对齐(简化版,无 mermaid /
/// 长按选择上下文):
/// - 行号列固定宽,与代码同步垂直滚动
/// - 代码区水平滚动,垂直 RawScrollbar
/// - 短代码自然撑开;超过 400px 高度后开始垂直滚
class _CodeBlockBody extends StatefulWidget {
  const _CodeBlockBody({
    required this.code,
    required this.language,
    required this.highlighter,
  });

  final String code;
  final String? language;
  final CodeBlockHighlighter highlighter;

  @override
  State<_CodeBlockBody> createState() => _CodeBlockBodyState();
}

class _CodeBlockBodyState extends State<_CodeBlockBody> {
  final _vController = ScrollController();
  final _hController = ScrollController();
  final _lineNumberVController = ScrollController();

  @override
  void initState() {
    super.initState();
    _vController.addListener(_syncLineNumberScroll);
  }

  @override
  void dispose() {
    _vController.removeListener(_syncLineNumberScroll);
    _vController.dispose();
    _hController.dispose();
    _lineNumberVController.dispose();
    super.dispose();
  }

  void _syncLineNumberScroll() {
    if (_lineNumberVController.hasClients) {
      _lineNumberVController.jumpTo(_vController.offset);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final scheme = theme.colorScheme;

    final lines = widget.code.split('\n');
    final lineCount = lines.length;
    final padWidth = lineCount.toString().length;
    // 行号列宽 = 数字宽度(单字符 9px monospace 估算)+ 左右 padding 24
    final lineNumberWidth = padWidth * 9.0 + 24;

    // 估算高度:行高 13*1.5 = 19.5,+ 上下 padding 12*2
    const lineHeight = 13.0 * 1.5;
    const verticalPadding = 24.0;
    final contentHeight = lineCount * lineHeight + verticalPadding;
    final estimatedHeight = contentHeight.clamp(0.0, 400.0);

    final lineNumberStyle = TextStyle(
      fontFamily: 'FiraCode',
      fontFamilyFallback: const ['monospace', 'Menlo', 'Courier'],
      fontSize: 13,
      height: 1.5,
      color: isDark
          ? Colors.white.withValues(alpha: 0.35)
          : Colors.black.withValues(alpha: 0.35),
    );
    final borderColor = scheme.outlineVariant.withValues(alpha: 0.3);
    final thumbColor = (isDark ? Colors.white : Colors.black)
        .withValues(alpha: 0.15);

    return SizedBox(
      height: estimatedHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 行号列(固定宽,跟随主体垂直滚)
          Container(
            width: lineNumberWidth,
            decoration: BoxDecoration(
              border: Border(right: BorderSide(color: borderColor)),
              color: isDark
                  ? Colors.white.withValues(alpha: 0.02)
                  : Colors.black.withValues(alpha: 0.02),
            ),
            child: SelectionContainer.disabled(
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(context).copyWith(
                  scrollbars: false,
                ),
                child: SingleChildScrollView(
                  controller: _lineNumberVController,
                  physics: const NeverScrollableScrollPhysics(),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 8,
                    ),
                    child: Text(
                      List.generate(
                        lineCount,
                        (i) => (i + 1).toString().padLeft(padWidth),
                      ).join('\n'),
                      style: lineNumberStyle,
                      textAlign: TextAlign.right,
                    ),
                  ),
                ),
              ),
            ),
          ),
          // 代码内容(双向滚动:垂直主体 + 水平内嵌)
          Expanded(
            child: RawScrollbar(
              controller: _vController,
              thumbVisibility: false,
              thickness: 4,
              radius: const Radius.circular(2),
              padding: const EdgeInsets.only(right: 2, top: 2, bottom: 2),
              thumbColor: thumbColor,
              child: SingleChildScrollView(
                controller: _vController,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  controller: _hController,
                  padding: const EdgeInsets.all(12),
                  child: widget.highlighter(
                    context,
                    widget.code,
                    widget.language,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 块级 spoiler 揭示交互 widget。
class _SpoilerBlockWidget extends StatefulWidget {
  const _SpoilerBlockWidget({required this.child});
  final Widget child;

  @override
  State<_SpoilerBlockWidget> createState() => _SpoilerBlockWidgetState();
}

class _SpoilerBlockWidgetState extends State<_SpoilerBlockWidget> {
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (_revealed) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
          border: Border(
            left: BorderSide(color: scheme.primary, width: 4),
          ),
          borderRadius: const BorderRadius.only(
            topRight: Radius.circular(4),
            bottomRight: Radius.circular(4),
          ),
        ),
        child: GestureDetector(
          onTap: () => setState(() => _revealed = false),
          child: widget.child,
        ),
      );
    }
    return GestureDetector(
      onTap: () => setState(() => _revealed = true),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: scheme.outlineVariant,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.visibility_off_outlined,
              size: 16,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Text(
              '剧透内容,点击显示',
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 引用卡标题文本(只是一行 InkWell-y 可点 Text;主色 + 省略)。
class _QuoteTitle extends StatelessWidget {
  const _QuoteTitle({
    required this.text,
    required this.href,
    required this.style,
    required this.onTap,
  });

  final String text;
  final String? href;
  final TextStyle? style;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final textWidget = Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
    if (onTap == null) return textWidget;
    return GestureDetector(
      onTap: onTap,
      child: textWidget,
    );
  }
}

/// 代码块右上角的"复制"按钮,带 1.5s "已复制" 反馈。
class _CopyButton extends StatefulWidget {
  const _CopyButton({required this.code});
  final String code;

  @override
  State<_CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<_CopyButton> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    if (!mounted) return;
    setState(() => _copied = true);
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TextButton.icon(
      onPressed: _copy,
      icon: Icon(
        _copied ? Icons.check_rounded : Icons.copy_rounded,
        size: 14,
      ),
      label: Text(
        _copied ? 'Copied' : 'Copy',
        style: const TextStyle(fontSize: 11),
      ),
      style: TextButton.styleFrom(
        foregroundColor: _copied ? scheme.primary : scheme.onSurfaceVariant,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        minimumSize: const Size(0, 28),
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}
