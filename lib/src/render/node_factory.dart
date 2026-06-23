/// 把 BlockNode 渲染成 Flutter Widget。
///
/// 阶段 1.1 范围:仅 ParagraphNode。
/// 设计上预留 sub-class 扩展点 — 主项目场景里(用户卡 bio / 通知 / AI 分享卡
/// 等)可以继承 NodeFactory 在 build* 方法里加 wrapper(如:简化版不让点
/// 链接、AI 分享卡内禁用图片)。
///
/// 后续阶段加新 BlockNode 时,新增对应 buildXxx 并在 build dispatch 里
/// 加 case;sealed class 编译期保证不漏。

library;

import 'package:flutter/material.dart';

import '../flatten/inline_flattener.dart';
import '../node/node.dart';

class NodeFactory {
  NodeFactory({
    InlineFlattener? inlineFlattener,
  }) : _inlineFlattener = inlineFlattener ?? const InlineFlattener();

  final InlineFlattener _inlineFlattener;

  /// 入口 dispatch — sealed class exhaustive switch。
  Widget build(BuildContext context, BlockNode node) {
    return switch (node) {
      ParagraphNode() => buildParagraph(context, node),
    };
  }

  /// 段落渲染 — 默认 RichText + padding。
  ///
  /// 子类可 override 实现段落级别的定制(如调字号、加 margin)。
  Widget buildParagraph(BuildContext context, ParagraphNode node) {
    final theme = Theme.of(context);
    final baseStyle = theme.textTheme.bodyMedium ?? const TextStyle();
    final span = _inlineFlattener.flatten(node.inlines, baseStyle);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text.rich(span),
    );
  }
}
