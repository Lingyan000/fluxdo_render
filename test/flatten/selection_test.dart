/// 新引擎选区接入测试。
///
/// 验证 InlineFlattener 产出的 WidgetSpan 在 SelectionArea 下贡献的纯文本
/// 与原始 cooked 的文本投影对齐——这是划词引用(HtmlTextMapper 在
/// post.cooked 里 DFS 匹配选区纯文本)能工作的前提。
///
/// 核心断言:
/// - emoji(EmojiRun)→ `:name:`(对齐 `<img class="emoji" title=":name:">`)
/// - click-count(ClickCountRun,preprocess 注入)→ 不进选区(原始 cooked 没有)
/// - mention(MentionRun)→ `@username`(对齐 `<a class="mention">@username</a>`)
/// - 普通文本 / 链接 / 行内代码 → 原文
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo_render/src/flatten/inline_flattener.dart';
import 'package:fluxdo_render/src/node/inline_node.dart';
import 'package:fluxdo_render/src/render/inline_span_text.dart';

void main() {
  const flattener = InlineFlattener();

  /// 用 InlineSpanText 渲染一段 inline 节点,全选后返回选区纯文本。
  Future<String?> selectionTextOf(
    WidgetTester tester,
    List<InlineNode> inlines, {
    EmojiImageBuilderForTest? emojiBuilder,
  }) async {
    SelectedContent? captured;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SelectionArea(
            onSelectionChanged: (c) => captured = c,
            child: InlineSpanText(
              inlines: inlines,
              baseStyle: const TextStyle(fontSize: 14),
              flattener: flattener,
              // emoji builder 故意返回纯 Image(无 Text),模拟真实主项目
              // 注入——验证 SelectableAdapter 是 emoji 选区文本的唯一来源。
              emojiImageBuilder: (context, emoji, size) =>
                  SizedBox(width: size, height: size),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final state =
        tester.state<SelectableRegionState>(find.byType(SelectableRegion));
    state.selectAll(SelectionChangedCause.keyboard);
    await tester.pumpAndSettle();
    return captured?.plainText;
  }

  testWidgets('纯文本选区原样输出', (tester) async {
    final r = await selectionTextOf(tester, const [TextRun('你好世界')]);
    expect(r, '你好世界');
  });

  testWidgets('emoji 贡献 :name:(对齐 cooked img.title)', (tester) async {
    final r = await selectionTextOf(tester, const [
      TextRun('心情'),
      EmojiRun(name: 'heart', url: 'https://x/heart.png'),
      TextRun('好'),
    ]);
    expect(r, '心情:heart:好');
  });

  testWidgets('emoji name 为空时不贡献文本', (tester) async {
    final r = await selectionTextOf(tester, const [
      TextRun('AB'),
      EmojiRun(name: '', url: 'https://x/u.png'),
      TextRun('CD'),
    ]);
    expect(r, 'ABCD');
  });

  testWidgets('click-count 被排除出选区', (tester) async {
    final r = await selectionTextOf(tester, const [
      TextRun('链接'),
      ClickCountRun('123'),
      TextRun('结束'),
    ]);
    expect(r, '链接结束');
    expect(r, isNot(contains('123')));
  });

  testWidgets('mention 贡献 @username', (tester) async {
    final r = await selectionTextOf(tester, const [
      TextRun('感谢 '),
      MentionRun(username: 'alice', href: '/u/alice'),
      TextRun(' 的帮助'),
    ]);
    expect(r, '感谢 @alice 的帮助');
  });

  testWidgets('mention 含状态 emoji 时状态 emoji 不污染选区', (tester) async {
    // 状态 emoji 是 preprocess 注入的,原始 cooked 的 mention 文本只有
    // @username,所以选区不应带上状态 emoji。
    final r = await selectionTextOf(tester, const [
      MentionRun(
        username: 'bob',
        href: '/u/bob',
        statusEmoji: EmojiRun(name: 'wave', url: 'https://x/wave.png'),
      ),
    ]);
    expect(r, '@bob');
  });

  testWidgets('链接 + 行内代码混合选区', (tester) async {
    final r = await selectionTextOf(tester, const [
      LinkRun(href: 'https://x', children: [TextRun('点我')]),
      TextRun(' 用 '),
      InlineCodeRun('flutter run'),
    ]);
    expect(r, '点我 用 flutter run');
  });

  testWidgets('em / strong 样式不影响选区文本', (tester) async {
    final r = await selectionTextOf(tester, const [
      StrongRun(children: [TextRun('粗')]),
      EmRun(children: [TextRun('斜')]),
      TextRun('正常'),
    ]);
    expect(r, '粗斜正常');
  });

  testWidgets('混合段落选区与 cooked 文本投影一致', (tester) async {
    // 模拟真实 cooked:`感谢 @alice ❤ 看 flutter run`
    // 选区应得到可被 HtmlTextMapper 在 cooked 里命中的纯文本。
    final r = await selectionTextOf(tester, const [
      TextRun('感谢 '),
      MentionRun(username: 'alice', href: '/u/alice'),
      TextRun(' '),
      EmojiRun(name: 'heart', url: 'https://x/h.png'),
      TextRun(' 看 '),
      InlineCodeRun('flutter run'),
    ]);
    expect(r, '感谢 @alice :heart: 看 flutter run');
  });
}

typedef EmojiImageBuilderForTest = Widget Function(
  BuildContext context,
  EmojiRun emoji,
  double size,
);
