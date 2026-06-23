import 'package:flutter/material.dart';

import '../node/node.dart';
import '../parser/paragraph_parser.dart';
import '../render/node_factory.dart';

/// 帖子渲染入口 widget。
///
/// 当前作用域(阶段 1.1):仅段落 + 行内 em/strong/br/text。
/// 其他节点(列表、标题、代码块、引用卡 等)按 docs/node_priority.md 顺序
/// 在后续阶段实现。未识别块级会 fallback 成段落 + textContent。
class FluxdoRender extends StatefulWidget {
  const FluxdoRender({
    super.key,
    required this.cookedHtml,
    this.parser = const ParagraphParser(),
    this.factory,
  });

  /// Discourse cooked HTML 内容。
  final String cookedHtml;

  /// 解析器,默认是 ParagraphParser(阶段 1.1)。
  /// 后续可注入自定义实现做 dogfood / fixture 测试。
  final ParagraphParser parser;

  /// 节点工厂,默认 NodeFactory()。
  /// 调用方可继承 NodeFactory 做场景化覆盖(用户卡 bio / AI 分享卡 等)。
  final NodeFactory? factory;

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
    final factory = widget.factory ?? NodeFactory();
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
