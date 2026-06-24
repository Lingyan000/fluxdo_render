import 'package:flutter/material.dart';

import '../node/node.dart';
import '../parser/paragraph_parser.dart';
import '../render/code_block_handler.dart';
import '../render/emoji_handler.dart';
import '../render/footnote_handler.dart';
import '../render/iframe_handler.dart';
import '../render/image_handler.dart';
import '../render/lazy_video_handler.dart';
import '../render/link_handler.dart';
import '../render/local_date_handler.dart';
import '../render/math_handler.dart';
import '../render/mention_handler.dart';
import '../render/node_factory.dart';
import '../render/onebox_handler.dart';
import '../render/policy_handler.dart';
import '../render/poll_handler.dart';
import '../render/quote_avatar_handler.dart';

/// 帖子渲染入口 widget。
///
/// 当前作用域(阶段 1):段落 + 标题 + 列表 + 引用块 + 分割线 + 代码块 +
/// 引用卡 + 行内 em/strong/br/text/link/inline_code/emoji/mention/image。
/// 其他节点(spoiler 等)按 docs/node_priority.md 顺序在后续阶段实现。
/// 未识别块级会 fallback 成段落 + textContent。
class FluxdoRender extends StatefulWidget {
  const FluxdoRender({
    super.key,
    required this.cookedHtml,
    this.parser,
    this.factory,
    this.linkHandler,
    this.emojiImageBuilder,
    this.mentionTapHandler,
    this.imageContentBuilder,
    this.codeBlockHighlighter,
    this.quoteAvatarBuilder,
    this.oneboxBuilder,
    this.footnoteTapHandler,
    this.lazyVideoBuilder,
    this.iframeBuilder,
    this.localDateBuilder,
    this.policyBuilder,
    this.pollBuilder,
    this.mathBlockBuilder,
    this.mathInlineBuilder,
  });

  /// Discourse cooked HTML 内容。
  final String cookedHtml;

  /// 解析器,默认是 ParagraphParser。
  /// 后续可注入自定义实现做 dogfood / fixture 测试。
  final ParagraphParser? parser;

  /// 节点工厂,默认 NodeFactory()。
  /// 调用方可继承 NodeFactory 做场景化覆盖(用户卡 bio / AI 分享卡 等)。
  /// 注意:传 factory 时,factory 自带的 handlers 优先于本 widget 的
  /// 同名参数(避免双重注入)。
  final NodeFactory? factory;

  /// 链接点击 callback —— 主项目注入。优先级见 [factory] 文档。
  final LinkActionHandler? linkHandler;

  /// Emoji 图片 builder —— 主项目注入。优先级见 [factory] 文档。
  final EmojiImageBuilder? emojiImageBuilder;

  /// Mention chip 点击跳用户卡 callback —— 主项目注入。
  final MentionTapHandler? mentionTapHandler;

  /// 内容图片 builder —— 主项目注入,走主项目的 discourseImageProvider
  /// + gallery + lightbox + 长按菜单 等完整体系。
  final ImageContentBuilder? imageContentBuilder;

  /// 代码块高亮 builder —— 主项目注入,走 HighlighterService(highlight.js)
  /// + Mermaid 等。不传则纯 monospace。
  final CodeBlockHighlighter? codeBlockHighlighter;

  /// 引用卡头像 builder —— 主项目注入,走 SmartAvatar(鉴权 + CDN 重写)。
  /// 不传则首字母 chip。
  final QuoteAvatarBuilder? quoteAvatarBuilder;

  /// Onebox 卡片 builder —— 主项目注入,根据 OneboxKind dispatch 到 6 种
  /// 子 builder(github / video / social / tech / user / default)。
  /// 返回 null 时子包用内置通用卡片(标题 + 描述 + 缩略图)。
  final OneboxBuilder? oneboxBuilder;

  /// 脚注点击 callback —— 主项目注入弹 popover/dialog 显示 contentHtml。
  /// 不传时仅 debugPrint(默认 [defaultFootnoteTapHandler])。
  final FootnoteTapHandler? footnoteTapHandler;

  /// 懒加载视频 builder —— 主项目注入 webview iframe 嵌入。
  /// 返回 null 时子包用内置缩略图卡片(点击 → linkHandler 跳浏览器)。
  final LazyVideoBuilder? lazyVideoBuilder;

  /// 嵌入 iframe builder —— 主项目注入 webview 真实渲染。
  /// 返回 null 时子包用内置占位卡(图标 + 域名 + 打开按钮)。
  final IframeBuilder? iframeBuilder;

  /// 本地日期 chip builder —— 主项目注入完整虚线下划线 + 时区换算 + popover。
  /// 返回 null 时子包用内置 fallback(服务端预渲染文本 + 时钟图标)。
  final LocalDateBuilder? localDateBuilder;

  /// Discourse policy builder —— 主项目注入完整交互(接受/撤销 + API +
  /// 已接受用户列表)。返回 null 时子包 fallback 渲染 body + 静态 footer 占位。
  final PolicyBuilder? policyBuilder;

  /// 投票块 builder —— 主项目接 legacy buildPoll(选项/票数/投票 + API)。
  /// 返回 null 时子包 fallback 占位卡。
  final PollBuilder? pollBuilder;

  /// 块级数学公式 builder —— 主项目接入 flutter_math_fork。
  /// 返回 null 时子包 fallback 用 monospace `$latex$` 原文。
  final MathBlockBuilder? mathBlockBuilder;

  /// 行内数学公式 builder —— 主项目接入 flutter_math_fork。
  /// 返回 null 时子包 fallback 用 monospace `$latex$` 原文。
  final MathInlineBuilder? mathInlineBuilder;

  @override
  State<FluxdoRender> createState() => _FluxdoRenderState();
}

class _FluxdoRenderState extends State<FluxdoRender> {
  late List<BlockNode> _nodes;
  late int _totalImagesInPost;

  @override
  void initState() {
    super.initState();
    _reparse();
  }

  @override
  void didUpdateWidget(covariant FluxdoRender oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cookedHtml != widget.cookedHtml ||
        oldWidget.parser != widget.parser) {
      _reparse();
    }
  }

  void _reparse() {
    final parser = widget.parser ?? ParagraphParser();
    _nodes = parser.parse(widget.cookedHtml);
    _totalImagesInPost = countImageRuns(_nodes);
  }

  @override
  Widget build(BuildContext context) {
    final factory = widget.factory ??
        NodeFactory(
          linkHandler: widget.linkHandler,
          emojiImageBuilder: widget.emojiImageBuilder,
          mentionTapHandler: widget.mentionTapHandler,
          imageContentBuilder: widget.imageContentBuilder,
          codeBlockHighlighter: widget.codeBlockHighlighter,
          quoteAvatarBuilder: widget.quoteAvatarBuilder,
          oneboxBuilder: widget.oneboxBuilder,
          footnoteTapHandler: widget.footnoteTapHandler,
          lazyVideoBuilder: widget.lazyVideoBuilder,
          iframeBuilder: widget.iframeBuilder,
          localDateBuilder: widget.localDateBuilder,
          policyBuilder: widget.policyBuilder,
          pollBuilder: widget.pollBuilder,
          mathBlockBuilder: widget.mathBlockBuilder,
          mathInlineBuilder: widget.mathInlineBuilder,
          totalImagesInPost: _totalImagesInPost,
        );
    if (_nodes.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final node in _nodes) factory.build(context, node),
      ],
    );
  }
}
