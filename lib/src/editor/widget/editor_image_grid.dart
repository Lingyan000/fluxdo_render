/// 编辑器网格(grid 岛的专属交互视图,官方 grid 内图可 NodeSelection
/// 的等价物):
///
/// - **布局 = 官方编辑器形态**(rich-editor.scss `.composer-image-grid`):
///   flex-wrap 等大方块缩略图流,img 固定 200px(容器宽 <640 时 150px)
///   object-fit:cover,虚线边框 + 内边距 —— **不是**阅读端的瀑布流
///   (那是 cooked 渲染形态,columns.js 分列);
/// - **瓦片可单击** → 子选中(primary 描边)+ 上抛 [onImageTap](宿主
///   浮出官方 isInGrid 工具条:[删除|移出网格] + alt 条,无缩放);
/// - 已子选中再点 → [onImageOpen](查看器);
/// - 瓦片区在 [kEditorSelfManagedRegion] 自管区内(编辑器手势让路,
///   点瓦片不触发岛整选);网格空白边缘仍走岛整选(外层 GestureDetector)。
///
/// 与 EditorTableGrid(表格 cell 编辑)同一架构角色:岛的专属交互视图。
library;

import 'package:flutter/material.dart';

import '../../node/node.dart';
import '../../render/image_handler.dart';
import '../../render/node_factory.dart';
import 'editor_table_grid.dart' show kEditorSelfManagedRegion;

/// grid 内图片子选中事件(宿主浮层锚定;官方 isInGrid 工具条)。
@immutable
class GridImageSelection {
  const GridImageSelection({
    required this.islandId,
    required this.imageIndex,
    required this.image,
    required this.globalRect,
  });

  /// grid 岛块 id。
  final String islandId;

  /// 在 ImageGridNode.images 中的下标。
  final int imageIndex;

  final ImageRun image;

  /// 瓦片全局矩形。
  final Rect globalRect;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GridImageSelection &&
          islandId == other.islandId &&
          imageIndex == other.imageIndex &&
          image == other.image &&
          globalRect == other.globalRect;

  @override
  int get hashCode => Object.hash(islandId, imageIndex, image, globalRect);
}

class EditorImageGrid extends StatefulWidget {
  const EditorImageGrid({
    super.key,
    required this.node,
    required this.islandId,
    required this.nodeFactory,
    this.selectedIndex,
    this.onImageTap,
    this.onImageOpen,
  });

  final ImageGridNode node;
  final String islandId;
  final NodeFactory nodeFactory;

  /// 当前子选中的图下标(宿主持有;null = 无子选中)。
  final int? selectedIndex;

  /// 瓦片单击(未选中态)→ 请求子选中(宿主记录 index + 浮层)。
  final ValueChanged<GridImageSelection>? onImageTap;

  /// 已子选中的瓦片再点 → 请求打开查看器。
  final ValueChanged<GridImageSelection>? onImageOpen;

  @override
  State<EditorImageGrid> createState() => _EditorImageGridState();
}

class _EditorImageGridState extends State<EditorImageGrid> {
  final Map<int, GlobalKey> _tileKeys = {};

  GlobalKey _keyFor(int index) => _tileKeys.putIfAbsent(index, GlobalKey.new);

  GridImageSelection? _selectionOf(int index) {
    final box =
        _tileKeys[index]?.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached || !box.hasSize) return null;
    final topLeft = box.localToGlobal(Offset.zero);
    if (!topLeft.dx.isFinite || !topLeft.dy.isFinite) return null;
    return GridImageSelection(
      islandId: widget.islandId,
      imageIndex: index,
      image: widget.node.images[index],
      globalRect: topLeft & box.size,
    );
  }

  void _onTileTap(int index) {
    final sel = _selectionOf(index);
    if (sel == null) return;
    if (widget.selectedIndex == index) {
      widget.onImageOpen?.call(sel);
    } else {
      widget.onImageTap?.call(sel);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final images = widget.node.images;
    final builder =
        widget.nodeFactory.imageContentBuilder ?? defaultImageContentBuilder;

    if (images.isEmpty) return const SizedBox.shrink();

    return MetaData(
      metaData: kEditorSelfManagedRegion,
      behavior: HitTestBehavior.opaque,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 官方:viewport <md 150px,≥md 200px(编辑器列宽近似判)
          final tileSize = constraints.maxWidth < 640 ? 150.0 : 200.0;
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              border: Border.all(
                color: scheme.outlineVariant,
                width: 2,
                strokeAlign: BorderSide.strokeAlignInside,
                style: BorderStyle.solid,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            // 官方是 dashed 虚线;Flutter 无原生 dashed border,细节
            // 用 outlineVariant 实线弱化近似(视觉层级一致即可)
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < images.length; i++)
                  _tile(context, scheme, builder, i, images[i], tileSize,
                      images.length),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _tile(
    BuildContext context,
    ColorScheme scheme,
    ImageContentBuilder builder,
    int index,
    ImageRun img,
    double size,
    int total,
  ) {
    final selected = widget.selectedIndex == index;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _onTileTap(index),
      child: Container(
        key: _keyFor(index),
        width: size,
        height: size,
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: selected ? scheme.primary : Colors.transparent,
            width: 2,
          ),
          color: selected
              ? scheme.primary.withValues(alpha: 0.10)
              : Colors.transparent,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: FittedBox(
            fit: BoxFit.cover,
            clipBehavior: Clip.hardEdge,
            child: AbsorbPointer(
              child: builder(context, img, total),
            ),
          ),
        ),
      ),
    );
  }
}
