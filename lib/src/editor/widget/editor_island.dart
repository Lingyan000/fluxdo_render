/// 只读孤岛块 widget。
///
/// 渲染 = NodeFactory.build(与阅读端同一渲染出口)包三层:
/// 1. **inert SelectionScope**:独立 SelectionController —— 岛内块
///    (codeblock/表格里的 SelectableTextBox)就近注册到这个哑控制器,
///    不进编辑器的 registry(否则命中/选区会漏进岛内部);
/// 2. **AbsorbPointer**:冻结岛内交互(链接点击/poll 投票/spoiler 揭示),
///    点击事件交给外层 GestureDetector 做「整选岛」;
/// 3. **选中态**:primary 描边 + 低透明度罩(选中时)。
library;

import 'package:flutter/material.dart';

import '../../node/node.dart';
import '../../render/node_factory.dart';
import '../../selection/selection_registry.dart';
import '../../selection/selection_scope.dart';

class EditorIsland extends StatefulWidget {
  const EditorIsland({
    super.key,
    required this.node,
    required this.nodeFactory,
    required this.selected,
    required this.onTapSelect,
  });

  final BlockNode node;

  final NodeFactory nodeFactory;

  final bool selected;

  /// 点击 → 编辑器整选本岛。
  final VoidCallback onTapSelect;

  @override
  State<EditorIsland> createState() => _EditorIslandState();
}

class _EditorIslandState extends State<EditorIsland> {
  /// 哑选区控制器:吞掉岛内块的注册,与编辑器 registry 隔离。
  late final SelectionController _inertController =
      SelectionController(SelectionRegistry());

  @override
  void dispose() {
    _inertController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    Widget content = SelectionScope(
      controller: _inertController,
      child: AbsorbPointer(
        child: widget.nodeFactory.build(context, widget.node),
      ),
    );

    content = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: widget.selected ? scheme.primary : Colors.transparent,
          width: 2,
        ),
        color: widget.selected
            ? scheme.primary.withValues(alpha: 0.08)
            : Colors.transparent,
      ),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: content,
      ),
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTapSelect,
      child: MouseRegion(
        cursor: SystemMouseCursors.basic,
        child: content,
      ),
    );
  }
}
