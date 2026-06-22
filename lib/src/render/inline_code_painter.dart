/// 行内代码背景自绘 —— 在 InlineSpanText 的文字**下层**画圆角灰底,跨行时按行
/// 合并成连续 RRect(首行圆左角、末行圆右角),对齐 legacy `InlineCodePainter`。
///
/// 为什么自绘而非 `TextStyle.background`:后者只能画**直角矩形**,代码跨行会裂成
/// 两块独立矩形、无圆角、无 padding、贴字。自绘用 RenderParagraph 的
/// `getBoxesForSelection` 拿到每段 inline code 的字符矩形,复用选区高亮的
/// `mergeSelectionBoxesByLine` 按行合并,再加 padding + 圆角。
///
/// 代码**块**(`<pre><code>`,SelectableTextBox.codeLanguage != null,整块自带背景)
/// 不挂本 painter —— 见 SelectableTextBox.build。
library;

import 'dart:ui' show BoxHeightStyle;

import 'package:flutter/rendering.dart';

import '../selection/projection.dart';
import '../selection/selection_highlight_painter.dart'
    show mergeSelectionBoxesByLine;

class InlineCodeBackgroundPainter extends CustomPainter {
  InlineCodeBackgroundPainter({
    required this.paragraphGetter,
    required this.projectionGetter,
    required this.color,
  });

  /// 取本块 child 子树里的 RenderParagraph(虚拟化安全,实时找)。
  final RenderParagraph? Function() paragraphGetter;

  /// 取本块的渲染偏移↔逻辑投影映射表(含 inlineCode 区间)。
  final RenderTextProjection Function() projectionGetter;

  /// 灰底色(主项目主题 `colorScheme.surfaceContainerHighest`)。
  final Color color;

  // 对齐 legacy InlineCodePainter。垂直 padding 顶部略大:真机字体(FiraCode)
  // 字形 ink 上沿略超出 tight 度量盒,顶部少给会切到代码字顶 → 顶 3 / 底 1.5。
  static const double _radius = 3.0;
  static const double _hPad = 3.5;
  static const double _vPadTop = 3.0;
  static const double _vPadBottom = 1.5;

  @override
  void paint(Canvas canvas, Size size) {
    final projection = projectionGetter();
    // 快路径:无 inline code 区间 → 不取 paragraph,零成本。
    final codeEntries = <ProjectionEntry>[
      for (final e in projection.entries)
        if (e.kind == ProjectionKind.inlineCode && e.renderLen > 0) e,
    ];
    if (codeEntries.isEmpty) return;
    final paragraph = paragraphGetter();
    if (paragraph == null) return;

    final paint = Paint()
      ..style = PaintingStyle.fill
      ..color = color;

    for (final e in codeEntries) {
      // 用 BoxHeightStyle.tight:贴合**代码字形自身**的行高(inline code 是
      // 0.85em 小字),而非段落整行高(baseStyle 1.5,会比代码高一大截显得过高)。
      // 背景 hug 住代码文字 → 对齐 legacy / 浏览器观感。
      final boxes = paragraph.getBoxesForSelection(
        TextSelection(baseOffset: e.renderStart, extentOffset: e.renderEnd),
        boxHeightStyle: BoxHeightStyle.tight,
      );
      if (boxes.isEmpty) continue;
      final rows = mergeSelectionBoxesByLine(boxes);
      for (var i = 0; i < rows.length; i++) {
        final row = rows[i];
        final merged = Rect.fromLTRB(
          row.left - _hPad,
          row.top - _vPadTop,
          row.right + _hPad,
          row.bottom + _vPadBottom,
        );
        // 首行圆左角、末行圆右角(单行 = 四角全圆);中间行直角 → 跨行连成一条。
        final lr = i == 0 ? const Radius.circular(_radius) : Radius.zero;
        final rr =
            i == rows.length - 1 ? const Radius.circular(_radius) : Radius.zero;
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            merged,
            topLeft: lr,
            bottomLeft: lr,
            topRight: rr,
            bottomRight: rr,
          ),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(InlineCodeBackgroundPainter old) =>
      old.color != color ||
      old.projectionGetter != projectionGetter ||
      old.paragraphGetter != paragraphGetter;
}
