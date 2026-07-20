/// 回车软换行(insertNewline)语义测试。
///
/// 背景:块间序列化用 `\n\n` → cook 成两个 `<p>`,行距比 Discourse 网页版
/// composer(回车插单个 `\n` → `<p>a<br>b</p>`)明显大。开关打开后回车
/// 插段内 `\n`。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo_render/editor.dart';

EditorState _stateWith(TextBlock block) {
  final s = EditorState(blocks: [block]);
  s.updateSelection(
    EditorSelection.collapsed(
      EditorPosition(blockId: block.id, offset: block.content.length),
    ),
  );
  return s;
}

TextBlock _para(String text) =>
    TextBlock(id: 'b0', content: EditableTextContent(text: text));

void main() {
  group('开关关闭(历史语义)', () {
    test('回车分块', () {
      final s = _stateWith(_para('abc'));
      s.insertNewline();
      expect(s.blocks.length, 2);
    });
  });

  group('开关打开', () {
    test('普通段落:回车插段内 \\n,不新建块', () {
      final s = _stateWith(_para('abc'))..enterInsertsSoftBreak = true;
      s.insertNewline();
      expect(s.blocks.length, 1);
      expect((s.blocks.single as TextBlock).content.text, 'abc\n');
    });

    test('连续两次仍是同一个块', () {
      final s = _stateWith(_para('a'))..enterInsertsSoftBreak = true;
      s.insertNewline();
      s.insertText('b');
      s.insertNewline();
      s.insertText('c');
      expect(s.blocks.length, 1);
      expect((s.blocks.single as TextBlock).content.text, 'a\nb\nc');
    });

    test('列表项仍分块(要接着开下一条)', () {
      final s = _stateWith(
        TextBlock(
          id: 'b0',
          content: EditableTextContent(text: '条目'),
          kind: TextBlockKind.listItem,
        ),
      )..enterInsertsSoftBreak = true;
      s.insertNewline();
      expect(s.blocks.length, 2, reason: '列表里软换行没有意义');
    });

    test('标题仍分块(要退出标题)', () {
      final s = _stateWith(
        TextBlock(
          id: 'b0',
          content: EditableTextContent(text: '标题'),
          kind: TextBlockKind.heading,
          headingLevel: 2,
        ),
      )..enterInsertsSoftBreak = true;
      s.insertNewline();
      expect(s.blocks.length, 2, reason: '标题里软换行没有意义');
    });
  });
}
