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

  testWidgets('上方放不下(越过 topBoundary)→ toolbar 翻到选区下方', (tester) async {
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
    // topBoundary 全局 y=100(模拟 AppBar 下沿)。选区在 y=110,上方放不下。
    final t = SelectionToolbar(
      context: ctx,
      onQuote: (_) {},
      onCopied: null,
      topBoundaryGlobal: () => 100,
    );
    t.show(dataAt(const Rect.fromLTWH(100, 110, 80, 20)));
    await tester.pump();

    // toolbar 应在选区下方(top > 选区 bottom=130),而非上方(会 < 100 遮挡)。
    final pos = tester.getTopLeft(find.text('复制'));
    expect(pos.dy, greaterThan(110),
        reason: '上方放不下应翻到选区下方,不遮挡 topBoundary 以上');
    t.hide();
  });

  testWidgets('上方放得下 → toolbar 在选区上方', (tester) async {
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
    final t = SelectionToolbar(
      context: ctx,
      onQuote: (_) {},
      onCopied: null,
      topBoundaryGlobal: () => 100,
    );
    // 选区在 y=400,上方空间充足。
    t.show(dataAt(const Rect.fromLTWH(100, 400, 80, 20)));
    await tester.pump();
    final pos = tester.getTopLeft(find.text('复制'));
    expect(pos.dy, lessThan(400), reason: '上方放得下应在选区上方');
    t.hide();
  });
}
