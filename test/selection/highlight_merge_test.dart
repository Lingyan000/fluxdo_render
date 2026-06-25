import 'dart:ui';

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo_render/src/selection/selection_highlight_painter.dart';

void main() {
  TextBox box(double l, double t, double r, double b) =>
      TextBox.fromLTRBD(l, t, r, b, TextDirection.ltr);

  group('mergeSelectionBoxesByLine', () {
    test('同行文字 + 偏高 emoji → 合并成统一文字行高', () {
      // 一行:文字 box 高 20(top10~bottom30),emoji box 高 32(top4~bottom36)。
      final merged = mergeSelectionBoxesByLine([
        box(0, 10, 50, 30), // 文字
        box(50, 4, 82, 36), // emoji(偏高)
        box(82, 10, 120, 30), // 文字
      ]);
      expect(merged.length, 1, reason: '同一行合并成一个矩形');
      final r = merged.first;
      // 行高 = 最矮 box(文字 20),top10 bottom30,不被 emoji 撑到 36
      expect(r.top, 10);
      expect(r.bottom, 30);
      expect(r.height, 20, reason: 'emoji 不撑高,用文字行高');
      // 水平铺满 0~120
      expect(r.left, 0);
      expect(r.right, 120);
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
      // 行2 合并 0~90
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
