/// 编辑器网格(grid 岛的专属交互视图,官方 grid 内图可 NodeSelection
/// 的等价物):
///
/// - 瀑布流布局与阅读端同源(image_grid_layout 三函数);
/// - **瓦片可单击** → 子选中(primary 描边)+ 上抛 [onImageTap](宿主
///   浮出官方 isInGrid 工具条:[删除|移出网格] + alt 条,无缩放 ——
///   官方 isInGrid 时不出 zoom 按钮,grid 布局吃掉显示尺寸);
/// - 已子选中再点 → [onImageOpen](查看器);
/// - 瓦片区在 [kEditorSelfManagedRegion] 自管区内(编辑器手势让路,
///   点瓦片不触发岛整选);网格空白边缘仍走岛整选(外层 GestureDetector)。
///
/// 与 EditorTableGrid(表格 cell 编辑)同一架构角色:岛的专属交互视图。
library;

import 'package:flutter/material.dart';

import '../../node/node.dart';
import '../../render/image_grid_layout.dart';
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

    Widget tile(int index, ImageRun img, double colWidth) {
      final selected = widget.selectedIndex == index;
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _onTileTap(index),
          child: Container(
            key: _keyFor(index),
            height: gridTileHeight(img, colWidth),
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
                  child: builder(context, img, images.length),
                ),
              ),
            ),
          ),
        ),
      );
    }

    // 单图:无分列
    if (images.length < 2) {
      return MetaData(
        metaData: kEditorSelfManagedRegion,
        behavior: HitTestBehavior.opaque,
        child: LayoutBuilder(
          builder: (context, c) => tile(0, images.single, c.maxWidth),
        ),
      );
    }

    return MetaData(
      metaData: kEditorSelfManagedRegion,
      behavior: HitTestBehavior.opaque,
      child: LayoutBuilder(
        builder: (context, constraints) {
          const spacing = 6.0;
          final cols = gridColumnCount(images.length, widget.node.columns);
          final colWidth =
              (constraints.maxWidth - (cols - 1) * spacing) / cols;
          final columns = distributeGridImages(images, cols);
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var c = 0; c < cols; c++) ...[
                if (c > 0) const SizedBox(width: spacing),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final (i, img) in columns[c])
                        tile(i, img, colWidth),
                    ],
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
