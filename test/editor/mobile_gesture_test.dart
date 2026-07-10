/// 移动端手势(设备分流):触摸竖滑=滚动不拖选、长按选词+手柄+动作条、
/// 双击选词、长按图原子=整选、长按岛=不误选邻段。
library;

import 'package:flutter/gestures.dart' show PointerDeviceKind, kLongPressTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo_render/editor.dart';
import 'package:fluxdo_render/fluxdo_render.dart';

Future<(ScrollController, EditorState)> pumpMobile(
  WidgetTester tester, {
  List<String> paragraphs = const ['hello world foo', 'second paragraph here'],
  List<EditorBlock>? blocks,
}) async {
  final state = blocks != null
      ? EditorState(blocks: blocks)
      : EditorState.fromTexts(paragraphs);
  addTearDown(state.dispose);
  final scroll = ScrollController();
  addTearDown(scroll.dispose);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        controller: scroll,
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          FluxdoEditor(state: state, autofocus: true),
          const SizedBox(height: 2000), // 保证可滚
        ]),
      ),
    ),
  ));
  await tester.pump();
  return (scroll, state);
}

void main() {
  testWidgets('触摸竖滑 = 页面滚动,选区不变(pan 不进竞技场)',
      (tester) async {
    final (scroll, state) = await pumpMobile(tester);
    final before = state.selection;

    final g = await tester.startGesture(
      tester.getCenter(find.byType(FluxdoEditor)),
      kind: PointerDeviceKind.touch,
    );
    for (var i = 0; i < 8; i++) {
      await g.moveBy(const Offset(0, -30));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await tester.pump();

    expect(scroll.offset, greaterThan(50), reason: '滚动生效');
    expect(state.selection, before, reason: '选区未被拖选劫持');
  });

  testWidgets('长按 = 选词 + 手柄 + 动作条;触摸后收 UI', (tester) async {
    final (_, state) = await pumpMobile(tester);
    // 长按 "world"(首段中间词)
    final para = tester.getRect(find.textContaining('hello').first);
    final target = Offset(para.left + 90, para.center.dy);

    final g = await tester.startGesture(target,
        kind: PointerDeviceKind.touch);
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await g.up();
    await tester.pump();
    await tester.pump(); // _afterFrame → 手柄/动作条

    final sel = state.selection!;
    expect(sel.isCollapsed, isFalse, reason: '长按选中了词');
    final tb = state.blocks.first as TextBlock;
    final word = tb.content.text.substring(
      sel.base.offset < sel.extent.offset ? sel.base.offset : sel.extent.offset,
      sel.base.offset < sel.extent.offset ? sel.extent.offset : sel.base.offset,
    );
    expect(word.trim(), isNotEmpty);
    expect(word.contains(' '), isFalse, reason: '单词粒度: "$word"');

    // 动作条出现(系统 AdaptiveTextSelectionToolbar)
    expect(find.byType(TextSelectionToolbarTextButton), findsWidgets);

    // 点别处(第二段,远离动作条浮层)落光标 → 触摸选区 UI 收
    final para2 = tester.getRect(find.textContaining('second').first);
    await tester.tapAt(Offset(para2.left + 4, para2.center.dy));
    await tester.pump();
    await tester.pump();
    expect(state.selection!.isCollapsed, isTrue);
  });

  testWidgets('双击(触摸连击)= 选词', (tester) async {
    final (_, state) = await pumpMobile(tester);
    final para = tester.getRect(find.textContaining('hello').first);
    final target = Offset(para.left + 20, para.center.dy);

    await tester.tapAt(target);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tapAt(target);
    await tester.pump();

    final sel = state.selection!;
    expect(sel.isCollapsed, isFalse, reason: '双击选词');
  });

  testWidgets('长按图片原子 = 整选(不选词不弹词边界)', (tester) async {
    const img = ImageRun(
        src: 'https://x/a.png', alt: 'a', width: 60, height: 40);
    final (_, state) = await pumpMobile(tester, blocks: [
      TextBlock(
        id: 'e_0',
        content: EditableTextContent.fromInlines(
            const [TextRun('前'), img, TextRun('后')]),
      ),
    ]);

    final imgRect = tester.getRect(find.byType(Image).first);
    final g = await tester.startGesture(imgRect.center,
        kind: PointerDeviceKind.touch);
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await g.up();
    await tester.pump();

    final sel = state.selection!;
    expect(sel.base.offset, 1);
    expect(sel.extent.offset, 2, reason: '图原子整选');
  });

  testWidgets('长按岛(代码块)= 让路不误选邻段', (tester) async {
    final (_, state) = await pumpMobile(tester, blocks: [
      TextBlock(id: 'e_0', content: EditableTextContent(text: '邻段文字')),
      const IslandBlock(
        id: 'e_isl',
        node: CodeBlockNode(id: 'b_0', code: 'code here', language: 'py'),
      ),
    ]);
    final before = state.selection;

    final g = await tester.startGesture(
      tester.getCenter(find.byType(EditorIsland)),
      kind: PointerDeviceKind.touch,
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await g.up();
    await tester.pump();

    // 岛让路:长按不产生任何选区变化(尤其不能选中"邻段文字"的词)
    expect(state.selection, before);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('鼠标拖选不受分流影响(桌面回归)', (tester) async {
    final (scroll, state) = await pumpMobile(tester);
    final para = tester.getRect(find.textContaining('hello').first);

    final g = await tester.startGesture(
      Offset(para.left + 4, para.center.dy),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(const Duration(milliseconds: 40));
    for (var i = 0; i < 6; i++) {
      await g.moveBy(const Offset(18, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await tester.pump();

    expect(state.selection!.isCollapsed, isFalse, reason: '鼠标拖选生效');
    expect(scroll.offset, 0, reason: '鼠标拖选不滚动');
  });
}
