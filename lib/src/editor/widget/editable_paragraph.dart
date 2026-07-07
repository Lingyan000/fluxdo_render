/// 可编辑段落视图。
///
/// 渲染链路与阅读端同源:EditableTextContent → toInlines() →
/// InlineFlattener → Text.rich —— 编辑态与帖子渲染视觉零差异
/// (行内代码 NBSP 灰底、样式精调全部复用)。
///
/// 外层用 [SelectableTextBox] 包装 → 注册进编辑器自己的 SelectionRegistry:
/// 命中(hit_tester)/选区高亮/逻辑块表(projection 坐标换算)全部走现有
/// 选区基建。
///
/// composing 下划线:foregroundPainter 按 [composing](**编辑文本坐标**)
/// 经 projection 转渲染坐标后,在 RenderParagraph 的 selection boxes 底边画线。
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../flatten/inline_flattener.dart';
import '../../render/selectable_text_box.dart';
import '../../selection/projection.dart';
import '../model/editor_state.dart';

class EditableParagraph extends StatefulWidget {
  const EditableParagraph({
    super.key,
    required this.block,
    required this.documentOrder,
    required this.baseStyle,
    this.composing = TextRange.empty,
  });

  final ParagraphBlock block;

  /// 在编辑器文档中的序号(= blocks index;SelectableBlockId.docOrder)。
  final int documentOrder;

  final TextStyle baseStyle;

  /// 本段的 IME composing 区间(编辑文本坐标);非本段/无 composing 传 empty。
  final TextRange composing;

  @override
  State<EditableParagraph> createState() => _EditableParagraphState();
}

class _EditableParagraphState extends State<EditableParagraph> {
  static const _flattener = InlineFlattener();

  final GlobalKey _textKey = GlobalKey();
  FlattenResult? _result;

  FlattenResult _ensureResult() {
    // block.content 不可变 → 引用相等即缓存有效。
    return _result ??= _flattener.flatten(
      widget.block.content.toInlines(),
      widget.baseStyle,
    );
  }

  @override
  void didUpdateWidget(covariant EditableParagraph oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.block.content != widget.block.content ||
        oldWidget.baseStyle != widget.baseStyle) {
      _disposeResult();
    }
  }

  void _disposeResult() {
    final r = _result;
    if (r != null) {
      for (final rec in r.recognizers) {
        rec.dispose();
      }
    }
    _result = null;
  }

  @override
  void dispose() {
    _disposeResult();
    super.dispose();
  }

  RenderParagraph? _findParagraph() {
    final ro = _textKey.currentContext?.findRenderObject();
    return ro == null ? null : _firstParagraph(ro);
  }

  static RenderParagraph? _firstParagraph(RenderObject node) {
    if (node is RenderParagraph) return node;
    RenderParagraph? found;
    node.visitChildren((child) {
      found ??= _firstParagraph(child);
    });
    return found;
  }

  @override
  Widget build(BuildContext context) {
    final result = _ensureResult();

    Widget text = KeyedSubtree(
      key: _textKey,
      // forceStrutHeight 关键(探针实测):默认布局下空段落只有裸字体高度
      // (20px)、段末 caret 度量下坠(top 3.71 vs 行内 0.4)—— 输入前后
      // 光标/段高都在跳。强制 strut 后:空段=满段=26px,caret top/height
      // 处处一致,光标稳定性由布局构造保证(EditableText 同思路)。
      // M2 注意:行内大元素(only-emoji 32dp / WidgetSpan)会被 strut
      // 压制吗?不会 —— strut 是**最小**行高,更高的 span 仍能撑行,
      // 届时 editingCaretRectIn 的行盒校正兜住非均匀行。
      child: Text.rich(
        result.span,
        strutStyle: StrutStyle.fromTextStyle(
          widget.baseStyle,
          forceStrutHeight: true,
        ),
      ),
    );

    if (widget.composing.isValid && !widget.composing.isCollapsed) {
      text = CustomPaint(
        foregroundPainter: _ComposingUnderlinePainter(
          paragraphGetter: _findParagraph,
          projectionGetter: () => _result?.projection,
          composing: widget.composing,
          color: widget.baseStyle.color ??
              Theme.of(context).colorScheme.onSurface,
        ),
        child: text,
      );
    }

    return SelectableTextBox(
      projectionGetter: () => _ensureResult().projection,
      documentOrder: widget.documentOrder,
      debugLabel: 'edit:${widget.block.id}',
      child: text,
    );
  }
}

/// IME 预编辑下划线(2px,画在 composing 渲染区间每个 box 的底边)。
class _ComposingUnderlinePainter extends CustomPainter {
  _ComposingUnderlinePainter({
    required this.paragraphGetter,
    required this.projectionGetter,
    required this.composing,
    required this.color,
  });

  final RenderParagraph? Function() paragraphGetter;
  final RenderTextProjection? Function() projectionGetter;

  /// 编辑文本坐标(== 逻辑投影坐标)。
  final TextRange composing;

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (!composing.isValid || composing.isCollapsed) return;
    final p = paragraphGetter();
    final proj = projectionGetter();
    if (p == null || proj == null || !p.attached || !p.hasSize) return;

    final rs = proj.renderOffsetForContent(composing.start);
    final re = proj.renderOffsetForContent(composing.end);
    if (rs >= re) return;

    final boxes = p.getBoxesForSelection(
      TextSelection(baseOffset: rs, extentOffset: re),
    );
    final paint = Paint()
      ..color = color.withValues(alpha: 0.8)
      ..strokeWidth = 2;
    for (final box in boxes) {
      final y = box.bottom - 1;
      canvas.drawLine(Offset(box.left, y), Offset(box.right, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ComposingUnderlinePainter oldDelegate) =>
      oldDelegate.composing != composing || oldDelegate.color != color;
}
