/// 渲染 emoji 图片时主项目要提供的 builder 签名。
///
/// 子包不实现图片加载(主项目有 emojiImageProvider 独立缓存池、SVG 探测、
/// upload:// 短链解析、CDN 重写 等),通过这个 typedef 注入。
///
/// 调用方:
/// ```dart
/// FluxdoRender(
///   cookedHtml: ...,
///   emojiImageBuilder: (context, emoji, size) {
///     return Image(
///       image: emojiImageProvider(rewriteCdn(emoji.url)),
///       width: size, height: size,
///     );
///   },
/// );
/// ```

library;

import 'package:flutter/widgets.dart';

import '../node/inline_node.dart';

/// Emoji 渲染 builder。
///
/// - [emoji] 包含 url / name / isOnlyEmoji
/// - [size] 已根据 isOnlyEmoji + 父字号算好的最终显示 px(主项目按需用)
typedef EmojiImageBuilder = Widget Function(
  BuildContext context,
  EmojiRun emoji,
  double size,
);

/// 默认 emoji builder —— 直接 Image.network,无缓存池、无 CDN 重写。
///
/// 主项目接入时**必须**注入自定义 builder(性能差距大:Image.network
/// 不走主项目的统一缓存池 + 鉴权)。子包默认值仅供 example gallery
/// 和单测使用。
Widget defaultEmojiImageBuilder(
  BuildContext context,
  EmojiRun emoji,
  double size,
) {
  if (emoji.url.isEmpty) {
    // 兜底:URL 缺失时用纯文本 :name: 占位
    return Text(
      emoji.name.isEmpty ? ':?:' : ':${emoji.name}:',
      style: TextStyle(fontSize: size * 0.9),
    );
  }
  return Image.network(
    emoji.url,
    width: size,
    height: size,
    errorBuilder: (_, _, _) => Text(
      emoji.name.isEmpty ? ':?:' : ':${emoji.name}:',
      style: TextStyle(fontSize: size * 0.9),
    ),
  );
}
