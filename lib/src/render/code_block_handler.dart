/// 渲染代码块时主项目要提供的 highlighter 签名。
///
/// 子包不依赖 highlight.js / mermaid / chart 等重量级库,通过这个 typedef
/// 注入。主项目侧用 HighlighterService(highlight.js)+ Mermaid 等真正渲染;
/// 不传时子包用纯 monospace 显示原始 code。
///
/// **mermaid 路由**:主项目在 highlighter 内判断 `language == 'mermaid'`
/// 返回 MermaidWidget,否则走高亮代码 widget。子包不区分 —— 都给同一个
/// highlighter,语言由它决定。
///
/// 调用方:
/// ```dart
/// FluxdoRender(
///   cookedHtml: ...,
///   codeBlockHighlighter: (ctx, code, language) {
///     if (language == 'mermaid') return MermaidWidget(code: code);
///     return HighlightedCodeText(code: code, language: language);
///   },
/// );
/// ```

library;

import 'package:flutter/material.dart';

/// 代码块 highlighter。返回应该是**只含代码内容**的 widget(monospace
/// text / 高亮后 RichText / mermaid 图),外面的灰底容器 + 顶栏 chip +
/// 复制按钮由子包 NodeFactory 包好,这个 callback 不用管。
typedef CodeBlockHighlighter = Widget Function(
  BuildContext context,
  String code,
  String? language,
);

/// 默认 highlighter —— 纯 monospace Text,无颜色。
///
/// 主项目接入时**应该**注入自定义 highlighter(highlight.js + mermaid)。
Widget defaultCodeBlockHighlighter(
  BuildContext context,
  String code,
  String? language,
) {
  return Text(
    code,
    style: const TextStyle(
      fontFamily: 'FiraCode',
      fontFamilyFallback: ['monospace', 'Menlo', 'Courier'],
      fontSize: 13,
      height: 1.4,
    ),
  );
}
