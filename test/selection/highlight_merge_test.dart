import 'dart:ui';

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo_render/src/selection/selection_highlight_painter.dart';

void main() {
  TextBox box(double l, double t, double r, double b) =>
      TextBox.fromLTRBD(l, t, r, b, TextDirection.ltr);

  group('mergeSelectionBoxesByLine', () {
    test('同行 box(max 已统一高度)水平 union 成一个矩形', () {
      // 用 BoxHeightStyle.max 时各 box 已同高(如 35.4),这里模拟同高 box。
      final merged = mergeSelectionBoxesByLine([
        box(0, 4, 50, 36),
        box(50, 4, 82, 36),
        box(82, 4, 120, 36),
      ]);
      expect(merged.length, 1, reason: '同一行合并成一个矩形');
      final r = merged.first;
      expect(r.top, 4);
      expect(r.bottom, 36);
      expect(r.left, 0);
      expect(r.right, 120, reason: '水平铺满,去掉相邻缝隙');
    });

    test('两行各自独立矩形', () {
      final merged = mergeSelectionBoxesByLine([
        box(0, 10, 100, 30), // 行1
        box(0, 40, 60, 60), // 行2
      ]);
      expect(merged.length, 2);
      expect(merged[0].top, 10);
      expect(merged[1].top, 40);
    });

    test('行内乱序 box 也按 y 正确分组', () {
      final merged = mergeSelectionBoxesByLine([
        box(0, 40, 50, 60), // 行2 先来
        box(0, 10, 50, 30), // 行1
        box(50, 40, 90, 60), // 行2
      ]);
      expect(merged.length, 2);
      final row2 = merged.firstWhere((r) => r.top == 40);
      expect(row2.left, 0);
      expect(row2.right, 90);
    });

    test('空列表返回空', () {
      expect(mergeSelectionBoxesByLine([]), isEmpty);
    });

    test('单 box 原样', () {
      final merged = mergeSelectionBoxesByLine([box(5, 10, 55, 30)]);
      expect(merged.length, 1);
      expect(merged.first, const Rect.fromLTRB(5, 10, 55, 30));
    });
  });
}
