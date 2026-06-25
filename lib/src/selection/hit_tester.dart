/// 命中测试 —— 全局坐标 → DocumentPosition。
///
/// 对齐 fleather 的「父协调定位块 + 子委派块内 getPositionForOffset」:
/// 顶层手势层拿到全局坐标 → [positionAt] 找命中块 → 委派 RenderParagraph.
/// getPositionForOffset 拿块内渲染偏移。
library;

import 'package:flutter/rendering.dart';

import 'selectable_block_handle.dart';
import 'selection_geometry.dart';
import 'selection_registry.dart';

class SelectionHitTester {
  const SelectionHitTester(this.registry);

  final SelectionRegistry registry;

  /// 全局坐标 → DocumentPosition。
  ///
  /// 1. 几何包含优先:点落在某块 rect 内 → 该块。
  /// 2. 兜底:落在块间空隙 / padding / 列表上下空白 → 取 y 最近的块,
  ///    再夹到块内(避免行距空白处选区断裂)。
  /// null = registry 空 / 无任何已 mount 块。
  DocumentPosition? positionAt(Offset global) {
    final blocks = registry.visualOrder();
    if (blocks.isEmpty) return null;

    // 1. 几何包含
    for (final h in blocks) {
      final r = h.globalRect();
      if (r != null && r.contains(global)) {
        return _localPosition(h, global);
      }
    }

    // 2. 最近距离兜底(按到块 rect 的垂直距离)
    SelectableBlockHandle? nearest;
    Rect? nearestRect;
    double best = double.infinity;
    for (final h in blocks) {
      final r = h.globalRect();
      if (r == null) continue;
      final dy = global.dy < r.top
          ? r.top - global.dy
          : global.dy > r.bottom
              ? global.dy - r.bottom
              : 0.0;
      if (dy < best) {
        best = dy;
        nearest = h;
        nearestRect = r;
      }
    }
    if (nearest == null || nearestRect == null) return null;
    // 把点夹进最近块的 rect 再委派(用边缘 y,x 保留以定位行内列)。
    final clamped = Offset(
      global.dx.clamp(nearestRect.left, nearestRect.right),
      global.dy.clamp(nearestRect.top, nearestRect.bottom),
    );
    return _localPosition(nearest, clamped);
  }

  DocumentPosition? _localPosition(SelectableBlockHandle h, Offset global) {
    final p = h.paragraph;
    if (p == null) return null;
    final local = p.globalToLocal(global);
    final tp = p.getPositionForOffset(local);
    return DocumentPosition(blockId: h.id, renderOffset: tp.offset);
  }

  /// 块内某渲染偏移处的「词」边界(长按选词用)。
  /// 落在 ￼(emoji/mention)上时 getWordBoundary 返回 (n, n+1) → 整颗选中
  /// (已探针实测)。
  ({int start, int end})? wordBoundaryAt(DocumentPosition pos) {
    final h = registry.byId(pos.blockId);
    final p = h?.paragraph;
    if (p == null) return null;
    final wb = p.getWordBoundary(TextPosition(offset: pos.renderOffset));
    return (start: wb.start, end: wb.end);
  }
}
