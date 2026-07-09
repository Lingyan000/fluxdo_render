/// 孤岛集成 widget 测试:选岛/删岛/registry 隔离/岛前后建段。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo_render/editor.dart';
import 'package:fluxdo_render/src/node/node.dart';

EditorState makeDoc() => EditorState(blocks: [
      TextBlock(id: 'e_0', content: EditableTextContent(text: 'aaa')),
      const IslandBlock(
        id: 'e_1',
        node: CodeBlockNode(id: 'b_0', code: 'print(1)', language: 'py'),
      ),
      TextBlock(id: 'e_2', content: EditableTextContent(text: 'bbb')),
    ]);

Future<EditorState> pumpEditor(WidgetTester tester, EditorState state) async {
  addTearDown(state.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: FluxdoEditor(
            state: state,
            autofocus: true,
            baseTextStyle: const TextStyle(fontSize: 16, height: 1.6),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return state;
}

void main() {
  testWidgets('岛用 NodeFactory 渲染(能找到代码文本)', (tester) async {
    await pumpEditor(tester, makeDoc());
    expect(find.textContaining('print(1)', findRichText: true), findsOneWidget);
  });

  testWidgets('tap 岛 → 整选 + 选中描边;退格删岛', (tester) async {
    final state = await pumpEditor(tester, makeDoc());
    await tester.tap(find.byType(EditorIsland));
    await tester.pump();
    expect(state.selection!.base,
        const EditorPosition(blockId: 'e_1', offset: 0));
    expect(state.selection!.extent,
        const EditorPosition(blockId: 'e_1', offset: 1));
    expect(
      tester.widget<EditorIsland>(find.byType(EditorIsland)).selected,
      true,
    );
    // 整选态退格 → 删岛
    state.backspace();
    await tester.pump();
    expect(state.blocks.whereType<IslandBlock>(), isEmpty);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('岛内块不注册进编辑器 registry(选区隔离)', (tester) async {
    final state = await pumpEditor(tester, makeDoc());
    // 编辑器 registry 只应有 2 个文本块(e_0/e_2);codeblock 的
    // SelectableTextBox 注册进 EditorIsland 的哑控制器
    // 通过点击 codeblock 文本区域验证:命中不落进岛内部 → tap 走整选
    final islandRect = tester.getRect(find.byType(EditorIsland));
    await tester.tapAt(islandRect.center);
    await tester.pump();
    expect(state.selection!.base.blockId, 'e_1');
    expect(state.selection!.isCollapsed, false);
    // 光标/选区仍能落回文本块
    state.updateSelection(const EditorSelection.collapsed(
      EditorPosition(blockId: 'e_0', offset: 1),
    ));
    await tester.pump();
    expect(state.selection!.extent.blockId, 'e_0');
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('岛整选态回车:岛后建空段', (tester) async {
    final state = await pumpEditor(tester, makeDoc());
    await tester.tap(find.byType(EditorIsland));
    await tester.pump();
    state.splitBlock();
    await tester.pump();
    expect(state.blocks.length, 4);
    expect(state.blocks[2], isA<TextBlock>());
    expect((state.blocks[2] as TextBlock).content.text, '');
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('AbsorbPointer 冻结岛内交互(无手势穿透崩溃)', (tester) async {
    await pumpEditor(tester, makeDoc());
    // codeblock 内长按/拖动均不应触发岛内部手势
    await tester.longPress(find.byType(EditorIsland));
    await tester.pump();
    // 不崩即过(岛内 recognizer 被 AbsorbPointer 挡住)
    await tester.pump(const Duration(seconds: 1));
  });

  // ---- 图片岛缩放胶囊(位置贴合 + 选中切换零重建)回归 ----

  EditorState makeImageDoc() => EditorState(blocks: [
        TextBlock(id: 'e_0', content: EditableTextContent(text: 'aaa')),
        const IslandBlock(
          id: 'e_img',
          node: ParagraphNode(id: 'b_0', inlines: [
            // 窄图(宽 120):编辑器列宽远大于它 —— 胶囊若相对全宽层
            // 定位会飘出图片右缘老远(回归:必须贴图)
            ImageRun(
                src: 'upload://x.png',
                width: 120,
                height: 90,
                scale: 100,
                previewImageIndex: 0),
          ]),
        ),
      ]);

  Future<EditorState> pumpImageEditor(WidgetTester tester) async {
    final state = makeImageDoc();
    addTearDown(state.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: FluxdoEditor(
              state: state,
              autofocus: true,
              onImageScale: (island, image, scale) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return state;
  }

  testWidgets('缩放胶囊贴图片右上角(不飘到编辑器右缘)', (tester) async {
    await pumpImageEditor(tester);
    await tester.tap(find.byType(EditorIsland));
    await tester.pump();

    final bar = find.byType(EditorImageScaleBar);
    expect(bar, findsOneWidget);
    final barRect = tester.getRect(bar);
    final islandRect = tester.getRect(find.byType(EditorIsland));
    // 岛(GestureDetector 层)被编辑器拉满列宽;胶囊必须贴内容
    // (图 120 宽 + 描边/padding ≈ 128),而不是岛的右缘
    expect(barRect.right, lessThan(islandRect.left + 200),
        reason: '胶囊 right=${barRect.right} 应贴 120px 宽的图,'
            '而不是飘向岛右缘 ${islandRect.right}');
  });

  testWidgets('选中/取消选中:图片子树 Element 不重建(不闪)', (tester) async {
    final state = await pumpImageEditor(tester);

    Element imageElement() =>
        tester.element(find.byType(Image, skipOffstage: false).first);

    final before = imageElement();
    // 选中
    await tester.tap(find.byType(EditorIsland));
    await tester.pump();
    expect(find.byType(EditorImageScaleBar), findsOneWidget);
    expect(identical(imageElement(), before), isTrue,
        reason: '选中态切换重建了图片 Element → 闪一帧占位');
    // 取消选中(光标回文本块)
    state.updateSelection(const EditorSelection.collapsed(
        EditorPosition(blockId: 'e_0', offset: 0)));
    await tester.pump();
    expect(find.byType(EditorImageScaleBar), findsNothing);
    expect(identical(imageElement(), before), isTrue);
  });

  testWidgets('点胶囊:选区不被编辑器清掉(down 不落光标),切档回调触发',
      (tester) async {
    // 复刻真实接线:onImageScale 改 scale 后 updateIslandNode
    final state = makeImageDoc();
    addTearDown(state.dispose);
    var scaled = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: FluxdoEditor(
              state: state,
              autofocus: true,
              onImageScale: (island, image, scale) {
                scaled = scale;
                final para = island.node as ParagraphNode;
                state.updateIslandNode(
                  island.id,
                  para.copyWith(inlines: [
                    (para.inlines.single as ImageRun)
                        .copyWith(scale: scale.toDouble()),
                  ]),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // 整选出胶囊
    await tester.tap(find.byType(EditorIsland));
    await tester.pump();
    expect(find.byType(EditorImageScaleBar), findsOneWidget);
    final sel = state.selection!;
    expect(sel.base.blockId, 'e_img');

    // 点 75% 档。核心回归:pointer-down 瞬间编辑器若不让路会先清
    // 整选 → 胶囊当帧卸载 → up 时 onTap 丢失(点一下就消失,档没切)。
    await tester.tap(find.text('75%'));
    await tester.pump();

    expect(scaled, 75, reason: '切档回调必须触发');
    expect(state.selection!.base.blockId, 'e_img',
        reason: '整选保持,胶囊不消失');
    expect(find.byType(EditorImageScaleBar), findsOneWidget);
    // 新档位生效(75% 变 active,不可再点)
    expect(
        ((state.blocks[1] as IslandBlock).node as ParagraphNode)
            .inlines
            .single,
        isA<ImageRun>().having((i) => i.scale, 'scale', 75));
    // 排空双击窗口 timer(岛 onDoubleTap recognizer)
    await tester.pump(const Duration(seconds: 1));
  });
}
