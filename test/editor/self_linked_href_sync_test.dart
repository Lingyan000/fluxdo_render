/// 「文本即链接」的裸链接:改文字时 href 要跟着改,否则切源码就成了
/// `[改过的文字](原地址)` —— 显示一个地址、跳另一个。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo_render/src/editor/model/editable_text_content.dart';

const _url = 'https://linux.do/t/topic/2659942/18?u=is_hp';

EditableTextContent _bareLink() => EditableTextContent(
      text: _url,
      marks: [
        MarkSpan(start: 0, end: _url.length, kind: MarkKind.link, attr: _url),
      ],
    );

void main() {
  test('删掉查询参数:href 跟着变', () {
    final c = _bareLink();
    final cut = c.delete(_url.indexOf('?'), _url.length);

    expect(cut.text, 'https://linux.do/t/topic/2659942/18');
    expect(cut.marks.single.attr, cut.text, reason: '两边必须还相等');
  });

  test('末尾续打字符:href 跟着变', () {
    final c = _bareLink();
    final added = c.insert(_url.length - 1, 'X');

    expect(added.marks.single.attr, added.text);
  });

  test('自定义文案的链接不受影响', () {
    const label = '点我';
    final c = EditableTextContent(
      text: label,
      marks: [
        MarkSpan(start: 0, end: label.length, kind: MarkKind.link, attr: _url),
      ],
    );

    final edited = c.insert(label.length, '看看');

    expect(edited.text, '点我看看');
    expect(edited.marks.single.attr, _url, reason: '自定义文案不联动');
  });
}
