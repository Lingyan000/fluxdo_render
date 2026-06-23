import 'package:flutter/material.dart';

import '../node/node.dart';
import '../parser/paragraph_parser.dart';
import '../render/emoji_handler.dart';
import '../render/image_handler.dart';
import '../render/link_handler.dart';
import '../render/mention_handler.dart';
import '../render/node_factory.dart';

/// 帖子渲染入口 widget。
///
/// 当前作用域(阶段 1):段落 + 标题 + 列表 + 引用块 + 分割线 + 行内
/// em/strong/br/text/link/inline_code/emoji/mention/image。
/// 其他节点(code_block / quote_card / spoiler 等)按 docs/node_priority.md
/// 顺序在后续阶段实现。未识别块级会 fallback 成段落 + textContent。
class FluxdoRender extends StatefulWidget {
  const FluxdoRender({
    super.key,
    required this.cookedHtml,
    this.parser = const ParagraphParser(),
    this.factory,
    this.linkHandler,
    this.emojiImageBuilder,
    this.mentionTapHandler,
    this.imageContentBuilder,
  });

  /// Discourse cooked HTML 内容。
  final String cookedHtml;

  /// 解析器,默认是 ParagraphParser。
  /// 后续可注入自定义实现做 dogfood / fixture 测试。
  final ParagraphParser parser;

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

  @override
  State<FluxdoRender> createState() => _FluxdoRenderState();
}

class _FluxdoRenderState extends State<FluxdoRender> {
  late List<BlockNode> _nodes;

  @override
  void initState() {
    super.initState();
    _nodes = widget.parser.parse(widget.cookedHtml);
  }

  @override
  void didUpdateWidget(covariant FluxdoRender oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cookedHtml != widget.cookedHtml ||
        oldWidget.parser != widget.parser) {
      _nodes = widget.parser.parse(widget.cookedHtml);
    }
  }

  @override
  Widget build(BuildContext context) {
    final factory = widget.factory ??
        NodeFactory(
          linkHandler: widget.linkHandler,
          emojiImageBuilder: widget.emojiImageBuilder,
          mentionTapHandler: widget.mentionTapHandler,
          imageContentBuilder: widget.imageContentBuilder,
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
