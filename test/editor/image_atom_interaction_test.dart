/// 图片原子交互(官方 NodeSelection 语义):点图整选不落光标、已选中
/// 再点上抛打开请求、选中态退格删、reselect 保选区、选中事件矩形上抛。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo_render/editor.dart';
import 'package:fluxdo_render/fluxdo_render.dart';

const _img = ImageRun(
    src: 'https://x/doge.png', alt: 'doge', width: 100, height: 80);

EditorState _doc() => EditorState(blocks: [
      TextBlock(
        id: 'e_0',
        content: EditableTextContent.fromInlines(const [
          TextRun('前'), _img, TextRun('后'),
        ]),
      ),
    ]);

void main() {
  Future<
      ({
        EditorState state,
        List<ImageAtomSelection?> selEvents,
        List<ImageAtomSelection> openEvents,
      })> pump(WidgetTester tester) async {
    final state = _doc();
    addTearDown(state.dispose);
    final selEvents = <ImageAtomSelection?>[];
    final openEvents = <ImageAtomSelection>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: FluxdoEditor(
            state: state,
            autofocus: true,
            onImageAtomSelectionChanged: selEvents.add,
            onImageAtomOpenRequest: openEvents.add,
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(); // 帧后事件
    return (state: state, selEvents: selEvents, openEvents: openEvents);
  }

  Future<void> tapImage(WidgetTester tester) async {
    await tester.tap(find.byType(Image, skipOffstage: false).first,
        warnIfMissed: false);
    await tester.pump();
    await tester.pump(); // _afterFrame 上抛
  }

  testWidgets('点图 = 整选原子(不落光标),事件带矩形贴图', (tester) async {
    final h = await pump(tester);
    await tapImage(tester);

    final sel = h.state.selection!;
    expect(sel.base.offset, 1);
    expect(sel.extent.offset, 2, reason: '整选 FFFC,非折叠光标');

    final ev = h.selEvents.last;
    expect(ev, isNotNull);
    expect(ev!.blockId, 'e_0');
    expect(ev.offset, 1);
    expect(ev.image, _img);
    final imgRect = tester.getRect(find.byType(Image).first);
    expect((ev.globalRect.center - imgRect.center).distance, lessThan(2),
        reason: '事件矩形贴图片渲染矩形');
  });

  testWidgets('已选中再点 → onImageAtomOpenRequest(选区不变)', (tester) async {
    final h = await pump(tester);
    await tapImage(tester);
    expect(h.openEvents, isEmpty);

    await tapImage(tester);
    expect(h.openEvents, hasLength(1));
    expect(h.openEvents.single.offset, 1);
    expect(h.state.selection!.extent.offset, 2, reason: '选区保持整选');
  });

  testWidgets('选中态退格 → 删原子,事件回 null', (tester) async {
    final h = await pump(tester);
    await tapImage(tester);

    h.state.backspace();
    await tester.pump();
    await tester.pump();

    final b = h.state.blocks.single as TextBlock;
    expect(b.content.text, '前后');
    expect(b.content.atoms, isEmpty);
    expect(h.selEvents.last, isNull, reason: '取消选中事件');
  });

  testWidgets('replaceAtomAt reselect:true → 选区保持,事件带新 ImageRun',
      (tester) async {
    final h = await pump(tester);
    await tapImage(tester);

    h.state.replaceAtomAt('e_0', 1, _img.copyWith(scale: 75), reselect: true);
    await tester.pump();
    await tester.pump();

    expect(h.state.selection!.base.offset, 1);
    expect(h.state.selection!.extent.offset, 2);
    final ev = h.selEvents.last;
    expect(ev, isNotNull);
    expect(ev!.image.scale, 75, reason: '事件携带更新后的 ImageRun');
  });

  testWidgets('点文字落光标(图原子路由不干扰正常编辑)', (tester) async {
    final h = await pump(tester);
    // 点段首文字位置(远离图片)
    final para = tester.getRect(find.textContaining('前').first);
    await tester.tapAt(para.centerLeft + const Offset(2, 0));
    await tester.pump();
    expect(h.state.selection!.isCollapsed, isTrue, reason: '文字处正常落光标');
  });
}
