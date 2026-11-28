import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// 可跨页面共享的排版快照，只含文字、样式和确定的占位尺寸。
///
/// 不持有原始 InlineSpan、Widget、手势或回调。不同挂载点即使使用不同
/// builder，只要实际排版输入相等，就能复用同一个 ui.Paragraph。
@immutable
class ParagraphLayoutData {
  const ParagraphLayoutData._(this._root);

  final _LayoutRun _root;

  /// 未知 span 或需要先布局组件才能得知尺寸时返回 null，交给 RichText。
  static ParagraphLayoutData? fromSpan(
    TextSpan span,
    List<PlaceholderDimensions?> dimensions,
  ) {
    if (dimensions.contains(null)) return null;
    var placeholderIndex = 0;
    _LayoutRun? copy(InlineSpan source) {
      if (source is TextSpan) {
        final children = <_LayoutRun>[];
        for (final child in source.children ?? const <InlineSpan>[]) {
          final copied = copy(child);
          if (copied == null) return null;
          children.add(copied);
        }
        return _LayoutRun(
          style: source.style,
          text: source.text,
          children: List.unmodifiable(children),
        );
      }
      if (source is PlaceholderSpan && placeholderIndex < dimensions.length) {
        final dimension = dimensions[placeholderIndex++]!;
        if (dimension.alignment != source.alignment) return null;
        // 基线占位必须提供测量结果；目前可直绘的岛使用 middle 对齐。
        if ((source.alignment == ui.PlaceholderAlignment.baseline ||
                source.alignment == ui.PlaceholderAlignment.aboveBaseline ||
                source.alignment == ui.PlaceholderAlignment.belowBaseline) &&
            dimension.baseline == null) {
          return null;
        }
        return _LayoutRun(style: source.style, placeholder: dimension);
      }
      return null;
    }

    final root = copy(span);
    if (root == null || placeholderIndex != dimensions.length) return null;
    return ParagraphLayoutData._(root);
  }

  double? get fontSize => _root.style?.fontSize;

  /// 与 TextSpan.build 相同的样式栈和缩放语义，不访问任何页面实例。
  void build(
    ui.ParagraphBuilder builder, {
    required TextScaler textScaler,
    required double placeholderScale,
  }) => _root.build(builder, textScaler, placeholderScale);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ParagraphLayoutData && _root == other._root;

  @override
  int get hashCode => _root.hashCode;
}

@immutable
class _LayoutRun {
  _LayoutRun({
    this.style,
    this.text,
    this.placeholder,
    this.children = const [],
  }) : _hash = Object.hash(style, text, placeholder, Object.hashAll(children));

  final TextStyle? style;
  final String? text;
  final PlaceholderDimensions? placeholder;
  final List<_LayoutRun> children;
  final int _hash;

  void build(
    ui.ParagraphBuilder builder,
    TextScaler textScaler,
    double placeholderScale,
  ) {
    if (style != null) {
      builder.pushStyle(style!.getTextStyle(textScaler: textScaler));
    }
    if (text != null) {
      try {
        builder.addText(text!);
      } on ArgumentError {
        // 与 TextSpan.build 一致，非法 UTF-16 用替换字符兜底。
        builder.addText('\uFFFD');
      }
    }
    final dimension = placeholder;
    if (dimension != null) {
      builder.addPlaceholder(
        dimension.size.width * placeholderScale,
        dimension.size.height * placeholderScale,
        dimension.alignment,
        baseline: dimension.baseline,
        baselineOffset: dimension.baselineOffset == null
            ? null
            : dimension.baselineOffset! * placeholderScale,
      );
    }
    for (final child in children) {
      child.build(builder, textScaler, placeholderScale);
    }
    if (style != null) builder.pop();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _LayoutRun &&
          _hash == other._hash &&
          style == other.style &&
          text == other.text &&
          placeholder == other.placeholder &&
          listEquals(children, other.children);

  @override
  int get hashCode => _hash;
}
