/// 回归:表格 cell 编辑时,退格/方向键必须进 cell TextField,
/// 不能被编辑器 Focus.onKeyEvent 拦走(症状:只能覆盖不能删改)。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo_render/src/editor/model/doc_converter.dart';
import 'package:fluxdo_render/src/editor/model/editor_state.dart';
import 'package:fluxdo_render/src/editor/widget/fluxdo_editor.dart';
import 'package:fluxdo_render/src/parser/paragraph_parser.dart';

void main() {
  testWidgets('cell 编辑中退格删字符(不被编辑器拦截)', (tester) async {
    var n = 0;
    final state = EditorState(
        blocks: blockNodesToDoc(
            ParagraphParser().parse(
                '<p>正文</p>'
                '<div class="md-table"><table><tbody><tr><td>ABC</td></tr></tbody></table></div>'),
            () => 'e_${n++}'));
    addTearDown(state.dispose);
    String? edited;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: FluxdoEditor(
            state: state,
            onTableEdited: (island, md) => edited = md,
          ),
        ),
      ),
    ));
    await tester.pump();

    // 点 cell 进入编辑(初值 ABC,自动全选)
    await tester.tap(find.text('ABC'));
    await tester.pump();
    await tester.pump(); // post-frame 焦点请求
    final tf = find.byType(TextField);
    expect(tf, findsOneWidget);

    // 光标移到末尾(取消全选),退格删一个字符
    final controller = tester.widget<TextField>(tf).controller!;
    controller.selection = TextSelection.collapsed(
        offset: controller.text.length);
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();
    expect(controller.text, 'AB',
        reason: '退格必须删 cell 字符 —— 被编辑器 onKeyEvent 拦走则不变');

    // 方向键也不该被拦(左移后中间插入)
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(controller.selection.baseOffset, 1);

    // 编辑器文档不受牵连(正文块没被退格改掉)
    final para = state.blocks.first;
    expect((para as dynamic).content.text, '正文');

    // 提交(失焦:点正文)→ onTableEdited 收到新 markdown
    // (硬件 Enter 在 widget 测试不走 IME action,onSubmitted 不触发;
    // 真机两条路都通,失焦是共同路径)
    await tester.tap(find.textContaining('正文', findRichText: true));
    await tester.pump();
    expect(edited, isNotNull);
    expect(edited, contains('AB'));
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('cell 失焦回编辑器正文:编辑器按键恢复正常', (tester) async {
    var n = 0;
    final state = EditorState(
        blocks: blockNodesToDoc(
            ParagraphParser().parse(
                '<p>xy</p>'
                '<div class="md-table"><table><tbody><tr><td>A</td></tr></tbody></table></div>'),
            () => 'e_${n++}'));
    addTearDown(state.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: FluxdoEditor(state: state, onTableEdited: (i, m) {}),
        ),
      ),
    ));
    await tester.pump();

    // 进 cell 再点回正文
    await tester.tap(find.text('A'));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.textContaining('xy', findRichText: true));
    await tester.pump();

    // 正文块尾退格:编辑器处理(删 y)
    state.updateSelection(EditorSelection.collapsed(
        EditorPosition(blockId: state.blocks.first.id, offset: 2)));
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();
    expect((state.blocks.first as dynamic).content.text, 'x');
    await tester.pump(const Duration(seconds: 1));
  });
}
