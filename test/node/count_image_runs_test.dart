import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo_render/src/node/node.dart';
import 'package:fluxdo_render/src/parser/paragraph_parser.dart';

void main() {
  group('countImageRuns', () {
    test('空 list 返回 0', () {
      expect(countImageRuns([]), 0);
    });

    test('无 image 的节点返回 0', () {
      const nodes = <BlockNode>[
        ParagraphNode(id: 'b_0', inlines: [TextRun('hello')]),
        HeadingNode(id: 'b_1', level: 1, inlines: [TextRun('h')]),
        HorizontalRuleNode(id: 'b_2'),
      ];
      expect(countImageRuns(nodes), 0);
    });

    test('emoji 不计数(只 ImageRun)', () {
      const nodes = <BlockNode>[
        ParagraphNode(id: 'b_0', inlines: [
          EmojiRun(name: 'heart', url: 'x.png'),
        ]),
      ];
      expect(countImageRuns(nodes), 0);
    });

    test('paragraph 内 ImageRun 计数', () {
      const nodes = <BlockNode>[
        ParagraphNode(id: 'b_0', inlines: [
          ImageRun(src: 'a.png'),
          TextRun(' 中间 '),
          ImageRun(src: 'b.png'),
        ]),
      ];
      expect(countImageRuns(nodes), 2);
    });

    test('blockquote / list 嵌套递归计数', () {
      // 用真 parser 产生(避免手写 ListItem 复杂)
      final parser = ParagraphParser();
      final nodes = parser.parse(
        '<p><img src="a.png"></p>'
        '<blockquote><p><img src="b.png"></p></blockquote>'
        '<ul><li><img src="c.png"></li><li>纯文本</li></ul>',
      );
      expect(countImageRuns(nodes), 3);
    });

    test('link 内嵌 image 也计数', () {
      const nodes = <BlockNode>[
        ParagraphNode(id: 'b_0', inlines: [
          LinkRun(href: '/x', children: [
            ImageRun(src: 'thumb.png'),
          ]),
        ]),
      ];
      expect(countImageRuns(nodes), 1);
    });
  });
}
