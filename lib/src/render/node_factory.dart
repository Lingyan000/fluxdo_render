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

import '../flatten/inline_flattener.dart';
import '../node/node.dart';
import 'emoji_handler.dart';
import 'inline_span_text.dart';
import 'link_handler.dart';
import 'mention_handler.dart';

class NodeFactory {
  NodeFactory({
    InlineFlattener? inlineFlattener,
    this.linkHandler,
    this.emojiImageBuilder,
    this.mentionTapHandler,
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

  /// 入口 dispatch — sealed class exhaustive switch。
  Widget build(BuildContext context, BlockNode node) {
    return switch (node) {
      ParagraphNode() => buildParagraph(context, node),
      HeadingNode() => buildHeading(context, node),
      ListNode() => buildList(context, node),
      BlockquoteNode() => buildBlockquote(context, node),
    };
  }

  /// 段落渲染 — InlineSpanText 自动管 GestureRecognizer 生命周期。
  ///
  /// 子类可 override 实现段落级别的定制(如调字号、加 margin)。
  ///
  /// margin 对齐 legacy(fwfh `_tagP`):`1em 0`(上下各一个 em)。
  Widget buildParagraph(BuildContext context, ParagraphNode node) {
    final theme = Theme.of(context);
    final baseStyle = theme.textTheme.bodyMedium ?? const TextStyle();
    final em = baseStyle.fontSize ?? 14;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: em),
      child: InlineSpanText(
        inlines: node.inlines,
        baseStyle: baseStyle,
        flattener: _inlineFlattener,
        linkHandler: linkHandler,
        emojiImageBuilder: emojiImageBuilder,
        mentionTapHandler: mentionTapHandler,
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
            for (final child in node.children) build(context, child),
          ],
        ),
      ),
    );
  }
}
