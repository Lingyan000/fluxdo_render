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
  Rect? globalRect() {
    final p = paragraph;
    if (p == null || !p.attached || !p.hasSize) return null;
    final topLeft = p.localToGlobal(Offset.zero);
    return topLeft & p.size;
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
