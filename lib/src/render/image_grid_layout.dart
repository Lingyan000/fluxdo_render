/// 瀑布流分列算法(官方 columns.js 对齐)—— 阅读端 buildImageGrid 与
/// 编辑器 EditorImageGrid 共用。
library;

import '../node/inline_node.dart';

/// 官方 count():2/4 张 2 列,其余 3 列;显式 ≥3 列(web 已分列的
/// cooked 形态)尊重。调用方保证 images.length ≥ 2。
int gridColumnCount(int imageCount, int declaredColumns) =>
    declaredColumns >= 3
        ? declaredColumns.clamp(3, 6)
        : ((imageCount == 2 || imageCount == 4) ? 2 : 3);

/// 最短列贪心分配(官方 _distributeEvenly):按宽高比累计列高,逐图放
/// 最短列。返回每列的 (原始 index, ImageRun) 列表 —— index 供编辑器
/// 子选中/删除定位。
List<List<(int, ImageRun)>> distributeGridImages(
  List<ImageRun> images,
  int cols,
) {
  final columns = List.generate(cols, (_) => <(int, ImageRun)>[]);
  final heights = List.filled(cols, 0.0);
  for (var i = 0; i < images.length; i++) {
    final img = images[i];
    var shortest = 0;
    for (var j = 1; j < cols; j++) {
      if (heights[j] < heights[shortest]) shortest = j;
    }
    final ratio = (img.width != null && img.height != null && img.width! > 0)
        ? img.height! / img.width!
        : 1.0;
    heights[shortest] += ratio;
    columns[shortest].add((i, img));
  }
  return columns;
}

/// 瓦片高:填满列宽、高按自身宽高比;超高图 cap 列宽 2.5x(官方
/// max-height:1200px 等价意图),无尺寸按 1:1。
double gridTileHeight(ImageRun img, double columnWidth) {
  final w = img.width;
  final h = img.height;
  if (w != null && h != null && w > 0) {
    return (columnWidth * (h / w)).clamp(60.0, columnWidth * 2.5);
  }
  return columnWidth;
}
