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
import '../render/chat_transcript_handler.dart';
import '../render/poll_handler.dart';
import '../render/quote_avatar_handler.dart';
import '../selection/selection_data.dart';
import '../selection/selection_registry.dart';
import '../selection/selection_scope.dart';
import 'selection_content_layer.dart';

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
    this.chatTranscriptBuilder,
    this.mathBlockBuilder,
    this.mathInlineBuilder,
    this.selectionEnabled = true,
    this.onQuoteRequest,
    this.onCopyQuoteRequest,
    this.onCopyToast,
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

  /// 聊天记录 builder —— 主项目接 legacy buildChatTranscript。
  /// 返回 null 时子包 fallback 卡。
  final ChatTranscriptBuilder? chatTranscriptBuilder;

  /// 块级数学公式 builder —— 主项目接入 flutter_math_fork。
  /// 返回 null 时子包 fallback 用 monospace `$latex$` 原文。
  final MathBlockBuilder? mathBlockBuilder;

  /// 行内数学公式 builder —— 主项目接入 flutter_math_fork。
  /// 返回 null 时子包 fallback 用 monospace `$latex$` 原文。
  final MathInlineBuilder? mathInlineBuilder;

  /// 是否启用自研选区(划词选中 → toolbar 复制/引用)。默认 true;
  /// 用户卡 bio 等场景可关掉(不挂手势层 + 高亮,零成本)。
  final bool selectionEnabled;

  /// 引用请求 —— toolbar 点「引用」时调,把选区 plainText 交回主项目。
  final QuoteRequestCallback? onQuoteRequest;

  /// 复制引用请求 —— toolbar 点「复制引用」时调,主项目拼 [quote=...] BBCode
  /// 进剪贴板(需 post 元数据,子包无法自拼)。null = 不显示该按钮。
  final QuoteRequestCallback? onCopyQuoteRequest;

  /// 复制完成 —— 子包复制到剪贴板后通知主项目弹 toast(可选)。
  final CopyToastCallback? onCopyToast;

  @override
  State<FluxdoRender> createState() => _FluxdoRenderState();
}

class _FluxdoRenderState extends State<FluxdoRender> {
  late List<BlockNode> _nodes;
  late int _totalImagesInPost;

  /// 自研选区控制器(selectionEnabled 时非 null)。
  SelectionController? _selectionController;

  @override
  void initState() {
    super.initState();
    _reparse();
    if (widget.selectionEnabled) {
      _selectionController = SelectionController(SelectionRegistry());
    }
  }

  @override
  void didUpdateWidget(covariant FluxdoRender oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cookedHtml != widget.cookedHtml ||
        oldWidget.parser != widget.parser) {
      _reparse();
    }
    if (widget.selectionEnabled && _selectionController == null) {
      _selectionController = SelectionController(SelectionRegistry());
    } else if (!widget.selectionEnabled && _selectionController != null) {
      _selectionController!.dispose();
      _selectionController = null;
    }
  }

  @override
  void dispose() {
    _selectionController?.dispose();
    super.dispose();
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
          chatTranscriptBuilder: widget.chatTranscriptBuilder,
          mathBlockBuilder: widget.mathBlockBuilder,
          mathInlineBuilder: widget.mathInlineBuilder,
          totalImagesInPost: _totalImagesInPost,
        );
    if (_nodes.isEmpty) {
      return const SizedBox.shrink();
    }
    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final node in _nodes) factory.build(context, node),
      ],
    );

    final controller = _selectionController;
    if (controller == null) return column;

    // 选区树:Scope 下传 controller 给各 InlineSpanText(注册 + 高亮),
    // 顶层手势层管长按选区,toolbar 弹复制/引用浮层。
    //
    // 关键:用 SelectionContainer.disabled 把内容从**外层系统 SelectionArea**
    // (主项目 topic_post_list 包了一层)里排除——否则 Text.rich 会自动参与
    // 外层系统选区,系统高亮抢先接管拖拽,自研手势层/toolbar 永远触发不了。
    // 自研选区直接用 RenderParagraph,不依赖 SelectionContainer,disabled 不影响它。
    return SelectionContainer.disabled(
      child: SelectionScope(
        controller: controller,
        child: SelectionContentLayer(
          controller: controller,
          onQuoteRequest: widget.onQuoteRequest,
          onCopyQuoteRequest: widget.onCopyQuoteRequest,
          onCopyToast: widget.onCopyToast,
          child: column,
        ),
      ),
    );
  }
}
