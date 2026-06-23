import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo_render/src/flatten/inline_flattener.dart';
import 'package:fluxdo_render/src/node/inline_node.dart';

void main() {
  const flattener = InlineFlattener();
  const baseStyle = TextStyle(fontSize: 14, color: Color(0xFF000000));

  test('空列表产出空 children', () {
    final span = flattener.flatten([], baseStyle);
    expect(span.style, baseStyle);
    expect(span.children, isEmpty);
  });

  test('纯文本', () {
    final span = flattener.flatten([const TextRun('hello')], baseStyle);
    expect(span.children, hasLength(1));
    final inner = span.children![0] as TextSpan;
    expect(inner.text, 'hello');
  });

  test('em 注入 italic style,style 不含 baseStyle(merge 由 RichText 完成)', () {
    final span = flattener.flatten(
      [const EmRun(children: [TextRun('it')])],
      baseStyle,
    );
    final em = span.children![0] as TextSpan;
    expect(em.style?.fontStyle, FontStyle.italic);
    expect(em.children, hasLength(1));
    expect((em.children![0] as TextSpan).text, 'it');
  });

  test('strong 注入 bold style', () {
    final span = flattener.flatten(
      [const StrongRun(children: [TextRun('bd')])],
      baseStyle,
    );
    final strong = span.children![0] as TextSpan;
    expect(strong.style?.fontWeight, FontWeight.bold);
  });

  test('em 嵌套 strong 产生双层 span', () {
    final span = flattener.flatten(
      [
        const EmRun(
          children: [
            StrongRun(children: [TextRun('x')]),
          ],
        ),
      ],
      baseStyle,
    );
    final em = span.children![0] as TextSpan;
    final nestedStrong = em.children![0] as TextSpan;
    expect(em.style?.fontStyle, FontStyle.italic);
    expect(nestedStrong.style?.fontWeight, FontWeight.bold);
    // Flutter RichText 渲染时会自动 merge 父子 style,所以 nested 的
    // text 实际呈现 italic + bold
  });

  test('LineBreak 渲染为 \\n', () {
    final span = flattener.flatten(
      [
        const TextRun('a'),
        const LineBreakRun(),
        const TextRun('b'),
      ],
      baseStyle,
    );
    expect(span.children, hasLength(3));
    expect((span.children![1] as TextSpan).text, '\n');
  });

  test('混合复合段落保持顺序', () {
    final span = flattener.flatten(
      [
        const TextRun('hello '),
        const StrongRun(children: [TextRun('bold')]),
        const TextRun(' and '),
        const EmRun(children: [TextRun('italic')]),
        const LineBreakRun(),
        const TextRun('newline'),
      ],
      baseStyle,
    );
    expect(span.children, hasLength(6));
  });
}
