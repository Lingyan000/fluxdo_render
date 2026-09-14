/// 行内 onebox 链接(裸 URL linkify)可编辑化:
/// 导入 = link mark 文本用 href;序列化 = text==attr 走裸 URL 规则
/// (不包 [text](url)、URL 内不转义);编辑后(text!=attr)回标准语法。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo_render/editor.dart';
import 'package:fluxdo_render/fluxdo_render.dart'
    show LinkRun, ParagraphNode, ParagraphParser, TextRun;

void main() {
  test('加载中的自动链接按裸 href 导入，不把 URL 编码差异当自定义标题', () {
    final nodes = ParagraphParser().parse(
      '<p>[<a href="https://github.com/%5C" '
      'class="inline-onebox-loading">https://github.com/\\</a>]('
      '<a href="https://github.com">https://github.com</a>)</p>',
    );
    final paragraph = nodes.single as ParagraphNode;
    final link = paragraph.inlines.whereType<LinkRun>().first;
    expect(link.isOneboxLink, isTrue);
    var n = 0;
    final doc = blockNodesToDoc(nodes, () => 'e_${n++}');
    expect(docToMarkdown(doc),
        r'\[https://github.com/%5C](https://github.com)');
  });

  test('裸链接之后的闭括号不转义，避免反斜杠被吸入地址', () {
    const url = 'https://example.com/path';
    final block = TextBlock(
      id: 'e_0',
      content: EditableTextContent(
        text: '[$url]',
        marks: [
          MarkSpan(start: 1, end: 1 + url.length,
              kind: MarkKind.link, attr: url),
        ],
      ),
    );
    expect(docToMarkdown([block]), r'\[https://example.com/path]');
  });

  test('inline-onebox 链接导入为可编辑 mark(文本=href)', () {
    const url = 'https://linux.do/t/topic/2587100';
    final doc = blockNodesToDoc(
      [
        ParagraphNode(id: 'b_0', inlines: const [
          TextRun('看这个 '),
          LinkRun(
            href: url,
            children: [TextRun('动态取回的页面标题')],
            isOneboxLink: true,
          ),
          TextRun(' 不错'),
        ]),
      ],
      () => 'e_0',
    );
    expect(doc, hasLength(1));
    final tb = doc.first as TextBlock;
    expect(tb.content.text, '看这个 $url 不错', reason: '显示 URL 非标题');
    final range = tb.content.linkRangeAt(5);
    expect(range, isNotNull);
    expect(range!.$3, url);
  });

  test('裸 URL 序列化:不包装不转义;编辑过的回 [text](url)', () {
    const url = 'https://x.test/a_b_c';
    final bare = TextBlock(
      id: 'e_0',
      content: EditableTextContent(
        text: '前 $url 后',
        marks: [
          MarkSpan(start: 2, end: 2 + url.length, kind: MarkKind.link, attr: url),
        ],
      ),
    );
    expect(docToMarkdown([bare]), '前 $url 后',
        reason: '裸 URL 原样(下划线不转义,无 [] 包装)');

    final edited = TextBlock(
      id: 'e_1',
      content: EditableTextContent(
        text: '前 说明文字 后',
        marks: const [
          MarkSpan(start: 2, end: 6, kind: MarkKind.link, attr: url),
        ],
      ),
    );
    expect(docToMarkdown([edited]), '前 [说明文字]($url) 后',
        reason: 'text!=href 走标准链接语法');
  });

  test('往返:含行内 onebox 链接的段落 doc→md→(结构自证)', () {
    const url = 'https://linux.do/t/topic/123';
    final doc = blockNodesToDoc(
      [
        ParagraphNode(id: 'b_0', inlines: const [
          TextRun('a '),
          LinkRun(href: url, children: [TextRun('标题')], isOneboxLink: true),
          TextRun(' b'),
        ]),
      ],
      () => 'e_0',
    );
    expect(docToMarkdown(doc), 'a $url b', reason: 'raw 保持裸 URL');
  });
}
