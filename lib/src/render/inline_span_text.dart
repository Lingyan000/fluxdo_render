/// 渲染一段含 LinkRun 等需要 GestureRecognizer 的行内内容。
///
/// 把 [InlineFlattener.flatten] 返回的 recognizers 在 dispose 时统一释放。
/// 没有 link 的纯样式段落也走这个 widget(零成本 — recognizers 列表空)。

library;

import 'package:flutter/material.dart';

import '../flatten/inline_flattener.dart';
import '../node/inline_node.dart';
import '../selection/projection.dart';
import 'emoji_handler.dart';
import 'footnote_handler.dart';
import 'image_handler.dart';
import 'link_handler.dart';
import 'local_date_handler.dart';
import 'math_handler.dart';
import 'mention_handler.dart';
import 'selectable_text_box.dart';

class InlineSpanText extends StatefulWidget {
  const InlineSpanText({
    super.key,
    required this.inlines,
    required this.baseStyle,
    this.documentOrder = 0,
    this.chunkIndex = 0,
    this.flattener = const InlineFlattener(),
    this.linkHandler,
    this.emojiImageBuilder,
    this.mentionTapHandler,
    this.imageContentBuilder,
    this.footnoteTapHandler,
    this.localDateBuilder,
    this.mathInlineBuilder,
    this.onDownloadAttachment,
    this.totalImagesInPost = 0,
    this.textAlign,
    this.maxLines,
    this.overflow = TextOverflow.clip,
  });

  final List<InlineNode> inlines;
  final TextStyle baseStyle;

  /// 块在 chunk 内的文档序(见 SelectableBlockId / document_order.dart)。
  final int documentOrder;

  /// 所属 chunk 的文档序号(整帖渲染时 0)。
  final int chunkIndex;

  final InlineFlattener flattener;
  final LinkActionHandler? linkHandler;
  final EmojiImageBuilder? emojiImageBuilder;
  final MentionTapHandler? mentionTapHandler;
  final ImageContentBuilder? imageContentBuilder;
  final FootnoteTapHandler? footnoteTapHandler;
  final LocalDateBuilder? localDateBuilder;
  final MathInlineBuilder? mathInlineBuilder;
  /// 附件下载回调(主项目注入)。null 时附件 tap 降级到 linkHandler。
  final AttachmentDownloadHandler? onDownloadAttachment;
  final int totalImagesInPost;
  final TextAlign? textAlign;

  /// 最大行数(null=不限)。引用卡标题传 1 做单行省略。
  final int? maxLines;

  /// 文本溢出处理(默认 clip;引用卡标题传 ellipsis)。
  final TextOverflow overflow;

  @override
  State<InlineSpanText> createState() => _InlineSpanTextState();
}

class _InlineSpanTextState extends State<InlineSpanText> {
  /// flatten 结果缓存。输入(见 [_cacheValid])不变时跨 rebuild 复用:
  /// - span identical → RenderParagraph 的 text setter 短路,不重排版
  ///   (此前每次 build 重新 flatten,recognizer 是新实例导致 span 永不相等,
  ///   任何 ancestor rebuild 都放大成全部可见文本重 layout);
  /// - recognizer 不重建 → 命中路径上进行中的 tap 手势不再被 dispose 打断。
  /// 失效(内容/主题/handler 真变了)才重新 flatten 并释放旧 recognizers。
  FlattenResult? _result;

  // ---- 缓存 key:全部影响 flatten 输出的输入 ----
  // theme 覆盖 flatten 同步路径里唯一的 context 读取
  // (_buildInlineCodeSpan 的 colorScheme.onSurfaceVariant 字色)。
  List<InlineNode>? _keyInlines;
  TextStyle? _keyBaseStyle;
  ThemeData? _keyTheme;
  InlineFlattener? _keyFlattener;
  LinkActionHandler? _keyLinkHandler;
  EmojiImageBuilder? _keyEmojiBuilder;
  MentionTapHandler? _keyMentionHandler;
  ImageContentBuilder? _keyImageBuilder;
  FootnoteTapHandler? _keyFootnoteHandler;
  LocalDateBuilder? _keyLocalDateBuilder;
  MathInlineBuilder? _keyMathInlineBuilder;
  AttachmentDownloadHandler? _keyOnDownloadAttachment;
  int _keyTotalImages = -1;

  /// 当前选区映射表(供 SelectableTextBox 读取),与 span 同源。
  RenderTextProjection get _projection =>
      _result?.projection ?? RenderTextProjection.empty;

  @override
  void dispose() {
    _disposeResult();
    super.dispose();
  }

  @override
  void reassemble() {
    // hot reload 后强制重 flatten,渲染代码改动立即可见
    _disposeResult();
    super.reassemble();
  }

  void _disposeResult() {
    final r = _result;
    if (r == null) return;
    for (final rec in r.recognizers) {
      rec.dispose();
    }
    _result = null;
  }

  bool _cacheValid(ThemeData theme) =>
      _result != null &&
      identical(_keyInlines, widget.inlines) &&
      _keyBaseStyle == widget.baseStyle &&
      identical(_keyTheme, theme) &&
      identical(_keyFlattener, widget.flattener) &&
      identical(_keyLinkHandler, widget.linkHandler) &&
      identical(_keyEmojiBuilder, widget.emojiImageBuilder) &&
      identical(_keyMentionHandler, widget.mentionTapHandler) &&
      identical(_keyImageBuilder, widget.imageContentBuilder) &&
      identical(_keyFootnoteHandler, widget.footnoteTapHandler) &&
      identical(_keyLocalDateBuilder, widget.localDateBuilder) &&
      identical(_keyMathInlineBuilder, widget.mathInlineBuilder) &&
      identical(_keyOnDownloadAttachment, widget.onDownloadAttachment) &&
      _keyTotalImages == widget.totalImagesInPost;

  @override
  Widget build(BuildContext context) {
    // 无条件读 Theme:注册依赖,主题切换时本 widget 被标脏 → 缓存 miss
    // → 重 flatten(行内代码字色等派生自 colorScheme)。
    final theme = Theme.of(context);
    if (!_cacheValid(theme)) {
      // 内容/主题/handler 真变了 → 旧 span 手势语义已失效,立即释放重建。
      _disposeResult();
      _result = widget.flattener.flatten(
        widget.inlines,
        widget.baseStyle,
        linkHandler: widget.linkHandler,
        emojiImageBuilder: widget.emojiImageBuilder,
        mentionTapHandler: widget.mentionTapHandler,
        imageContentBuilder: widget.imageContentBuilder,
        footnoteTapHandler: widget.footnoteTapHandler,
        localDateBuilder: widget.localDateBuilder,
        mathInlineBuilder: widget.mathInlineBuilder,
        onDownloadAttachment: widget.onDownloadAttachment,
        totalImagesInPost: widget.totalImagesInPost,
        context: context,
      );
      _keyInlines = widget.inlines;
      _keyBaseStyle = widget.baseStyle;
      _keyTheme = theme;
      _keyFlattener = widget.flattener;
      _keyLinkHandler = widget.linkHandler;
      _keyEmojiBuilder = widget.emojiImageBuilder;
      _keyMentionHandler = widget.mentionTapHandler;
      _keyImageBuilder = widget.imageContentBuilder;
      _keyFootnoteHandler = widget.footnoteTapHandler;
      _keyLocalDateBuilder = widget.localDateBuilder;
      _keyMathInlineBuilder = widget.mathInlineBuilder;
      _keyOnDownloadAttachment = widget.onDownloadAttachment;
      _keyTotalImages = widget.totalImagesInPost;
    }
    final result = _result!;
    // 选区注册 + 高亮统一由 SelectableTextBox 封装(无 SelectionScope 时退化
    // 为裸 Text.rich,零成本)。
    return SelectableTextBox(
      projectionGetter: () => _projection,
      documentOrder: widget.documentOrder,
      chunkIndex: widget.chunkIndex,
      debugLabel: 'inlineText',
      child: Text.rich(
        result.span,
        textAlign: widget.textAlign,
        maxLines: widget.maxLines,
        overflow: widget.overflow,
      ),
    );
  }
}
