/// 渲染一段含 LinkRun 等需要 GestureRecognizer 的行内内容。
///
/// 把 [InlineFlattener.flatten] 返回的 recognizers 在 dispose 时统一释放。
/// 没有 link 的纯样式段落也走这个 widget(零成本 — recognizers 列表空)。

library;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../flatten/inline_flattener.dart';
import '../node/inline_node.dart';
import 'emoji_handler.dart';
import 'footnote_handler.dart';
import 'image_handler.dart';
import 'link_handler.dart';
import 'mention_handler.dart';

class InlineSpanText extends StatefulWidget {
  const InlineSpanText({
    super.key,
    required this.inlines,
    required this.baseStyle,
    this.flattener = const InlineFlattener(),
    this.linkHandler,
    this.emojiImageBuilder,
    this.mentionTapHandler,
    this.imageContentBuilder,
    this.footnoteTapHandler,
    this.totalImagesInPost = 0,
    this.textAlign,
  });

  final List<InlineNode> inlines;
  final TextStyle baseStyle;
  final InlineFlattener flattener;
  final LinkActionHandler? linkHandler;
  final EmojiImageBuilder? emojiImageBuilder;
  final MentionTapHandler? mentionTapHandler;
  final ImageContentBuilder? imageContentBuilder;
  final FootnoteTapHandler? footnoteTapHandler;
  final int totalImagesInPost;
  final TextAlign? textAlign;

  @override
  State<InlineSpanText> createState() => _InlineSpanTextState();
}

class _InlineSpanTextState extends State<InlineSpanText> {
  List<GestureRecognizer> _recognizers = const [];

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
      totalImagesInPost: widget.totalImagesInPost,
      context: context,
    );
    _recognizers = result.recognizers;
    return Text.rich(result.span, textAlign: widget.textAlign);
  }
}
