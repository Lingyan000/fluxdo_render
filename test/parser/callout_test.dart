import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo_render/src/node/node.dart';
import 'package:fluxdo_render/src/parser/paragraph_parser.dart';

void main() {
  final parser = ParagraphParser();

  group('parser callout 识别', () {
    test('最简形态 [!note] → CalloutNode + kind=note + 默认配置', () {
      final result = parser.parse(
        '<blockquote><p>[!note]<br>正文一行</p></blockquote>',
      );
      expect(result, hasLength(1));
      final c = result[0] as CalloutNode;
      expect(c.kind, CalloutKind.note);
      expect(c.typeRaw, 'note');
      expect(c.title, isNull);
      expect(c.foldable, isNull);
      expect(c.children, hasLength(1));
      expect(c.children[0], isA<ParagraphNode>());
      final p = c.children[0] as ParagraphNode;
      expect(p.inlines, isNotEmpty);
      expect((p.inlines.first as TextRun).text.trim(), '正文一行');
    });

    test('[!warning] 自定义标题 → title 提取', () {
      final result = parser.parse(
        '<blockquote><p>[!warning] 操作不可逆<br>请确认</p></blockquote>',
      );
      final c = result[0] as CalloutNode;
      expect(c.kind, CalloutKind.warning);
      expect(c.title, '操作不可逆');
      expect(c.foldable, isNull);
    });

    test('[!tip]+ → foldable=true (默认展开)', () {
      final result = parser.parse(
        '<blockquote><p>[!tip]+ 标题<br>正文</p></blockquote>',
      );
      final c = result[0] as CalloutNode;
      expect(c.kind, CalloutKind.tip);
      expect(c.foldable, isTrue);
      expect(c.title, '标题');
    });

    test('[!danger]- → foldable=false (默认折叠)', () {
      final result = parser.parse(
        '<blockquote><p>[!danger]- 不要点<br>正文</p></blockquote>',
      );
      final c = result[0] as CalloutNode;
      expect(c.kind, CalloutKind.danger);
      expect(c.foldable, isFalse);
    });

    test('未知类型 [!xyz] → CalloutKind.unknown + typeRaw 保留', () {
      final result = parser.parse(
        '<blockquote><p>[!xyz]<br>正文</p></blockquote>',
      );
      final c = result[0] as CalloutNode;
      expect(c.kind, CalloutKind.unknown);
      expect(c.typeRaw, 'xyz');
    });

    test('别名映射:abstract/summary/tldr → CalloutKind.summary', () {
      for (final type in const ['abstract', 'summary', 'tldr']) {
        final result = parser.parse(
          '<blockquote><p>[!$type]<br>x</p></blockquote>',
        );
        final c = result[0] as CalloutNode;
        expect(c.kind, CalloutKind.summary, reason: '别名 $type 应映射到 summary');
      }
    });

    test('别名映射:tip/hint/important → CalloutKind.tip', () {
      for (final type in const ['tip', 'hint', 'important']) {
        final result = parser.parse(
          '<blockquote><p>[!$type]<br>x</p></blockquote>',
        );
        final c = result[0] as CalloutNode;
        expect(c.kind, CalloutKind.tip);
      }
    });

    test('多段正文:首段 br 后 inline + 后续 p 都进 children', () {
      final result = parser.parse(
        '<blockquote>'
        '<p>[!info] 标题<br>第一段</p>'
        '<p>第二段</p>'
        '</blockquote>',
      );
      final c = result[0] as CalloutNode;
      expect(c.children, hasLength(2));
      expect(c.children[0], isA<ParagraphNode>());
      expect(c.children[1], isA<ParagraphNode>());
      final p1 = c.children[0] as ParagraphNode;
      final p2 = c.children[1] as ParagraphNode;
      expect((p1.inlines.first as TextRun).text.trim(), '第一段');
      expect((p2.inlines.first as TextRun).text.trim(), '第二段');
    });

    test('普通 blockquote(无 [!type])仍回落 BlockquoteNode', () {
      final result = parser.parse(
        '<blockquote><p>这只是普通引用</p></blockquote>',
      );
      expect(result[0], isA<BlockquoteNode>());
    });

    test('callout 内含 list / code 等混合块级', () {
      final result = parser.parse(
        '<blockquote>'
        '<p>[!example]+ 示例<br>下面是步骤</p>'
        '<ul><li>步骤一</li></ul>'
        '<pre><code class="lang-dart">print("hi");</code></pre>'
        '</blockquote>',
      );
      final c = result[0] as CalloutNode;
      expect(c.kind, CalloutKind.example);
      expect(c.foldable, isTrue);
      expect(c.children, hasLength(3));
      expect(c.children[0], isA<ParagraphNode>());
      expect(c.children[1], isA<ListNode>());
      expect(c.children[2], isA<CodeBlockNode>());
    });

    test('首段无 br + 仅标记行 → callout 但 children 为空', () {
      final result = parser.parse(
        '<blockquote><p>[!quote]</p></blockquote>',
      );
      final c = result[0] as CalloutNode;
      expect(c.kind, CalloutKind.quote);
      expect(c.children, isEmpty);
    });

    test('id 在嵌套场景下全局唯一', () {
      final result = parser.parse(
        '<blockquote>'
        '<p>[!note]<br>a</p>'
        '<p>b</p>'
        '</blockquote>',
      );
      final c = result[0] as CalloutNode;
      final p1 = c.children[0] as ParagraphNode;
      final p2 = c.children[1] as ParagraphNode;
      expect({c.id, p1.id, p2.id}, hasLength(3));
    });

    test('CalloutKind.fromType 大小写敏感:大写不识别(parser 已 lowercase)', () {
      // parser 内部已经做了 lowercase,这里直接测 enum 的契约
      expect(CalloutKind.fromType('NOTE'), CalloutKind.unknown);
      expect(CalloutKind.fromType('note'), CalloutKind.note);
    });
  });
}
