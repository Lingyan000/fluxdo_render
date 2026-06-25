/// 单块选区高亮绘制 —— super_editor layerBeneath 式:每个 InlineSpanText 在
/// Text.rich 底下叠一层 CustomPaint,只画落在本块的选区矩形。
///
/// 选每块自绘而非顶层 overlay:表格 cell 横滚 + 虚拟化下天然正确(顶层 overlay
/// 会与横滚内容错位)。painter 监听 controller,选区落本块时用本块的
/// RenderParagraph.getBoxesForSelection 取矩形(本地坐标)直接画。
library;

import 'dart:ui' show BoxHeightStyle;

import 'package:flutter/widgets.dart';

import 'selectable_block_handle.dart';
import 'selection_geometry.dart';
import 'selection_range.dart';
import 'selection_registry.dart';

class SelectionHighlight extends StatelessWidget {
  const SelectionHighlight({
    super.key,
    required this.controller,
    required this.blockHandleGetter,
    required this.color,
    required this.child,
  });

  final SelectionController controller;

  /// 取本块 handle(InlineSpanText 注册的那个);null 时不画。
  final SelectableBlockHandle? Function() blockHandleGetter;

  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _HighlightPainter(
        repaint: controller,
        registry: controller.registry,
        selectionOf: () => controller.selection,
        blockHandleGetter: blockHandleGetter,
        color: color,
      ),
      child: child,
    );
  }
}

class _HighlightPainter extends CustomPainter {
  _HighlightPainter({
    required Listenable repaint,
    required this.registry,
    required this.selectionOf,
    required this.blockHandleGetter,
    required this.color,
  }) : super(repaint: repaint);

  final SelectionRegistry registry;
  final DocumentSelectionGetter selectionOf;
  final SelectableBlockHandle? Function() blockHandleGetter;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final selection = selectionOf();
    if (selection == null || selection.isCollapsed) return;
    final handle = blockHandleGetter();
    if (handle == null) return;
    final paragraph = handle.paragraph;
    if (paragraph == null) return;

    // 找本块在选区里的渲染偏移区间。
    final ranges = expandSelection(registry, selection);
    BlockRange? mine;
    for (final r in ranges) {
      if (r.handle.id == handle.id) {
        mine = r;
        break;
      }
    }
    if (mine == null || mine.isEmpty) return;

    // boxHeightStyle.max:每个 box 用整行最大高度(含 emoji 撑高的行高),
    // **与选了什么无关** —— 拖拽中行高恒定,不会因为选区刚好只含/不含 emoji
    // 而跳变(实测 tight=[16,32,16] 参差且会跳;max=[35.4,35.4,35.4] 恒定)。
    final boxes = paragraph.getBoxesForSelection(
      TextSelection(baseOffset: mine.start, extentOffset: mine.end),
      boxHeightStyle: BoxHeightStyle.max,
    );
    if (boxes.isEmpty) return;

    final paint = Paint()
      ..style = PaintingStyle.fill
      ..color = color;
    // box 已是统一行高(max),按行做水平 union 去掉相邻 box 间亚像素缝隙。
    for (final rowRect in mergeSelectionBoxesByLine(boxes)) {
      canvas.drawRect(rowRect, paint);
    }
  }

  @override
  bool shouldRepaint(_HighlightPainter old) =>
      old.color != color ||
      old.selectionOf != selectionOf ||
      old.registry != registry;
}

typedef DocumentSelectionGetter = DocumentSelection? Function();

/// 把 getBoxesForSelection(boxHeightStyle.max)返回的 box 按「行」(y 区间
/// 重叠)分组,每行合并成一个矩形 —— 水平 union 去掉相邻 box 间亚像素缝隙。
///
/// 前提:调用方用 [BoxHeightStyle.max],各 box 已是统一行高(与选区内容无关),
/// 所以这里直接取行内 union(top/bottom 同行一致,left/right 取最左最右),
/// 无需再挑「最矮 box」(那会随选区跳变)。
List<Rect> mergeSelectionBoxesByLine(List<TextBox> boxes) {
  final rows = <List<Rect>>[];
  for (final b in boxes) {
    final r = b.toRect();
    if (r.width == 0 && r.height == 0) continue;
    bool placed = false;
    for (final row in rows) {
      final ref = row.first;
      if (r.top < ref.bottom && r.bottom > ref.top) {
        row.add(r);
        placed = true;
        break;
      }
    }
    if (!placed) rows.add([r]);
  }

  final result = <Rect>[];
  for (final row in rows) {
    var rect = row.first;
    for (final r in row.skip(1)) {
      rect = rect.expandToInclude(r);
    }
    result.add(rect);
  }
  return result;
}
