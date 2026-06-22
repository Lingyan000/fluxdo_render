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

  testWidgets('reposition 选区滚动 → toolbar 跟随移动,且始终夹在视口内可见',
      (tester) async {
    final t = await mountToolbar(tester, onQuote: (_) {});
    t.show(dataAt(const Rect.fromLTWH(100, 300, 80, 20)));
    await tester.pump();
    final mat = find.ancestor(
        of: find.text('复制'), matching: find.byType(Material));
    expect(mat, findsOneWidget);
    final y0 = tester.getTopLeft(mat.first).dy;

    // 选区上移(模拟滚动)→ toolbar 跟着上移(连续,不是突然消失)。
    t.reposition(dataAt(const Rect.fromLTWH(100, 200, 80, 20)));
    await tester.pump();
    final y1 = tester.getTopLeft(mat.first).dy;
    expect(y1, lessThan(y0), reason: 'toolbar 应跟随选区连续上移');

    // 选区滚到屏幕上方很远(仍有可见几何)→ toolbar **夹在视口内保持可见**
    // (对齐 Discourse:floating-ui shift,始终可见;而非滑出屏幕)。
    t.reposition(dataAt(const Rect.fromLTWH(100, -500, 80, 20)));
    await tester.pump();
    final y2 = tester.getTopLeft(mat.first).dy;
    expect(y2, greaterThanOrEqualTo(0.0),
        reason: 'toolbar 夹在视口内,始终可见(不滑出屏幕)');
    t.hide();
  });

  testWidgets('选区比视口还高(顶/底都出界,中段可见)→ toolbar 仍在视口内可见',
      (tester) async {
    final t = await mountToolbar(tester, onQuote: (_) {});
    // 选区从 y=-200 到 y=1000(高 1200 > 视口 800),视口只显示中段。
    t.show(SelectionData(
      plainText: 'hello',
      globalBounds: const Rect.fromLTWH(100, -200, 80, 1200),
      globalRects: const [Rect.fromLTWH(100, -200, 80, 1200)],
    ));
    await tester.pump();
    final pos = tester.getTopLeft(find.text('复制'));
    // 工具栏必须落在视口内(之前会跑到屏幕外 → 看不见)。
    expect(pos.dy, greaterThanOrEqualTo(0.0));
    expect(pos.dy, lessThan(800.0),
        reason: '选区跨满视口时,工具栏夹到视口内,始终可见');
    t.hide();
  });

  testWidgets('选区完全滚出视口(无可见块)→ toolbar 隐藏(滚回再现)',
      (tester) async {
    final t = await mountToolbar(tester, onQuote: (_) {});
    t.show(dataAt(const Rect.fromLTWH(100, 300, 80, 20)));
    await tester.pump();
    expect(find.text('复制'), findsOneWidget);
    // 无可见几何(globalRects 空)→ 不显示。
    t.reposition(const SelectionData(
      plainText: 'hello',
      globalBounds: Rect.zero,
      globalRects: [],
    ));
    await tester.pump();
    expect(find.text('复制'), findsNothing,
        reason: '选区完全滚出视口时工具栏隐藏');
    t.hide();
  });

  testWidgets('滚动时水平冻结:可见块切换(bounds.left 变)也不左右跳',
      (tester) async {
    final t = await mountToolbar(tester, onQuote: (_) {});
    t.show(dataAt(const Rect.fromLTWH(100, 400, 80, 20)));
    await tester.pump();
    final mat = find.ancestor(
        of: find.text('复制'), matching: find.byType(Material));
    final x0 = tester.getTopLeft(mat.first).dx;

    // 模拟滚动后「首个可见块」切换 → 外接框左缘跳到 200;但竖直滚动不该改水平,
    // reposition 须冻结水平 x(不随之左右跳)。
    t.reposition(dataAt(const Rect.fromLTWH(200, 350, 80, 20)));
    await tester.pump();
    final x1 = tester.getTopLeft(mat.first).dx;
    expect(x1, closeTo(x0, 0.5),
        reason: '滚动 reposition 应冻结水平,不随可见块切换左右跳');
    t.hide();
  });

  testWidgets('reposition yCompensation 抵消滚动滞后(toolbar 预平移 delta)',
      (tester) async {
    final t = await mountToolbar(tester, onQuote: (_) {});
    t.show(dataAt(const Rect.fromLTWH(100, 400, 80, 20)));
    await tester.pump();
    final mat = find.ancestor(
        of: find.text('复制'), matching: find.byType(Material));
    final y0 = tester.getTopLeft(mat.first).dy;

    // 同样几何但补偿 60 → toolbar 上移 60(与内容同帧对齐,消抖)。
    t.reposition(dataAt(const Rect.fromLTWH(100, 400, 80, 20)),
        yCompensation: 60);
    await tester.pump();
    final y1 = tester.getTopLeft(mat.first).dy;
    expect(y1, closeTo(y0 - 60, 0.5),
        reason: 'yCompensation=60 → toolbar 竖直预平移 60(抵消一帧滚动滞后)');
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

  testWidgets('上方放不下(越过安全线)→ toolbar 翻到选区下方', (tester) async {
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
    // 测试环境 padding.top=0,安全线 = kToolbarHeight(56)。
    // 选区在 y=60:上方 60-40-8=12 < 56 → 放不下 → 翻下方。
    final t = SelectionToolbar(context: ctx, onQuote: (_) {}, onCopied: null);
    t.show(dataAt(const Rect.fromLTWH(100, 60, 80, 20)));
    await tester.pump();

    // toolbar 应在选区下方(top > 选区 bottom=80),不遮挡顶部。
    final pos = tester.getTopLeft(find.text('复制'));
    expect(pos.dy, greaterThan(60),
        reason: '上方放不下应翻到选区下方,不遮挡安全线以上');
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
    final t = SelectionToolbar(context: ctx, onQuote: (_) {}, onCopied: null);
    // 选区在 y=400,上方空间充足。
    t.show(dataAt(const Rect.fromLTWH(100, 400, 80, 20)));
    await tester.pump();
    final pos = tester.getTopLeft(find.text('复制'));
    expect(pos.dy, lessThan(400), reason: '上方放得下应在选区上方');
    t.hide();
  });

  testWidgets('选区靠屏幕右边 → toolbar 夹回视口内(shift)', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(builder: (c) {
            ctx = c;
            return const SizedBox.expand();
          }),
        ),
      ),
    );
    final screenW = tester.view.physicalSize.width / tester.view.devicePixelRatio;
    final t = SelectionToolbar(context: ctx, onQuote: (_) {}, onCopied: null);
    // 选区贴右边缘
    t.show(dataAt(Rect.fromLTWH(screenW - 30, 400, 20, 20)));
    await tester.pump();
    // toolbar 整体不应超出右边界(右沿 ≤ 屏宽)。
    final tbMaterial = find.ancestor(
      of: find.text('复制'),
      matching: find.byType(Material),
    );
    final tr = tester.getTopRight(tbMaterial.first);
    expect(tr.dx, lessThanOrEqualTo(screenW),
        reason: 'shift 应把 toolbar 夹回视口内,不超右边界');
    t.hide();
  });

  testWidgets('左对齐选区起点(top-start,非居中)', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(builder: (c) {
            ctx = c;
            return const SizedBox.expand();
          }),
        ),
      ),
    );
    final t = SelectionToolbar(context: ctx, onQuote: (_) {}, onCopied: null);
    // 屏幕中部一个很宽的选区(left=100,宽 200)。
    t.show(SelectionData(
      plainText: 'x',
      globalBounds: const Rect.fromLTWH(100, 400, 200, 20),
      globalRects: const [Rect.fromLTWH(100, 400, 200, 20)],
    ));
    await tester.pump();
    // 定位 toolbar 自身的 Material(含「复制」文字的那个,非 Scaffold 外层)。
    final toolbarMaterial = find.ancestor(
      of: find.text('复制'),
      matching: find.byType(Material),
    );
    final tlx = tester.getTopLeft(toolbarMaterial.first).dx;
    // 左对齐选区起点(≈100),而非居中(居中会是 100+100-w/2 ≈ 120 偏右)。
    expect((tlx - 100).abs(), lessThan(8),
        reason: 'toolbar 应左对齐选区起点 100,不是居中');
    t.hide();
  });
}
