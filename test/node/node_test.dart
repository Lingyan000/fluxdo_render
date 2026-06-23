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
    test('==/hashCode 按 inlines listEquals', () {
      const a = ParagraphNode(inlines: [TextRun('hello'), LineBreakRun()]);
      const b = ParagraphNode(inlines: [TextRun('hello'), LineBreakRun()]);
      const c = ParagraphNode(inlines: [TextRun('hello')]);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == c, isFalse);
    });

    test('toString 含 inlines 数量', () {
      const p = ParagraphNode(
        inlines: [TextRun('a'), TextRun('b'), TextRun('c')],
      );
      expect(p.toString(), contains('3 inlines'));
    });
  });

  group('sealed class exhaustiveness', () {
    test('BlockNode switch 必须覆盖所有 case', () {
      // 这是个编译期检查 — 如果新增 BlockNode 子类没在 switch 里,
      // analyzer 会报 non-exhaustive,这条用例只是 runtime 烟雾测试。
      const p = ParagraphNode(inlines: []);
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
      ];
      final labels = list
          .map(
            (n) => switch (n) {
              TextRun() => 'text',
              EmRun() => 'em',
              StrongRun() => 'strong',
              LineBreakRun() => 'br',
            },
          )
          .toList();
      expect(labels, ['text', 'em', 'strong', 'br']);
    });
  });
}
