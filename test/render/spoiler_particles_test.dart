/// D2 守护:spoiler 粒子动画。
/// - reduce-motion(MediaQuery.disableAnimations):静态遮罩,无粒子 painter、无
///   Ticker(确保 golden/pumpAndSettle 能 settle)。
/// - 动画态:未揭示时挂 SpoilerParticlePainter(粒子云遮盖)。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo_render/src/render/spoiler_particles.dart';
import 'package:fluxdo_render/src/widget/fluxdo_render.dart';

void main() {
  Finder particlePainter() => find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is SpoilerParticlePainter,
      );

  const spoilerHtml = '<p>答案 <span class="spoiler">42</span> 完</p>';

  testWidgets('reduce-motion:spoiler 静态遮罩,无粒子 painter(可 settle)',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (c) => MediaQuery(
              data: MediaQuery.of(c).copyWith(disableAnimations: true),
              child: const FluxdoRender(cookedHtml: spoilerHtml),
            ),
          ),
        ),
      ),
    );
    // 能 settle(无限 Ticker 被 reduce-motion 关掉)。
    await tester.pumpAndSettle();
    expect(particlePainter(), findsNothing,
        reason: 'reduce-motion 应走静态遮罩,不挂粒子 painter');
  });

  testWidgets('动画态:未揭示 spoiler 挂粒子 painter', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: FluxdoRender(cookedHtml: spoilerHtml)),
      ),
    );
    await tester.pump(); // 布局 + post-frame 初始化粒子
    await tester.pump(const Duration(milliseconds: 16)); // 推进一帧
    expect(particlePainter(), findsWidgets,
        reason: '动画态未揭示应挂 SpoilerParticlePainter');
    // 卸载以 dispose Ticker(避免活动 ticker 跨测试)。
    await tester.pumpWidget(const SizedBox());
  });
}
