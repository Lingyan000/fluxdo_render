/// 把 BlockNode 渲染成 Flutter Widget。
///
/// 阶段 1 范围:Paragraph + Heading。
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
      HeadingNode() => buildHeading(context, node),
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

  /// 标题渲染 — 字号按 level 决定,默认值参考浏览器 UA stylesheet。
  ///
  /// h1=2em / h2=1.5em / h3=1.17em / h4=1em / h5=0.83em / h6=0.67em
  /// 字重统一 bold。垂直 padding 按 CSS heading margin(em 倍数)。
  Widget buildHeading(BuildContext context, HeadingNode node) {
    final theme = Theme.of(context);
    final baseStyle = theme.textTheme.bodyMedium ?? const TextStyle();
    final em = baseStyle.fontSize ?? 14;
    final scale = _headingScale[node.level - 1];
    final headingStyle = baseStyle.copyWith(
      fontSize: em * scale,
      fontWeight: FontWeight.bold,
      height: 1.2,
    );
    final span = _inlineFlattener.flatten(node.inlines, headingStyle);
    return Padding(
      padding: EdgeInsets.symmetric(
        vertical: em * _headingMargin[node.level - 1],
      ),
      child: Text.rich(span),
    );
  }

  // 索引 0 对应 h1
  static const _headingScale = [2.0, 1.5, 1.17, 1.0, 0.83, 0.67];

  // CSS heading margin(em 倍数,top/bottom 各一份)
  static const _headingMargin = [0.67, 0.83, 1.0, 1.33, 1.67, 2.33];
}
