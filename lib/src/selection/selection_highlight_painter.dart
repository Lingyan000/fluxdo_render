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
    // CustomPaint 的坐标系 == child(Text.rich)本地坐标系,box 已是本地坐标,
    // 直接画。
    for (final b in boxes) {
      canvas.drawRect(b.toRect(), paint);
    }
  }

  @override
  bool shouldRepaint(_HighlightPainter old) =>
      old.color != color ||
      old.selectionOf != selectionOf ||
      old.registry != registry;
}

typedef DocumentSelectionGetter = DocumentSelection? Function();
