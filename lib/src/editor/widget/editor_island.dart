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
/// 图片不再走岛(全图原子化,官方 ProseMirror image 是 inline:true):
/// 选中/缩放/alt/删除交互由 FluxdoEditor 的 ImageAtomSelection 事件 +
/// 宿主浮层承载。[EditorImageScaleBar] 保留 —— 主项目源码模式预览
/// (fluxdo_render_callbacks)仍用它做可缩放图的 100/75/50 胶囊。
///
/// **网格岛工具条**(官方 GridNodeView 对齐):ImageGridNode 岛选中时
/// 顶部浮 [网格|轮播] 模式切换 + [移除网格];动作经 [onGridModeChange]/
/// [onGridRemove] 上抛(宿主接 setImageGridMode/removeImageGrid)。
library;

import 'package:flutter/material.dart';

import '../../node/node.dart';
import '../../render/node_factory.dart';
import '../../selection/selection_registry.dart';
import '../../selection/selection_scope.dart';
import 'editor_table_grid.dart' show kEditorSelfManagedRegion;

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
    this.onGridModeChange,
    this.onGridRemove,
    this.contentOverride,
  });

  final BlockNode node;

  final NodeFactory nodeFactory;

  final bool selected;

  /// 点击 → 编辑器整选本岛。
  final VoidCallback onTapSelect;

  /// 双击 → 请求编辑本岛(宿主弹源码对话框;null = 岛不可编辑)。
  final VoidCallback? onEditRequest;

  /// 网格岛工具条:模式切换(grid ⇄ carousel)。null = 不出工具条。
  final ValueChanged<ImageGridMode>? onGridModeChange;

  /// 网格岛工具条:移除网格(拆壳保图)。null = 不出移除按钮。
  final VoidCallback? onGridRemove;

  /// 岛内容替换(grid 岛的可交互瓦片视图 EditorImageGrid 由编辑器注入;
  /// null 用默认 NodeFactory.build + AbsorbPointer 只读渲染)。
  /// 注入内容自带自管区标记/手势,不再包 AbsorbPointer。
  final Widget? contentOverride;

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

    Widget content = widget.contentOverride ??
        SelectionScope(
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

    // 网格岛选中态工具条(官方 GridNodeView:[网格|轮播] + 移除网格)。
    // 结构恒定(Column 恒挂、工具条条件子)避免选中切换重建内容子树;
    // 工具条区 MetaData 自管 + Listener 原始 down(编辑器让路,点击
    // 不清整选 —— 图片胶囊同款机制)。
    final gridNode = widget.node;
    if (gridNode is ImageGridNode &&
        (widget.onGridModeChange != null || widget.onGridRemove != null)) {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.selected)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: MetaData(
                metaData: kEditorSelfManagedRegion,
                behavior: HitTestBehavior.opaque,
                child: _GridToolbar(
                  mode: gridNode.mode,
                  onModeChange: widget.onGridModeChange,
                  onRemove: widget.onGridRemove,
                ),
              ),
            ),
          content,
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

/// 网格岛工具条:[网格|轮播] 分段切换 + 移除网格(浮层统一规格)。
class _GridToolbar extends StatelessWidget {
  const _GridToolbar({
    required this.mode,
    this.onModeChange,
    this.onRemove,
  });

  final ImageGridMode mode;
  final ValueChanged<ImageGridMode>? onModeChange;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    Widget segBtn(String label, IconData icon, ImageGridMode m) {
      final active = mode == m;
      final onModeChange = this.onModeChange;
      return Listener(
        onPointerDown: (onModeChange == null || active)
            ? null
            : (_) => onModeChange(m),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: active ? scheme.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon,
                size: 14,
                color: active ? scheme.onPrimary : scheme.onSurfaceVariant),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                height: 1.2,
                fontWeight: FontWeight.w500,
                color: active ? scheme.onPrimary : scheme.onSurfaceVariant,
              ),
            ),
          ]),
        ),
      );
    }

    Widget panel(Widget child) => DecoratedBox(
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
          child: Padding(padding: const EdgeInsets.all(2), child: child),
        );

    return Row(mainAxisSize: MainAxisSize.min, children: [
      panel(Row(mainAxisSize: MainAxisSize.min, children: [
        segBtn('网格', Icons.grid_view_rounded, ImageGridMode.grid),
        segBtn('轮播', Icons.view_carousel_rounded, ImageGridMode.carousel),
      ])),
      if (onRemove != null) ...[
        const SizedBox(width: 6),
        panel(Listener(
          onPointerDown: (_) => onRemove!(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.grid_off_rounded,
                  size: 14, color: scheme.onSurfaceVariant),
              const SizedBox(width: 4),
              Text(
                '移除网格',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.2,
                  fontWeight: FontWeight.w500,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ]),
          ),
        )),
      ],
    ]);
  }
}

/// 100%/75%/50% 缩放胶囊条(浮层统一规格:圆角 + outlineVariant 细边 +
/// surfaceContainerLow 底 + 柔和投影)。主项目源码模式预览的可缩放图
/// 使用(编辑器内图片缩放已改走宿主浮层工具条)。
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
    // Listener 原始指针事件,不进手势竞技场:源码预览的图片外层可能有
    // 查看器 tap 手势,原始 down 即触发零等待。InkWell 仅留视觉水波。
    return Listener(
      onPointerDown: onTap == null ? null : (_) => onTap!(),
      child: InkWell(
        onTap: onTap == null ? null : () {},
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
      ),
    );
  }
}
