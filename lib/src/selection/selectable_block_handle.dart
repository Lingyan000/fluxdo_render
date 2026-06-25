/// 可选块的句柄 —— registry 通过它访问某个文本块的 RenderParagraph + 映射表。
///
/// **不缓存 RenderParagraph / 几何**(已探针实测:虚拟列表滚出视口块会被回收,
/// 滚回重建 RenderObject 会换新)。全部 getter 实时取,保证虚拟化/滚动安全。
library;

import 'package:flutter/rendering.dart';

import 'projection.dart';
import 'selection_geometry.dart';

/// 一个可选文本块的访问句柄。
abstract class SelectableBlockHandle {
  SelectableBlockId get id;

  /// 实时取当前 RenderParagraph;块未 mount / 已回收时返回 null(调用方跳过)。
  RenderParagraph? get paragraph;

  /// 渲染偏移 ↔ 逻辑投影 映射表(随块内容更新)。
  RenderTextProjection get projection;

  /// 块在全局坐标系的矩形(用于视觉序排序 + 命中)。null = 不可用。
  ///
  /// 若块在内部滚动容器里(如代码块的双层 SingleChildScrollView),
  /// RenderParagraph.size 是**完整内容尺寸**(远超可视区)、localToGlobal 随
  /// 滚动偏移跑到 viewport 外 → 直接用会让命中框溢出可视区,误命中相邻块。
  /// 故与最近祖先 viewport 的可视区求交,裁剪到真正可见的部分。
  Rect? globalRect() {
    final p = paragraph;
    if (p == null || !p.attached || !p.hasSize) return null;
    final raw = p.localToGlobal(Offset.zero) & p.size;
    final clip = _nearestViewportClip(p);
    if (clip == null) return raw;
    final r = raw.intersect(clip);
    return (r.width <= 0 || r.height <= 0) ? null : r;
  }

  /// 从 [from] 向上找最近的滚动 viewport,返回其可视区全局矩形;无则 null。
  static Rect? _nearestViewportClip(RenderObject from) {
    RenderObject? node = from.parent;
    while (node != null) {
      if (node is RenderAbstractViewport && node is RenderBox) {
        final box = node as RenderBox;
        if (box.attached && box.hasSize) {
          return box.localToGlobal(Offset.zero) & box.size;
        }
        return null;
      }
      node = node.parent;
    }
    return null;
  }
}

/// 基于回调的默认实现 —— InlineSpanText 用 closure 提供 paragraph/projection。
class CallbackBlockHandle extends SelectableBlockHandle {
  CallbackBlockHandle({
    required this.id,
    required RenderParagraph? Function() paragraphGetter,
    required RenderTextProjection Function() projectionGetter,
  })  : _paragraphGetter = paragraphGetter,
        _projectionGetter = projectionGetter;

  @override
  final SelectableBlockId id;

  final RenderParagraph? Function() _paragraphGetter;
  final RenderTextProjection Function() _projectionGetter;

  @override
  RenderParagraph? get paragraph => _paragraphGetter();

  @override
  RenderTextProjection get projection => _projectionGetter();
}
