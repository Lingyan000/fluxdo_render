/// 只读孤岛块 widget。
///
/// 渲染 = NodeFactory.build(与阅读端同一渲染出口)包三层:
/// 1. **inert SelectionScope**:独立 SelectionController —— 岛内块
///    (codeblock/表格里的 SelectableTextBox)就近注册到这个哑控制器,
///    不进编辑器的 registry(否则命中/选区会漏进岛内部);
/// 2. **AbsorbPointer**:冻结岛内交互(链接点击/poll 投票/spoiler 揭示),
///    点击事件交给外层 GestureDetector 做「整选岛」;
/// 3. **选中态**:primary 描边 + 低透明度罩(选中时)。
///
/// 图片缩放(image-controls,对齐官方 composer):可缩放图(客户端 cook
/// 预览形态,ImageRun.scale 非 null)的岛在**选中时**浮出 100%/75%/50%
/// 胶囊条,点击经 [onImageScale] 上抛宿主改 raw 缩放档。
library;

import 'package:flutter/material.dart';

import '../../node/node.dart';
import '../../render/node_factory.dart';
import '../../selection/selection_registry.dart';
import '../../selection/selection_scope.dart';

/// 官方 SCALES 同款档位。
const kEditorImageScales = [100, 75, 50];

class EditorIsland extends StatefulWidget {
  const EditorIsland({
    super.key,
    required this.node,
    required this.nodeFactory,
    required this.selected,
    required this.onTapSelect,
    this.onEditRequest,
    this.onImageScale,
  });

  final BlockNode node;

  final NodeFactory nodeFactory;

  final bool selected;

  /// 点击 → 编辑器整选本岛。
  final VoidCallback onTapSelect;

  /// 双击 → 请求编辑本岛(宿主弹源码对话框;null = 岛不可编辑)。
  final VoidCallback? onEditRequest;

  /// 缩放胶囊点击 → 请求切换 [image] 到 [scale] 档(宿主改 ImageRun 的
  /// scale/显示尺寸后 state.updateIslandNode)。null = 不出缩放控件。
  final void Function(ImageRun image, int scale)? onImageScale;

  /// 岛内**可缩放**图(客户端 cook 预览形态才有 scale;服务端 baked /
  /// 外链图无)。单图段落岛才出控件 —— 多图段/grid 的控件归属会歧义,
  /// 且官方 grid 内也是逐图 button-wrapper,后续有需要再扩。
  static ImageRun? scalableImageOf(BlockNode node) {
    if (node is! ParagraphNode) return null;
    ImageRun? found;
    for (final n in node.inlines) {
      if (n is ImageRun) {
        if (found != null) return null; // 多图不出
        found = n;
      }
    }
    return (found?.scale != null) ? found : null;
  }

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

    final scalable = widget.onImageScale == null
        ? null
        : EditorIsland.scalableImageOf(widget.node);
    if (scalable != null && widget.selected) {
      // 选中态浮出缩放胶囊(右上角内缘)。控件在 AbsorbPointer 之外,
      // 可正常点击;GestureDetector 在最外层,胶囊命中先于整选。
      content = Stack(
        clipBehavior: Clip.none,
        children: [
          content,
          Positioned(
            top: 8,
            right: 8,
            child: EditorImageScaleBar(
              current: scalable.scale!.round(),
              onSelect: (s) => widget.onImageScale!(scalable, s),
            ),
          ),
        ],
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTapSelect,
      onDoubleTap: widget.onEditRequest,
      child: MouseRegion(
        cursor: SystemMouseCursors.basic,
        child: content,
      ),
    );
  }
}

/// 100%/75%/50% 缩放胶囊条(浮层统一规格:圆角 + outlineVariant 细边 +
/// surfaceContainerLow 底 + 柔和投影)。编辑器岛内选中态浮出;主项目
/// 源码预览的可缩放图也复用(视觉一致)。
class EditorImageScaleBar extends StatelessWidget {
  const EditorImageScaleBar({
    super.key,
    required this.current,
    required this.onSelect,
  });

  final int current;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.5),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final s in kEditorImageScales)
              _ScalePill(
                label: '$s%',
                active: s == current,
                onTap: s == current ? null : () => onSelect(s),
              ),
          ],
        ),
      ),
    );
  }
}

class _ScalePill extends StatelessWidget {
  const _ScalePill({required this.label, required this.active, this.onTap});

  final String label;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: active ? scheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            height: 1.2,
            fontWeight: FontWeight.w500,
            color: active ? scheme.onPrimary : scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
