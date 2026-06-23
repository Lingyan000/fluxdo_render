import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo_render/src/flatten/inline_flattener.dart';
import 'package:fluxdo_render/src/node/inline_node.dart';

void main() {
  const flattener = InlineFlattener();
  const baseStyle = TextStyle(fontSize: 14, color: Color(0xFF000000));

  test('空列表产出空 children', () {
    final result = flattener.flatten([], baseStyle);
    expect(result.span.style, baseStyle);
    expect(result.span.children, isEmpty);
    expect(result.recognizers, isEmpty);
  });

  test('纯文本', () {
    final result = flattener.flatten([const TextRun('hello')], baseStyle);
    final children = result.span.children!;
    expect(children, hasLength(1));
    expect((children[0] as TextSpan).text, 'hello');
  });

  test('em 注入 italic style', () {
    final result = flattener.flatten(
      [const EmRun(children: [TextRun('it')])],
      baseStyle,
    );
    final em = result.span.children![0] as TextSpan;
    expect(em.style?.fontStyle, FontStyle.italic);
    expect(em.children, hasLength(1));
    expect((em.children![0] as TextSpan).text, 'it');
  });

  test('strong 注入 bold style', () {
    final result = flattener.flatten(
      [const StrongRun(children: [TextRun('bd')])],
      baseStyle,
    );
    final strong = result.span.children![0] as TextSpan;
    expect(strong.style?.fontWeight, FontWeight.bold);
  });

  test('em 嵌套 strong 产生双层 span', () {
    final result = flattener.flatten(
      [
        const EmRun(
          children: [
            StrongRun(children: [TextRun('x')]),
          ],
        ),
      ],
      baseStyle,
    );
    final em = result.span.children![0] as TextSpan;
    final nestedStrong = em.children![0] as TextSpan;
    expect(em.style?.fontStyle, FontStyle.italic);
    expect(nestedStrong.style?.fontWeight, FontWeight.bold);
  });

  test('LineBreak 渲染为 \\n', () {
    final result = flattener.flatten(
      [
        const TextRun('a'),
        const LineBreakRun(),
        const TextRun('b'),
      ],
      baseStyle,
    );
    final children = result.span.children!;
    expect(children, hasLength(3));
    expect((children[1] as TextSpan).text, '\n');
  });

  test('混合复合段落保持顺序', () {
    final result = flattener.flatten(
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
    expect(result.span.children, hasLength(6));
  });

  group('LinkRun', () {
    testWidgets('有 context 时产生 TapGestureRecognizer', (tester) async {
      late BuildContext capturedContext;
      await tester.pumpWidget(
        Builder(
          builder: (ctx) {
            capturedContext = ctx;
            return const SizedBox();
          },
        ),
      );
      String? tapped;
      final result = flattener.flatten(
        [const LinkRun(href: 'https://example.com', children: [TextRun('go')])],
        baseStyle,
        context: capturedContext,
        linkHandler: (_, href) => tapped = href,
      );
      expect(result.recognizers, hasLength(1));
      expect(result.recognizers[0], isA<TapGestureRecognizer>());

      // 直接触发 onTap 验证 handler 被调
      (result.recognizers[0] as TapGestureRecognizer).onTap!();
      expect(tapped, 'https://example.com');

      // 清理 recognizer 避免 leak warning
      for (final r in result.recognizers) {
        r.dispose();
      }
    });

    test('无 context 时不创建 recognizer(link 不可点)', () {
      final result = flattener.flatten(
        [const LinkRun(href: 'https://example.com', children: [TextRun('go')])],
        baseStyle,
      );
      expect(result.recognizers, isEmpty);
      final linkSpan = result.span.children![0] as TextSpan;
      expect(linkSpan.recognizer, isNull);
    });

    test('link span 自带下划线样式 hint', () {
      final result = flattener.flatten(
        [const LinkRun(href: 'https://example.com', children: [TextRun('x')])],
        baseStyle,
      );
      final linkSpan = result.span.children![0] as TextSpan;
      expect(linkSpan.style?.decoration, TextDecoration.underline);
    });

    test('link 内嵌 strong 保留嵌套样式', () {
      final result = flattener.flatten(
        [
          const LinkRun(
            href: 'https://example.com',
            children: [
              TextRun('点击 '),
              StrongRun(children: [TextRun('粗体')]),
            ],
          ),
        ],
        baseStyle,
      );
      final linkSpan = result.span.children![0] as TextSpan;
      expect(linkSpan.children, hasLength(2));
      final strong = linkSpan.children![1] as TextSpan;
      expect(strong.style?.fontWeight, FontWeight.bold);
    });
  });

  group('InlineCodeRun', () {
    test('产出 monospace + background 的 TextSpan', () {
      final result = flattener.flatten(
        [const InlineCodeRun('git status')],
        baseStyle,
      );
      final span = result.span.children![0] as TextSpan;
      expect(span.text, 'git status');
      expect(span.style?.fontFamily, 'monospace');
      expect(span.style?.fontFamilyFallback, ['Menlo', 'Courier']);
      expect(span.style?.background, isNotNull);
      // 默认无 context → 走 light 灰底
      expect(
        span.style?.background?.color.toARGB32(),
        const Color(0xFFE8E8E8).toARGB32(),
      );
    });

    testWidgets('dark 主题用深灰底', (tester) async {
      late BuildContext capturedContext;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: Brightness.dark),
          home: Builder(
            builder: (ctx) {
              capturedContext = ctx;
              return const SizedBox();
            },
          ),
        ),
      );
      final result = flattener.flatten(
        [const InlineCodeRun('x')],
        baseStyle,
        context: capturedContext,
      );
      final span = result.span.children![0] as TextSpan;
      expect(
        span.style?.background?.color.toARGB32(),
        const Color(0xFF3A3A3A).toARGB32(),
      );
    });

    test('与 link / text 混排顺序保留', () {
      final result = flattener.flatten(
        [
          const TextRun('使用 '),
          const InlineCodeRun('git'),
          const TextRun(' 命令'),
        ],
        baseStyle,
      );
      final children = result.span.children!;
      expect(children, hasLength(3));
      expect((children[0] as TextSpan).text, '使用 ');
      expect((children[1] as TextSpan).text, 'git');
      expect((children[2] as TextSpan).text, ' 命令');
    });
  });
}
