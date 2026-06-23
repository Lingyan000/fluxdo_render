import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo_render/src/node/node.dart';
import 'package:fluxdo_render/src/parser/paragraph_parser.dart';

void main() {
  const parser = ParagraphParser();

  group('parser image 识别', () {
    test('普通 img 产生 ImageRun(无 width/height)', () {
      final result = parser.parse(
        '<p>x <img src="https://e.com/foo.png" alt="foo"> y</p>',
      );
      final p = result[0] as ParagraphNode;
      final img = p.inlines[1] as ImageRun;
      expect(img.src, 'https://e.com/foo.png');
      expect(img.alt, 'foo');
      expect(img.width, isNull);
      expect(img.height, isNull);
    });

    test('带 width/height attribute 解析为 double', () {
      final result = parser.parse(
        '<p><img src="x.png" width="200" height="120"></p>',
      );
      final p = result[0] as ParagraphNode;
      final img = p.inlines[0] as ImageRun;
      expect(img.width, 200);
      expect(img.height, 120);
    });

    test('class=emoji 走 EmojiRun 不走 ImageRun', () {
      final result = parser.parse(
        '<p><img src="h.png" class="emoji" title=":heart:"></p>',
      );
      final p = result[0] as ParagraphNode;
      expect(p.inlines[0], isA<EmojiRun>());
      expect(p.inlines[0], isNot(isA<ImageRun>()));
    });

    test('alt 缺失时 alt 为空串', () {
      final result = parser.parse('<p><img src="x.png"></p>');
      final p = result[0] as ParagraphNode;
      expect((p.inlines[0] as ImageRun).alt, '');
    });

    test('img 嵌套在 link 内', () {
      final result = parser.parse(
        '<p><a href="/big"><img src="thumb.png" width="100" height="100"></a></p>',
      );
      final p = result[0] as ParagraphNode;
      final link = p.inlines[0] as LinkRun;
      expect(link.children, hasLength(1));
      expect(link.children[0], isA<ImageRun>());
    });

    test('一段内多张图', () {
      final result = parser.parse(
        '<p><img src="a.png"> 和 <img src="b.png"></p>',
      );
      final p = result[0] as ParagraphNode;
      expect(p.inlines.whereType<ImageRun>(), hasLength(2));
    });

    test('width attribute 非数字时为 null(parse 容错)', () {
      final result = parser.parse(
        '<p><img src="x.png" width="auto" height="auto"></p>',
      );
      final p = result[0] as ParagraphNode;
      expect((p.inlines[0] as ImageRun).width, isNull);
      expect((p.inlines[0] as ImageRun).height, isNull);
    });
  });
}
