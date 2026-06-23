/// 渲染内容图片(非 emoji)时主项目要提供的 builder 签名。
///
/// 子包不实现 gallery / Hero / lightbox / 长按菜单 / upload:// 短链解析 /
/// CDN 重写等(主项目侧有 `discourseImageProvider` + `galleryInfo` + Hero
/// 路由 + 长按菜单 等完整体系),通过这个 typedef 注入。
///
/// 调用方:
/// ```dart
/// FluxdoRender(
///   cookedHtml: ...,
///   imageContentBuilder: (context, image) {
///     return Image(
///       image: discourseImageProvider(rewriteCdn(image.src)),
///       width: image.width,
///       height: image.height,
///     );
///   },
/// );
/// ```

library;

import 'package:flutter/material.dart';

import '../node/inline_node.dart';

/// 内容图片 builder。
typedef ImageContentBuilder = Widget Function(
  BuildContext context,
  ImageRun image,
);

/// 默认 image builder —— Image.network + broken-image fallback。
///
/// 主项目接入时**必须**注入自定义 builder(性能 / 缓存 / 鉴权差距大)。
/// 子包默认值仅供 example gallery 和单测使用。
Widget defaultImageContentBuilder(
  BuildContext context,
  ImageRun image,
) {
  if (image.src.isEmpty) {
    return _placeholder(context, image);
  }
  return Image.network(
    image.src,
    width: image.width,
    height: image.height,
    fit: BoxFit.contain,
    errorBuilder: (_, _, _) => _placeholder(context, image),
  );
}

Widget _placeholder(BuildContext context, ImageRun image) {
  final scheme = Theme.of(context).colorScheme;
  return Container(
    width: image.width ?? 120,
    height: image.height ?? 80,
    decoration: BoxDecoration(
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: scheme.outlineVariant),
    ),
    alignment: Alignment.center,
    padding: const EdgeInsets.all(4),
    child: Icon(
      Icons.broken_image_outlined,
      size: 24,
      color: scheme.onSurfaceVariant,
    ),
  );
}
