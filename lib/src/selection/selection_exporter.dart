/// 选区导出 —— DocumentSelection → SelectionData(plainText + 矩形 + 代码块语言)。
///
/// plainText 按 visualOrder 遍历各块,用映射表投影,块间加 `\n`(对齐
/// HtmlTextMapper 块级换行)。选区完全落单代码块时带 language。
library;

import 'package:flutter/rendering.dart';

import 'selection_data.dart';
import 'selection_geometry.dart';
import 'selection_range.dart';
import 'selection_registry.dart';

class SelectionExporter {
  const SelectionExporter(this.registry);

  final SelectionRegistry registry;

  /// 选区为空 / collapsed / 无内容时返回 null。
  SelectionData? export(DocumentSelection? selection) {
    if (selection == null || selection.isCollapsed) return null;

    final ranges = expandSelection(registry, selection);
    if (ranges.isEmpty) return null;

    // 1. plainText:各块投影 + 块间 \n
    final buf = StringBuffer();
    for (var i = 0; i < ranges.length; i++) {
      final r = ranges[i];
      buf.write(r.handle.projection.project(r.start, r.end));
      if (i != ranges.length - 1) buf.write('\n');
    }
    final plainText = buf.toString();
    if (plainText.isEmpty) return null;

    // 2. 高亮矩形(全局)+ 外接框
    final globalRects = <Rect>[];
    for (final r in ranges) {
      final p = r.handle.paragraph;
      if (p == null) continue;
      final boxes = p.getBoxesForSelection(
        TextSelection(baseOffset: r.start, extentOffset: r.end),
      );
      for (final b in boxes) {
        final tl = p.localToGlobal(Offset(b.left, b.top));
        final br = p.localToGlobal(Offset(b.right, b.bottom));
        globalRects.add(Rect.fromPoints(tl, br));
      }
    }
    final bounds = globalRects.isEmpty
        ? Rect.zero
        : globalRects.reduce((a, b) => a.expandToInclude(b));

    // 3. 代码块语言(选区完全落单代码块)
    final code = _codeInfoIfSingleCodeBlock(ranges);

    return SelectionData(
      plainText: plainText,
      globalBounds: bounds,
      globalRects: globalRects,
      code: code,
    );
  }

  CodeSelectionInfo? _codeInfoIfSingleCodeBlock(List<BlockRange> ranges) {
    if (ranges.length != 1) return null;
    final h = ranges.first.handle;
    if (h is CodeBlockHandleInfo) {
      return CodeSelectionInfo(language: (h as CodeBlockHandleInfo).language);
    }
    return null;
  }

  /// 按视觉序返回选区两端点的 DocumentPosition(拖手柄时固定一端、动另一端)。
  /// visualStart = 视觉最前端点,visualEnd = 视觉最后端点。空选区返回 null。
  ({DocumentPosition visualStart, DocumentPosition visualEnd})? orderedEndpoints(
      DocumentSelection? selection) {
    if (selection == null) return null;
    final order = registry.visualOrder();
    if (order.isEmpty) return null;
    int idx(SelectableBlockId id) {
      for (var i = 0; i < order.length; i++) {
        if (order[i].id == id) return i;
      }
      return -1;
    }

    final bi = idx(selection.base.blockId);
    final ei = idx(selection.extent.blockId);
    if (bi < 0 || ei < 0) return null;
    final baseFirst = bi < ei ||
        (bi == ei &&
            selection.base.renderOffset <= selection.extent.renderOffset);
    return baseFirst
        ? (visualStart: selection.base, visualEnd: selection.extent)
        : (visualStart: selection.extent, visualEnd: selection.base);
  }

  /// 选区两端的全局锚点(给拖拽手柄实时定位用,**按当前 selection 随时重算**,
  /// 不复用松手快照)。
  /// - start = 选区视觉首 box 的**左下角**(左手柄贴这里)
  /// - end   = 选区视觉末 box 的**右下角**(右手柄贴这里)
  /// - startLineHeight / endLineHeight = 对应 box 高度(手柄尺寸/锚点按行高算)。
  /// 选区空 / 取不到几何时返回 null。
  SelectionEndpoints? endpointAnchors(DocumentSelection? selection) {
    if (selection == null || selection.isCollapsed) return null;
    final ranges = expandSelection(registry, selection);
    if (ranges.isEmpty) return null;

    // 首 range 的首 box 左下 = start;末 range 的末 box 右下 = end。
    final first = ranges.first;
    final last = ranges.last;
    final fp = first.handle.paragraph;
    final lp = last.handle.paragraph;
    if (fp == null || lp == null) return null;

    final firstBoxes = fp.getBoxesForSelection(
      TextSelection(baseOffset: first.start, extentOffset: first.end),
    );
    final lastBoxes = lp.getBoxesForSelection(
      TextSelection(baseOffset: last.start, extentOffset: last.end),
    );
    if (firstBoxes.isEmpty || lastBoxes.isEmpty) return null;

    final fb = firstBoxes.first;
    final lb = lastBoxes.last;
    final startGlobal = fp.localToGlobal(Offset(fb.left, fb.bottom));
    final endGlobal = lp.localToGlobal(Offset(lb.right, lb.bottom));

    return SelectionEndpoints(
      start: startGlobal,
      end: endGlobal,
      startLineHeight: fb.bottom - fb.top,
      endLineHeight: lb.bottom - lb.top,
    );
  }
}

/// 选区两端全局锚点 + 行高(手柄定位用)。
class SelectionEndpoints {
  const SelectionEndpoints({
    required this.start,
    required this.end,
    required this.startLineHeight,
    required this.endLineHeight,
  });

  /// 选区视觉起点(首 box 左下角,全局)。
  final Offset start;

  /// 选区视觉终点(末 box 右下角,全局)。
  final Offset end;

  final double startLineHeight;
  final double endLineHeight;
}

/// 代码块 handle 实现这个,导出时带出 language。
abstract class CodeBlockHandleInfo {
  String? get language;
}
