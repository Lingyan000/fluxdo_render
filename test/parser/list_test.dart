import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo_render/src/node/node.dart';
import 'package:fluxdo_render/src/parser/paragraph_parser.dart';

void main() {
  const parser = ParagraphParser();

  group('parser list 识别', () {
    test('ul 产生 ListNode(ordered=false)', () {
      final result = parser.parse('<ul><li>a</li><li>b</li></ul>');
      expect(result, hasLength(1));
      final list = result[0] as ListNode;
      expect(list.ordered, isFalse);
      expect(list.depth, 0);
      expect(list.items, hasLength(2));
      expect(list.items[0].inlines, [const TextRun('a')]);
      expect(list.items[1].inlines, [const TextRun('b')]);
    });

    test('ol 产生 ListNode(ordered=true)', () {
      final result = parser.parse('<ol><li>第一</li><li>第二</li></ol>');
      expect(result, hasLength(1));
      final list = result[0] as ListNode;
      expect(list.ordered, isTrue);
      expect(list.items, hasLength(2));
    });

    test('li 内含 inline 混排', () {
      final result = parser.parse(
        '<ul><li>含 <strong>粗</strong> 和 <a href="/x">链接</a></li></ul>',
      );
      final list = result[0] as ListNode;
      final item = list.items[0];
      // text + strong + text + link + nothing(trailing 空)
      expect(item.inlines.length, greaterThanOrEqualTo(3));
      expect(item.inlines.whereType<StrongRun>(), hasLength(1));
      expect(item.inlines.whereType<LinkRun>(), hasLength(1));
    });

    test('li 内嵌套 ul → children 不为空', () {
      final result = parser.parse(
        '<ul><li>外<ul><li>内</li></ul></li></ul>',
      );
      final outer = result[0] as ListNode;
      final item = outer.items[0];
      expect(item.children, isNotNull);
      expect(item.children, hasLength(1));
      final inner = item.children![0];
      expect(inner.ordered, isFalse);
      expect(inner.depth, 1);
      expect(inner.items[0].inlines, [const TextRun('内')]);
    });

    test('li 内嵌套 ol → depth 递增', () {
      final result = parser.parse(
        '<ul><li>x<ol><li>1<ul><li>深</li></ul></li></ol></li></ul>',
      );
      final outer = result[0] as ListNode;
      final lvl1 = outer.items[0].children![0];
      expect(lvl1.depth, 1);
      expect(lvl1.ordered, isTrue);
      final lvl2 = lvl1.items[0].children![0];
      expect(lvl2.depth, 2);
      expect(lvl2.ordered, isFalse);
    });

    test('叶子 li children = null', () {
      final result = parser.parse('<ul><li>x</li></ul>');
      final list = result[0] as ListNode;
      expect(list.items[0].children, isNull);
    });

    test('list 跟 p 混排,各自独立 BlockNode', () {
      final result = parser.parse(
        '<p>前</p><ul><li>a</li></ul><p>后</p>',
      );
      expect(result, hasLength(3));
      expect(result[0], isA<ParagraphNode>());
      expect(result[1], isA<ListNode>());
      expect(result[2], isA<ParagraphNode>());
    });

    test('id 在嵌套场景下全局唯一,不冲突', () {
      final result = parser.parse(
        '<ul><li>a<ul><li>b</li></ul></li></ul><p>c</p>',
      );
      final outer = result[0] as ListNode;
      final inner = outer.items[0].children![0];
      final p = result[1] as ParagraphNode;
      // 三个 BlockNode 各自有独立 id
      expect({outer.id, inner.id, p.id}, hasLength(3));
    });

    test('非 li 子节点(白噪音 text)被忽略', () {
      final result = parser.parse('<ul>  \n  <li>x</li>  \n  </ul>');
      final list = result[0] as ListNode;
      expect(list.items, hasLength(1));
    });
  });
}
