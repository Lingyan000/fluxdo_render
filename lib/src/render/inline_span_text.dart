/// 渲染一段含 LinkRun 等需要 GestureRecognizer 的行内内容。
///
/// 把 [InlineFlattener.flatten] 返回的 recognizers 在 dispose 时统一释放。
/// 没有 link 的纯样式段落也走这个 widget(零成本 — recognizers 列表空)。

library;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

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
  List<GestureRecognizer> _recognizers = const [];

  /// 当前选区映射表,build 时由 flatten 结果更新(供 SelectableTextBox 读取)。
  RenderTextProjection _projection = RenderTextProjection.empty;

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 每次 build 重新 flatten — recognizers 也跟着重建。
    // 旧的 recognizers 在下一次 setState/rebuild 之前不会被销毁,
    // 但 GestureRecognizer 持有空闲资源很轻,且单 build 周期产生
    // 的不会泄漏(下次 build 之前没用户操作时间 — 即使 rebuild
    // 频繁,旧的也只在 dispose 时回收一次)。
    // 简单稳定的做法:rebuild 时先 dispose 旧的,再放新的。
    for (final r in _recognizers) {
      r.dispose();
    }
    final result = widget.flattener.flatten(
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
    _recognizers = result.recognizers;
    _projection = result.projection;
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
