/// 新旧引擎运行时对照 widget。
///
/// 用途:dogfood 期间在详情页对每个 post 同时渲染 legacy + new,
/// 视觉发现不一致。golden 测试在 CI 跑像素级 diff,这里只做"看得见"。
///
/// 设计:
/// - 子包不依赖 legacy `DiscourseHtmlContent`(那是主项目代码)。
///   两侧 widget 都由调用方注入,本 widget 只负责"组合 + 切换"。
/// - 没有实时像素 diff —— 用 overlay / sideBySide 让人眼看到差异即可。
///   真正像素级 diff 在 golden test 做。
///
/// 调用方(主项目)示例:
/// ```dart
/// DualRenderWidget(
///   mode: ref.watch(dualRenderModeProvider),
///   legacy: DiscourseHtmlContent(html: post.cooked),
///   newImpl: FluxdoRender(cookedHtml: post.cooked),
/// )
/// ```
library;

import 'package:flutter/material.dart';

/// 对照模式。
enum DualRenderMode {
  /// 仅渲染 legacy(默认,等于灰度未开)。
  legacy,

  /// 仅渲染新引擎。
  newOnly,

  /// 上下排列,带边框 + label,人眼对比。
  sideBySide,

  /// 老版完整渲染,新版半透明叠在上面,人眼能看到偏移/差异。
  overlay;

  String get label => switch (this) {
        DualRenderMode.legacy => '仅 Legacy',
        DualRenderMode.newOnly => '仅 New',
        DualRenderMode.sideBySide => '并排对比',
        DualRenderMode.overlay => '叠加对比',
      };
}

/// 新旧引擎对照 widget。
class DualRenderWidget extends StatelessWidget {
  const DualRenderWidget({
    super.key,
    required this.mode,
    required this.legacy,
    required this.newImpl,
    this.overlayOpacity = 0.5,
    this.overlayColor,
  });

  /// 当前对照模式(通常来自 provider / 全局设置)。
  final DualRenderMode mode;

  /// 调用方注入的 legacy 渲染 widget(主项目里通常是 `DiscourseHtmlContent`)。
  final Widget legacy;

  /// 调用方注入的新引擎渲染 widget(主项目里通常是 `FluxdoRender`)。
  final Widget newImpl;

  /// overlay 模式下,新版的透明度(0.0-1.0)。默认 0.5。
  final double overlayOpacity;

  /// overlay 模式下,新版叠加层的色调(可选,默认无 tint)。
  /// 给新版叠加一个色调,能让"哪里来自新版"更醒目。
  final Color? overlayColor;

  @override
  Widget build(BuildContext context) {
    return switch (mode) {
      DualRenderMode.legacy => legacy,
      DualRenderMode.newOnly => newImpl,
      DualRenderMode.sideBySide => _SideBySide(legacy: legacy, newImpl: newImpl),
      DualRenderMode.overlay => _Overlay(
          legacy: legacy,
          newImpl: newImpl,
          opacity: overlayOpacity,
          color: overlayColor,
        ),
    };
  }
}

class _SideBySide extends StatelessWidget {
  const _SideBySide({required this.legacy, required this.newImpl});
  final Widget legacy;
  final Widget newImpl;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Labeled(label: 'LEGACY (fwfh)', color: Colors.blue, child: legacy),
        const SizedBox(height: 8),
        _Labeled(label: 'NEW (fluxdo_render)', color: Colors.green, child: newImpl),
      ],
    );
  }
}

class _Labeled extends StatelessWidget {
  const _Labeled({required this.label, required this.color, required this.child});
  final String label;
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: color, width: 1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            color: color,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Padding(padding: const EdgeInsets.all(4), child: child),
        ],
      ),
    );
  }
}

class _Overlay extends StatelessWidget {
  const _Overlay({
    required this.legacy,
    required this.newImpl,
    required this.opacity,
    required this.color,
  });

  final Widget legacy;
  final Widget newImpl;
  final double opacity;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    // 用 Stack 把新版叠在老版上,需要保证两侧 layout 一致才有意义。
    // Stack 默认按子 widget 最大 size 撑开,老版/新版分别按各自内容
    // 求高,会自然对齐(width 由父约束,height 由内容决定)。
    return Stack(
      alignment: AlignmentDirectional.topStart,
      children: [
        legacy,
        Positioned.fill(
          child: IgnorePointer(
            child: Opacity(
              opacity: opacity,
              child: color != null
                  ? ColorFiltered(
                      colorFilter: ColorFilter.mode(color!, BlendMode.modulate),
                      child: newImpl,
                    )
                  : newImpl,
            ),
          ),
        ),
      ],
    );
  }
}
