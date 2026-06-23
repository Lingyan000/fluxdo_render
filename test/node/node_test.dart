import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo_render/src/node/node.dart';

void main() {
  group('TextRun', () {
    test('==/hashCode 按 text 比较', () {
      const a = TextRun('hello');
      const b = TextRun('hello');
      const c = TextRun('world');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == c, isFalse);
    });
  });

  group('EmRun', () {
    test('==/hashCode 按 children listEquals', () {
      const a = EmRun(children: [TextRun('a'), TextRun('b')]);
      const b = EmRun(children: [TextRun('a'), TextRun('b')]);
      const c = EmRun(children: [TextRun('a')]);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == c, isFalse);
    });

    test('children 可嵌套 InlineNode', () {
      const nested = EmRun(
        children: [
          TextRun('outer '),
          StrongRun(children: [TextRun('inner')]),
        ],
      );
      expect(nested.children.length, 2);
      expect(nested.children[1], isA<StrongRun>());
    });
  });

  group('LineBreakRun', () {
    test('所有实例相等', () {
      const a = LineBreakRun();
      const b = LineBreakRun();
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('与其他 InlineNode 不相等', () {
      const br = LineBreakRun();
      const text = TextRun('');
      expect(br == text, isFalse);
    });
  });

  group('ParagraphNode', () {
    test('==/hashCode 按 inlines listEquals(忽略 id)', () {
      const a = ParagraphNode(
        id: 'b_0',
        inlines: [TextRun('hello'), LineBreakRun()],
      );
      const b = ParagraphNode(
        id: 'b_0',
        inlines: [TextRun('hello'), LineBreakRun()],
      );
      const c = ParagraphNode(id: 'b_1', inlines: [TextRun('hello')]);
      // 同 id 同内容 → 相等
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      // 不同内容(id 也可能不同) → 不相等
      expect(a == c, isFalse);
    });

    test('id 不参与 ==,只要内容相同就相等', () {
      const a = ParagraphNode(id: 'b_0', inlines: [TextRun('x')]);
      const b = ParagraphNode(id: 'b_99', inlines: [TextRun('x')]);
      // 不同 id 同内容 → 也相等(让 widget diff 不必要 rebuild)
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('id 字段可访问', () {
      const p = ParagraphNode(id: 'b_7', inlines: []);
      expect(p.id, 'b_7');
    });

    test('toString 含 id 和 inlines 数量', () {
      const p = ParagraphNode(
        id: 'b_2',
        inlines: [TextRun('a'), TextRun('b'), TextRun('c')],
      );
      expect(p.toString(), contains('b_2'));
      expect(p.toString(), contains('3 inlines'));
    });
  });

  group('sealed class exhaustiveness', () {
    test('BlockNode switch 必须覆盖所有 case', () {
      // 这是个编译期检查 — 如果新增 BlockNode 子类没在 switch 里,
      // analyzer 会报 non-exhaustive,这条用例只是 runtime 烟雾测试。
      const p = ParagraphNode(id: 'b_0', inlines: []);
      final label = switch (p) {
        ParagraphNode() => 'paragraph',
      };
      expect(label, 'paragraph');
    });

    test('InlineNode switch 必须覆盖所有 case', () {
      const list = <InlineNode>[
        TextRun('a'),
        EmRun(children: []),
        StrongRun(children: []),
        LineBreakRun(),
        LinkRun(href: 'https://example.com', children: [TextRun('x')]),
        InlineCodeRun('c'),
      ];
      final labels = list
          .map(
            (n) => switch (n) {
              TextRun() => 'text',
              EmRun() => 'em',
              StrongRun() => 'strong',
              LineBreakRun() => 'br',
              LinkRun() => 'link',
              InlineCodeRun() => 'inlineCode',
            },
          )
          .toList();
      expect(labels, ['text', 'em', 'strong', 'br', 'link', 'inlineCode']);
    });
  });

  group('InlineCodeRun', () {
    test('==/hashCode 按 text 比较', () {
      const a = InlineCodeRun('hello');
      const b = InlineCodeRun('hello');
      const c = InlineCodeRun('world');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == c, isFalse);
    });

    test('空串也可构造', () {
      const e = InlineCodeRun('');
      expect(e.text, '');
    });

    test('toString 含字符数', () {
      const c = InlineCodeRun('hello');
      expect(c.toString(), contains('5 chars'));
    });
  });
}
