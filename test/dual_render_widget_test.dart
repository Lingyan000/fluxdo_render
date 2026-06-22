import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo_render/fluxdo_render.dart';

void main() {
  const legacy = Text('LEGACY-CONTENT');
  const newImpl = Text('NEW-CONTENT');

  Future<void> pump(WidgetTester tester, DualRenderMode mode) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DualRenderWidget(
            mode: mode,
            legacy: legacy,
            newImpl: newImpl,
          ),
        ),
      ),
    );
  }

  group('DualRenderWidget mode 切换', () {
    testWidgets('legacy 模式只显示 legacy', (tester) async {
      await pump(tester, DualRenderMode.legacy);
      expect(find.text('LEGACY-CONTENT'), findsOneWidget);
      expect(find.text('NEW-CONTENT'), findsNothing);
    });

    testWidgets('newOnly 模式只显示新引擎', (tester) async {
      await pump(tester, DualRenderMode.newOnly);
      expect(find.text('LEGACY-CONTENT'), findsNothing);
      expect(find.text('NEW-CONTENT'), findsOneWidget);
    });

    testWidgets('sideBySide 模式两侧都显示且都被 label 包裹', (tester) async {
      await pump(tester, DualRenderMode.sideBySide);
      expect(find.text('LEGACY-CONTENT'), findsOneWidget);
      expect(find.text('NEW-CONTENT'), findsOneWidget);
      expect(find.text('LEGACY (fwfh)'), findsOneWidget);
      expect(find.text('NEW (fluxdo_render)'), findsOneWidget);
    });

    testWidgets('overlay 模式两侧都在 tree 中(叠加)', (tester) async {
      await pump(tester, DualRenderMode.overlay);
      expect(find.text('LEGACY-CONTENT'), findsOneWidget);
      expect(find.text('NEW-CONTENT'), findsOneWidget);
      // overlay 模式用 Stack 把新版叠在老版上,新版被 IgnorePointer + Opacity 包裹
      expect(find.byType(Stack), findsWidgets);
      // 找 ignoring=true 的 IgnorePointer(我们这层叠加专属;Scaffold 内部
      // 也有几个 IgnorePointer 但 ignoring=false)
      final ignoring = tester.widgetList<IgnorePointer>(find.byType(IgnorePointer))
          .where((w) => w.ignoring)
          .toList();
      expect(ignoring, hasLength(1));
      expect(find.byType(Opacity), findsOneWidget);
    });
  });

  test('DualRenderMode.label 返回中文标签', () {
    expect(DualRenderMode.legacy.label, '仅 Legacy');
    expect(DualRenderMode.newOnly.label, '仅 New');
    expect(DualRenderMode.sideBySide.label, '并排对比');
    expect(DualRenderMode.overlay.label, '叠加对比');
  });
}
