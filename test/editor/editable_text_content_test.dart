import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo_render/src/editor/model/editable_text_content.dart';
import 'package:fluxdo_render/src/node/inline_node.dart';

void main() {
  group('EditableTextContent.fromInlines / toInlines 往返', () {
    test('纯文本', () {
      final c = EditableTextContent.fromInlines(const [TextRun('hello 世界')]);
      expect(c.text, 'hello 世界');
      expect(c.marks, isEmpty);
      expect(c.toInlines(), const [TextRun('hello 世界')]);
    });

    test('粗体+斜体嵌套展开为区间', () {
      final c = EditableTextContent.fromInlines(const [
        TextRun('a'),
        StrongRun(children: [
          TextRun('b'),
          EmRun(children: [TextRun('c')]),
        ]),
        TextRun('d'),
      ]);
      expect(c.text, 'abcd');
      expect(
        c.marks,
        const [
          MarkSpan(start: 1, end: 3, kind: MarkKind.strong),
          MarkSpan(start: 2, end: 3, kind: MarkKind.em),
        ],
      );
      // 往返:树形状可以不同(碎段),但语义等价 —— 再来一轮扁平化必须相等
      final round = EditableTextContent.fromInlines(c.toInlines());
      expect(round, c);
    });

    test('行内代码 + <br>', () {
      final c = EditableTextContent.fromInlines(const [
        TextRun('说 '),
        InlineCodeRun('var x'),
        LineBreakRun(),
        TextRun('第二行'),
      ]);
      expect(c.text, '说 var x\n第二行');
      expect(c.marks, const [MarkSpan(start: 2, end: 7, kind: MarkKind.inlineCode)]);
      final inlines = c.toInlines();
      expect(inlines, const [
        TextRun('说 '),
        InlineCodeRun('var x'),
        LineBreakRun(),
        TextRun('第二行'),
      ]);
    });

    test('M1 降级:emoji/mention 收编为投影文本', () {
      final c = EditableTextContent.fromInlines(const [
        TextRun('hi '),
        EmojiRun(name: 'heart', url: 'u'),
        TextRun(' '),
        MentionRun(username: 'sam', href: '/u/sam'),
      ]);
      expect(c.text, 'hi :heart: @sam');
    });
  });

  group('编辑原语', () {
    final base = EditableTextContent(
      text: 'abcdef',
      marks: const [MarkSpan(start: 2, end: 4, kind: MarkKind.strong)], // cd
    );

    test('insert 在区间前:区间右移', () {
      final r = base.insert(0, 'xx');
      expect(r.text, 'xxabcdef');
      expect(r.marks, const [MarkSpan(start: 4, end: 6, kind: MarkKind.strong)]);
    });

    test('insert 在区间内部:区间拉长(样式延续)', () {
      final r = base.insert(3, 'X');
      expect(r.text, 'abcXdef');
      expect(r.marks, const [MarkSpan(start: 2, end: 5, kind: MarkKind.strong)]);
    });

    test('insert 恰在区间末端边界:不延续', () {
      final r = base.insert(4, 'X');
      expect(r.text, 'abcdXef');
      expect(r.marks, const [MarkSpan(start: 2, end: 4, kind: MarkKind.strong)]);
    });

    test('delete 覆盖区间左半:区间收缩', () {
      final r = base.delete(1, 3); // 删 bc
      expect(r.text, 'adef');
      expect(r.marks, const [MarkSpan(start: 1, end: 2, kind: MarkKind.strong)]);
    });

    test('delete 完全覆盖区间:区间消失', () {
      final r = base.delete(1, 5);
      expect(r.text, 'af');
      expect(r.marks, isEmpty);
    });

    test('replace = delete+insert', () {
      final r = base.replace(2, 4, '你好啊');
      expect(r.text, 'ab你好啊ef');
    });

    test('split 区间跨切点:两侧各留一半', () {
      final (before, after) = base.split(3);
      expect(before.text, 'abc');
      expect(before.marks, const [MarkSpan(start: 2, end: 3, kind: MarkKind.strong)]);
      expect(after.text, 'def');
      expect(after.marks, const [MarkSpan(start: 0, end: 1, kind: MarkKind.strong)]);
    });

    test('concat 区间平移', () {
      final other = EditableTextContent(
        text: 'gh',
        marks: const [MarkSpan(start: 0, end: 2, kind: MarkKind.em)],
      );
      final r = base.concat(other);
      expect(r.text, 'abcdefgh');
      expect(r.marks, const [
        MarkSpan(start: 2, end: 4, kind: MarkKind.strong),
        MarkSpan(start: 6, end: 8, kind: MarkKind.em),
      ]);
    });
  });
}
