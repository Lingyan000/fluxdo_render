/// 单块选区高亮绘制 —— super_editor layerBeneath 式:每个 InlineSpanText 在
/// Text.rich 底下叠一层 CustomPaint,只画落在本块的选区矩形。
///
/// 选每块自绘而非顶层 overlay:表格 cell 横滚 + 虚拟化下天然正确(顶层 overlay
/// 会与横滚内容错位)。painter 监听 controller,选区落本块时用本块的
/// RenderParagraph.getBoxesForSelection 取矩形(本地坐标)直接画。
library;

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

    final boxes = paragraph.getBoxesForSelection(
      TextSelection(baseOffset: mine.start, extentOffset: mine.end),
    );
    if (boxes.isEmpty) return;

    final paint = Paint()
      ..style = PaintingStyle.fill
      ..color = color;
    // CustomPaint 的坐标系 == child(Text.rich)本地坐标系,box 已是本地坐标。
    // 不逐 box 直接画 —— emoji/mention 等 WidgetSpan 的 box 比纯文字行高,
    // 逐个画会高低参差。改为**按行合并成统一高度矩形**(见 mergeSelectionBoxesByLine)。
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

/// 把 getBoxesForSelection 返回的 box 按「行」(y 区间重叠)分组,每行合并成
/// 一个**统一高度**矩形,消除 emoji/mention 等 WidgetSpan box 比文字行高导致的
/// 高低参差。
///
/// 行高基准:取行内**最矮** box 的上下边(纯文字行高)——emoji 偏高、上标偏矮
/// 都不会撑歪;水平方向铺满该行最左到最右。跨行各自独立矩形。
List<Rect> mergeSelectionBoxesByLine(List<TextBox> boxes) {
  final rows = <List<Rect>>[];
  for (final b in boxes) {
    final r = b.toRect();
    if (r.isEmpty && r.width == 0 && r.height == 0) continue;
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
    double minLeft = double.infinity;
    double maxRight = -double.infinity;
    Rect base = row.first;
    for (final r in row) {
      if (r.left < minLeft) minLeft = r.left;
      if (r.right > maxRight) maxRight = r.right;
      if (r.height < base.height) base = r;
    }
    result.add(Rect.fromLTRB(minLeft, base.top, maxRight, base.bottom));
  }
  return result;
}
