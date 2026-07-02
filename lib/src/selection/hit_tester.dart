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
  /// **优先用框架真实 hit-test**(从 [hitTestRoot] = 当前 chunk 手势层的
  /// RenderObject 往下):框架 hit-test 只走真实可见、未被 viewport 裁剪的渲染
  /// 路径 —— 天然排除「被 keepAlive 保活但已滚出视口」的块(它们的 RepaintBoundary
  /// 停在旧屏幕位置,globalRect 会陈旧地"占着"屏幕、污染命中,导致窗口尺寸变化
  /// 后划词跳到完全另一段)。命中到已注册的 RenderParagraph 即返回。
  ///
  /// 框架 hit-test 取不到(点在 padding/空隙、或在别的 chunk 里 = 跨 chunk 拖拽
  /// 扩展)时,回退到 globalRect 包含/最近兜底(下方原逻辑)。
  DocumentPosition? positionAt(Offset global, {RenderObject? hitTestRoot}) {
    final framework = _frameworkHit(global, hitTestRoot);
    if (framework != null) return framework;

    final blocks = registry.liveHandles;

    // 1. 几何包含;多个重叠时取最小 rect(最内层)。
    SelectableBlockHandle? hit;
    double hitArea = double.infinity;
    for (final h in blocks) {
      final r = h.globalRect();
      if (r == null || !r.contains(global)) continue;
      final area = r.width * r.height;
      if (area < hitArea) {
        hitArea = area;
        hit = h;
      }
    }
    if (hit != null) return _localPosition(hit, global);

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

  /// 框架真实 hit-test:从 [root] 往下,命中路径里第一个「已注册」的
  /// RenderParagraph(路径是 deepest-first,故第一个 = 最内层,与嵌套容器
  /// 取最内一致)。取不到返回 null(交由 globalRect 兜底)。
  DocumentPosition? _frameworkHit(Offset global, RenderObject? root) {
    if (root is! RenderBox || !root.attached || !root.hasSize) return null;
    final local = root.globalToLocal(global);
    if (!local.dx.isFinite || !local.dy.isFinite) return null;
    final result = BoxHitTestResult();
    if (!root.hitTest(result, position: local)) return null;
    final live = registry.liveHandles;
    for (final entry in result.path) {
      final target = entry.target;
      if (target is! RenderParagraph) continue;
      for (final h in live) {
        if (identical(h.paragraph, target)) {
          return _localPosition(h, global);
        }
      }
    }
    return null;
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

  /// 位置处 caret 的**全局矩形**(宽 0)。手柄拖拽的半行补偿、放大镜焦点
  /// 「指文字所在行」都用它(对齐 SDK _buildInfoForMagnifier 的 caretRect)。
  /// 块不可见(回收/离屏 NaN)时返回 null。
  Rect? caretRectAt(DocumentPosition pos) {
    final p = registry.byId(pos.blockId)?.paragraph;
    if (p == null || !p.attached || !p.hasSize) return null;
    final tp = TextPosition(offset: pos.renderOffset);
    final local = p.getOffsetForCaret(tp, Rect.zero);
    final height = p.getFullHeightForCaret(tp);
    final topLeft = p.localToGlobal(local);
    if (!topLeft.dx.isFinite || !topLeft.dy.isFinite) return null;
    return topLeft & Size(0, height);
  }

  /// 块的渲染总长度(三击选段用)。走逻辑块表 → 回收块也能取。未注册返回 null。
  int? renderLengthOf(SelectableBlockId blockId) {
    return registry.logicalById(blockId)?.renderLength;
  }
}
