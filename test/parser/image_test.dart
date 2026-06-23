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

    test('indexInPost 按出现顺序 0,1,2 递增', () {
      final result = parser.parse(
        '<p><img src="a.png"></p>'
        '<p>中间段</p>'
        '<p><img src="b.png"> 和 <img src="c.png"></p>',
      );
      final imgs = <ImageRun>[];
      for (final n in result.whereType<ParagraphNode>()) {
        imgs.addAll(n.inlines.whereType<ImageRun>());
      }
      expect(imgs, hasLength(3));
      expect(imgs[0].indexInPost, 0);
      expect(imgs[1].indexInPost, 1);
      expect(imgs[2].indexInPost, 2);
    });

    test('indexInPost 跨 blockquote / list 嵌套全局连续', () {
      final result = parser.parse(
        '<p><img src="a.png"></p>'
        '<blockquote><p><img src="b.png"></p></blockquote>'
        '<ul><li><img src="c.png"></li></ul>',
      );
      final imgs = <ImageRun>[];
      void scan(BlockNode b) {
        switch (b) {
          case ParagraphNode(:final inlines):
            imgs.addAll(inlines.whereType<ImageRun>());
          case BlockquoteNode(:final children):
            for (final c in children) {
              scan(c);
            }
          case ListNode(:final items):
            for (final i in items) {
              imgs.addAll(i.inlines.whereType<ImageRun>());
            }
          case _:
            break;
        }
      }
      result.forEach(scan);
      expect(imgs.map((e) => e.indexInPost), [0, 1, 2]);
    });

    test('emoji img 不参与 indexInPost 计数', () {
      final result = parser.parse(
        '<p>'
        '<img src="e1.png" class="emoji" alt=":heart:">'
        '<img src="a.png">'
        '<img src="e2.png" class="emoji" alt=":fire:">'
        '<img src="b.png">'
        '</p>',
      );
      final p = result[0] as ParagraphNode;
      final imgs = p.inlines.whereType<ImageRun>().toList();
      expect(imgs, hasLength(2));
      expect(imgs[0].indexInPost, 0);
      expect(imgs[1].indexInPost, 1);
    });
  });
}
