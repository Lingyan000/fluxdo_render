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
}

/// 代码块 handle 实现这个,导出时带出 language。
abstract class CodeBlockHandleInfo {
  String? get language;
}
