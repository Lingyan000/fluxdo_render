import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo_render/src/selection/selection_data.dart';
import 'package:fluxdo_render/src/selection/selection_toolbar.dart';

void main() {
  // 用一个能拿到 Overlay 的 host 测 toolbar show/reposition/hide。
  Future<SelectionToolbar> mountToolbar(
    WidgetTester tester, {
    required void Function(String) onQuote,
  }) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(builder: (c) {
            ctx = c;
            return const SizedBox(width: 400, height: 800);
          }),
        ),
      ),
    );
    return SelectionToolbar(context: ctx, onQuote: onQuote, onCopied: null);
  }

  SelectionData dataAt(Rect bounds) => SelectionData(
        plainText: 'hello',
        globalBounds: bounds,
        globalRects: [bounds],
      );

  testWidgets('show 弹出 toolbar(复制/引用按钮可见)', (tester) async {
    final t = await mountToolbar(tester, onQuote: (_) {});
    t.show(dataAt(const Rect.fromLTWH(100, 300, 80, 20)));
    await tester.pump();
    expect(find.text('复制'), findsOneWidget);
    expect(find.text('引用'), findsOneWidget);
    t.hide();
    await tester.pump();
    expect(find.text('复制'), findsNothing);
  });

  testWidgets('reposition 选区滚出视口 → toolbar 隐藏内容', (tester) async {
    final t = await mountToolbar(tester, onQuote: (_) {});
    t.show(dataAt(const Rect.fromLTWH(100, 300, 80, 20)));
    await tester.pump();
    expect(find.text('复制'), findsOneWidget);

    // 选区移到屏幕上方很远(y=-500,完全在 overlay 之外)
    t.reposition(dataAt(const Rect.fromLTWH(100, -500, 80, 20)));
    await tester.pump();
    expect(find.text('复制'), findsNothing, reason: '滚出视口应隐藏');

    // 滚回视口内 → 重新显示
    t.reposition(dataAt(const Rect.fromLTWH(100, 200, 80, 20)));
    await tester.pump();
    expect(find.text('复制'), findsOneWidget, reason: '滚回应重显');
    t.hide();
  });

  testWidgets('reposition(null) 隐藏 toolbar', (tester) async {
    final t = await mountToolbar(tester, onQuote: (_) {});
    t.show(dataAt(const Rect.fromLTWH(100, 300, 80, 20)));
    await tester.pump();
    t.reposition(null);
    await tester.pump();
    expect(find.text('复制'), findsNothing);
  });

  testWidgets('引用按钮回调 plainText', (tester) async {
    String? quoted;
    final t = await mountToolbar(tester, onQuote: (s) => quoted = s);
    t.show(dataAt(const Rect.fromLTWH(100, 300, 80, 20)));
    await tester.pump();
    await tester.tap(find.text('引用'));
    await tester.pump();
    expect(quoted, 'hello');
  });
}
