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
    // 用 foregroundPainter(画在 child **上层**)而非 painter(下层):
    // emoji 图片 / mention chip / 内容图片是不透明的,画在文字层之上 —— 若高亮
    // 在下层会被它们完全盖住,占位符处看不到选中态。改画上层 + 半透明主题色
    // (selectionColor ~0.3 alpha)→ 文字和占位符都被涂一层选中色,范围连贯,
    // 内容仍透出可见(对齐系统选区思路)。
    return CustomPaint(
      foregroundPainter: _HighlightPainter(
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

    // 用默认 tight box:各 box 是「每行选中部分」的真实矩形,**行间天然有
    // 间隙**(实测 line1 底 19.6 vs line2 顶 26.6,差 7px)→ 按行分组绝不
    // 跨行误并,杜绝整段过选。
    // (曾错用 BoxHeightStyle.max:max 把相邻行 box 撑到亚像素紧贴 → 被
    //  mergeSelectionBoxesByLine 误判同行合并成跨两行整块 → 整段高亮 bug。)
    final boxes = paragraph.getBoxesForSelection(
      TextSelection(baseOffset: mine.start, extentOffset: mine.end),
    );
    if (boxes.isEmpty) return;

    final paint = Paint()
      ..style = PaintingStyle.fill
      ..color = color;
    // 同行 box 合并成统一高度矩形:同一行内 emoji(偏高)与文字 box 取 union,
    // 整行等高(防 emoji 处参差);tight 间隙保证不跨行。
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

/// 把 getBoxesForSelection(**tight**)返回的 box 按「行」(y 区间重叠)分组,
/// 每行合并成一个矩形:同行内 emoji(偏高)与文字 box 取 union(整行等高,
/// 消除 emoji 处参差),水平铺满该行左到右(去相邻 box 亚像素缝隙)。
///
/// 必须喂 tight box:tight 行间有真实间隙,分组按 y 重叠**绝不跨行**;若喂
/// BoxHeightStyle.max,相邻行 box 亚像素紧贴会被误判同行 → 合并成跨两行整块。
List<Rect> mergeSelectionBoxesByLine(List<TextBox> boxes) {
  final rows = <List<Rect>>[];
  for (final b in boxes) {
    final r = b.toRect();
    if (r.width == 0 && r.height == 0) continue;
    bool placed = false;
    for (final row in rows) {
      final ref = row.first;
      // 同行判定:垂直区间有「实质」重叠(过半),避免行间 1px 误触。
      final overlap =
          (r.bottom < ref.bottom ? r.bottom : ref.bottom) -
              (r.top > ref.top ? r.top : ref.top);
      final minH = (r.height < ref.height ? r.height : ref.height);
      if (overlap > minH * 0.5) {
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
