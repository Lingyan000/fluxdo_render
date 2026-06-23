import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo_render/src/node/node.dart';
import 'package:fluxdo_render/src/parser/paragraph_parser.dart';

void main() {
  final parser = ParagraphParser();

  group('parser 跳过纯展示元素(svg / d-icon / meta / lb-spacer)', () {
    test('inline <svg> 完全跳过,不留任何 inline', () {
      final result = parser.parse(
        '<p>前 <svg class="d-icon"><use href="#x"></use></svg> 后</p>',
      );
      final p = result[0] as ParagraphNode;
      // 期望:只有 "前 " + " 后",svg 完全不进 inline
      expect(p.inlines.length, 2);
      expect(p.inlines[0], const TextRun('前 '));
      expect(p.inlines[1], const TextRun(' 后'));
    });

    test('span.d-icon 跳过', () {
      final result = parser.parse(
        '<p>前 <span class="d-icon">icon-text-shouldnt-show</span> 后</p>',
      );
      final p = result[0] as ParagraphNode;
      expect(p.inlines, hasLength(2));
      expect(p.inlines.whereType<TextRun>().map((e) => e.text), ['前 ', ' 后']);
    });

    test('div.meta 在块级 fallback 时跳过(不产生 ParagraphNode)', () {
      final result = parser.parse(
        '<div class="meta">hidden filename + 1686×128 15.7 KB</div>',
      );
      // div.meta 走块级 default 分支,_isSkipElement 跳过 → 不产节点
      expect(result, isEmpty);
    });

    test('div.lb-spacer 跳过(legacy 是 lightbox 占位高度)', () {
      final result = parser.parse('<div class="lb-spacer"></div>');
      expect(result, isEmpty);
    });

    test('block 级 <svg> 跳过', () {
      final result = parser.parse('<svg width="100" height="100"><use href="#x"/></svg>');
      expect(result, isEmpty);
    });
  });

  group('parser ins / del / s / sup / sub 形态', () {
    test('<ins> 降级 EmRun', () {
      final result = parser.parse('<p>x <ins>new</ins> y</p>');
      final p = result[0] as ParagraphNode;
      expect(p.inlines.whereType<EmRun>(), hasLength(1));
    });

    test('<del> 展平内容(无样式但保留文字)', () {
      final result = parser.parse('<p>x <del>old</del> y</p>');
      final p = result[0] as ParagraphNode;
      // del 不产独立节点;old 作为 TextRun 加入 → "x " + "old" + " y"
      // 中间字串可能合并也可能分,但 "old" 一定在
      final allText = p.inlines.whereType<TextRun>().map((e) => e.text).join();
      expect(allText, contains('old'));
    });

    test('<s>(同 del)展平', () {
      final result = parser.parse('<p>x <s>strike</s> y</p>');
      final p = result[0] as ParagraphNode;
      final allText = p.inlines.whereType<TextRun>().map((e) => e.text).join();
      expect(allText, contains('strike'));
    });

    test('<sup> / <sub> 展平内容', () {
      final result = parser.parse('<p>H<sub>2</sub>O 和 E=mc<sup>2</sup></p>');
      final p = result[0] as ParagraphNode;
      final allText = p.inlines.whereType<TextRun>().map((e) => e.text).join();
      expect(allText, allOf(contains('2'), contains('mc')));
    });
  });

  group('parser 顶层裸 br 跳过(消除 block 之间空行)', () {
    test('两个 block 之间裸 br 不产 ParagraphNode', () {
      final result = parser.parse('<p>1</p><br><p>2</p>');
      expect(result, hasLength(2));
      expect(result.every((n) => n is ParagraphNode), isTrue);
    });

    test('inline 内的 br 仍正常产 LineBreakRun', () {
      final result = parser.parse('<p>a<br>b</p>');
      final p = result[0] as ParagraphNode;
      expect(p.inlines.whereType<LineBreakRun>(), hasLength(1));
    });
  });
}
