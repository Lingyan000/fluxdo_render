import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fluxdo_render/fluxdo_render.dart';
import 'package:fluxdo_render/src/render/cached_paragraph_text.dart';
import 'package:fluxdo_render/src/selection/block_text_geometry.dart';

import '../test_text_finders.dart';

const _examples = <String, String>{
  '链接': '<p><strong><a href="/target">link</a></strong></p>',
  '附件图标': '<p><a class="attachment" href="/uploads/file.zip">file.zip</a></p>',
  '附件文字': '<p><a class="attachment" href="/uploads/file.zip">file.zip</a></p>',
  '脚注':
      '<p>正文<sup class="footnote-ref"><a href="#fn:1">1</a></sup></p>'
      '<section class="footnotes"><ol class="footnotes-list">'
      '<li id="fn:1"><p>脚注内容</p></li></ol></section>',
  '日期':
      '<p>会议 <span class="discourse-local-date" data-date="2026-12-01" '
      'data-time="14:30" data-timezone="Asia/Shanghai">服务端时间</span></p>',
  '行内公式': r'<p>公式 <span class="math">\frac{1}{2}</span></p>',
  '表情': '<p>表情 <img class="emoji" alt=":heart:" src=""></p>',
  '分类':
      '<p><a class="hashtag-cooked" href="/c/tech/4" '
      'data-ref="tech::category">技术</a></p>',
  '图片':
      '<p>图片 <img src="https://example.com/image.png" '
      'width="24" height="24"></p>',
  '提及': '<p><a class="mention" href="/u/alice">@alice</a></p>',
};

Offset _textPoint(WidgetTester tester, String text, {int index = 0}) {
  final render = tester.renderObject(
    findRenderedTextContaining(text).at(index),
  );
  final geometry = render is RenderCachedParagraph
      ? render
      : ParagraphGeometry(render as RenderParagraph);
  final offset = geometry.plainText.indexOf(text);
  return geometry.renderBox.localToGlobal(
    geometry
        .getBoxesForSelection(
          TextSelection(baseOffset: offset, extentOffset: offset + 1),
        )
        .first
        .toRect()
        .center,
  );
}

Widget _host(List<BlockNode> nodes, List<String> calls, String owner) =>
    MaterialApp(
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(40),
          child: FluxdoRender(
            cookedHtml: '',
            parsedNodes: nodes,
            linkHandler: (_, href) => calls.add('$owner:link:$href'),
            onDownloadAttachment: (_, href, filename) =>
                calls.add('$owner:download:$filename'),
            footnoteTapHandler: (_, id, html) =>
                calls.add('$owner:footnote:$id'),
            mentionTapHandler: (_, username, href) =>
                calls.add('$owner:mention:$username'),
            localDateBuilder: (_, node) => TextButton(
              key: ValueKey('$owner:date'),
              onPressed: () => calls.add('$owner:date'),
              child: const Text('本地时区时间'),
            ),
            mathInlineBuilder: (_, node) =>
                SizedBox.square(key: ValueKey('$owner:math'), dimension: 24),
            emojiImageBuilder: (_, node, size) =>
                SizedBox.square(key: ValueKey('$owner:emoji'), dimension: size),
            imageContentBuilder: (_, node, total) => SizedBox.square(
              key: ValueKey('$owner:image:$total'),
              dimension: 24,
            ),
          ),
        ),
      ),
    );

Future<void> _prewarm(
  WidgetTester tester,
  List<BlockNode> nodes, {
  required bool canLayout,
}) async {
  await tester.pumpWidget(
    _host(
      const [
        ParagraphNode(id: 'probe', inlines: [TextRun('纯文字探针')]),
      ],
      [],
      'probe',
    ),
  );
  final cachedBefore = FlattenCache.length;
  final layoutsBefore = ParagraphLayoutCache.length;
  final warmedBefore = ParagraphWarmup.warmedParagraphs;
  final next = ParagraphWarmup.warmParagraphs(
    nodes: nodes,
    ctx: ParagraphWarmupProbe.snapshot()!,
    context: tester.element(find.byType(InlineSpanText)),
    totalImagesInPost: 0,
    budgetMicros: 1 << 30,
  );
  expect(next, -1, reason: '预热游标必须完成，避免反复预热');
  expect(FlattenCache.length, cachedBefore, reason: '默认回调和内嵌组件不能进入全局缓存');
  expect(ParagraphLayoutCache.length, layoutsBefore + (canLayout ? 1 : 0));
  expect(ParagraphWarmup.warmedParagraphs, warmedBefore + (canLayout ? 1 : 0));
}

Future<void> _verify(
  WidgetTester tester,
  String example,
  List<String> calls,
) async {
  switch (example) {
    case '链接':
      await tester.tapAt(_textPoint(tester, 'link'));
      expect(calls, ['new:link:/target']);
    case '附件图标':
      await tester.tap(find.byIcon(Icons.save_alt));
      expect(calls, ['new:download:file.zip']);
    case '附件文字':
      await tester.tapAt(_textPoint(tester, 'file.zip'));
      expect(calls, ['new:download:file.zip']);
    case '脚注':
      await tester.tap(find.text('[1]'));
      expect(calls, ['new:footnote:fn:1']);
    case '提及':
      await tester.tapAt(_textPoint(tester, '@alice'));
      expect(calls, ['new:mention:alice']);
    case '日期':
      expect(find.text('服务端时间'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('new:date')));
      expect(calls, ['new:date']);
    case '行内公式':
      expect(find.byKey(const ValueKey('new:math')), findsOneWidget);
      expect(find.text(r'$\frac{1}{2}$'), findsNothing);
    case '表情':
      expect(find.byKey(const ValueKey('new:emoji')), findsOneWidget);
      expect(find.text(':heart:'), findsNothing);
    case '分类':
      await tester.tap(find.text('技术'));
      expect(calls, ['new:link:/c/tech/4']);
    case '图片':
      expect(find.byKey(const ValueKey('new:image:1')), findsOneWidget);
  }
}

void main() {
  setUp(() {
    FlattenCache.evictAll();
    ParagraphLayoutCache.evictAll();
    ParagraphWarmupProbe.reset();
    final previousTap = hashtagTapHandler;
    final previousResolver = hashtagIconResolver;
    hashtagTapHandler = null;
    hashtagIconResolver = null;
    addTearDown(() {
      hashtagTapHandler = previousTap;
      hashtagIconResolver = previousResolver;
    });
  });

  for (final entry in _examples.entries) {
    for (final lifecycle in ['预热', '更新回调', '回收再显示']) {
      testWidgets('${entry.key}在$lifecycle后使用当前宿主', (tester) async {
        final nodes = ParagraphParser().parse(entry.value);
        final calls = <String>[];
        if (lifecycle == '预热') {
          await _prewarm(
            tester,
            nodes,
            canLayout: ['链接', '附件图标', '附件文字', '表情'].contains(entry.key),
          );
        } else {
          await tester.pumpWidget(_host(nodes, calls, 'old'));
          if (lifecycle == '回收再显示') {
            await tester.pumpWidget(const SizedBox.shrink());
          }
        }
        final cachedBefore = FlattenCache.length;
        final layoutMissesBefore = ParagraphLayoutCache.misses;
        await tester.pumpWidget(_host(nodes, calls, 'new'));
        await _verify(tester, entry.key, calls);
        expect(FlattenCache.length, cachedBefore);
        expect(
          ParagraphLayoutCache.misses,
          layoutMissesBefore,
          reason: '只复用预热或前次挂载的排版，交互始终来自当前宿主',
        );
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  testWidgets('同一正文的多处显示分别使用自己的回调和导航上下文', (tester) async {
    final nodes = ParagraphParser().parse(_examples['链接']!);
    final calls = <(String, String)>[];
    Widget pane(String owner) => SizedBox(
      key: ValueKey(owner),
      width: 300,
      child: FluxdoRender(
        cookedHtml: '',
        parsedNodes: nodes,
        linkHandler: (context, _) {
          var contextOwner = '';
          context.visitAncestorElements((element) {
            if (element.widget is SizedBox &&
                element.widget.key is ValueKey<String>) {
              contextOwner = (element.widget.key! as ValueKey<String>).value;
              return false;
            }
            return true;
          });
          calls.add((owner, contextOwner));
        },
      ),
    );
    final misses = ParagraphLayoutCache.misses;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Row(children: [pane('left'), pane('right')])),
      ),
    );
    expect(ParagraphLayoutCache.misses, misses + 1, reason: '两个区域只排版一次');
    final results = tester
        .widgetList<CachedParagraphText>(find.byType(CachedParagraphText))
        .map((widget) => widget.result)
        .toList();
    expect(results, hasLength(2));
    expect(results[0], isNot(same(results[1])));
    expect(
      results[0].recognizers.single,
      isNot(same(results[1].recognizers.single)),
    );
    expect(results[0].layoutData, results[1].layoutData);
    for (final kind in [PointerDeviceKind.mouse, PointerDeviceKind.touch]) {
      await tester.tapAt(_textPoint(tester, 'link'), kind: kind);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tapAt(_textPoint(tester, 'link', index: 1), kind: kind);
      await tester.pump(const Duration(milliseconds: 400));
    }
    expect(calls, [
      ('left', 'left'),
      ('right', 'right'),
      ('left', 'left'),
      ('right', 'right'),
    ]);
  }, variant: TargetPlatformVariant.all());

  testWidgets('回调未变的普通重建不打断正在进行的链接点击', (tester) async {
    final nodes = ParagraphParser().parse(_examples['链接']!);
    final calls = <String>[];
    void handler(BuildContext context, String href) => calls.add(href);
    Widget host() => MaterialApp(
      home: Scaffold(
        body: FluxdoRender(
          cookedHtml: '',
          parsedNodes: nodes,
          linkHandler: handler,
        ),
      ),
    );
    await tester.pumpWidget(host());
    final gesture = await tester.startGesture(_textPoint(tester, 'link'));
    final misses = FlattenCache.misses;
    await tester.pumpWidget(host());
    expect(FlattenCache.misses, misses);
    await gesture.up();
    expect(calls, ['/target']);
  });

  testWidgets('按下后更新回调和组件 builder，松开仍触发当前链接且不重排', (tester) async {
    final nodes = ParagraphParser().parse(
      '<p><a href="/target">link<img class="emoji" alt=":heart:" src=""></a></p>',
    );
    final calls = <String>[];
    await tester.pumpWidget(_host(nodes, calls, 'old'));
    final oldResult = tester
        .widget<CachedParagraphText>(find.byType(CachedParagraphText))
        .result;
    final gesture = await tester.startGesture(_textPoint(tester, 'link'));
    final flattenMisses = FlattenCache.misses;
    final layoutMisses = ParagraphLayoutCache.misses;
    await tester.pumpWidget(_host(nodes, calls, 'new'));
    expect(
      tester
          .widget<CachedParagraphText>(find.byType(CachedParagraphText))
          .result,
      same(oldResult),
    );
    expect(find.byKey(const ValueKey('new:emoji')), findsOneWidget);
    expect(find.byKey(const ValueKey('old:emoji')), findsNothing);
    expect(FlattenCache.misses, flattenMisses);
    expect(ParagraphLayoutCache.misses, layoutMisses);
    await gesture.up();
    expect(calls, ['new:link:/target']);
    await tester.tapAt(
      tester.getCenter(find.byKey(const ValueKey('new:emoji'))),
    );
    expect(calls, ['new:link:/target', 'new:link:/target']);
  });

  testWidgets('附件下载回调移除后立即降级到当前链接回调', (tester) async {
    final nodes = ParagraphParser().parse(_examples['附件文字']!);
    final calls = <String>[];
    Widget host(bool download) => MaterialApp(
      home: Scaffold(
        body: FluxdoRender(
          cookedHtml: '',
          parsedNodes: nodes,
          linkHandler: (_, href) => calls.add('link'),
          onDownloadAttachment: download
              ? (_, href, name) => calls.add('download')
              : null,
        ),
      ),
    );
    await tester.pumpWidget(host(true));
    await tester.tapAt(_textPoint(tester, 'file.zip'));
    final misses = ParagraphLayoutCache.misses;
    await tester.pumpWidget(host(false));
    await tester.tapAt(_textPoint(tester, 'file.zip'));
    await tester.tap(find.byIcon(Icons.save_alt));
    expect(calls, ['download', 'link', 'link']);
    expect(ParagraphLayoutCache.misses, misses);
  });

  testWidgets('共享布局被逐出且一个区域卸载后，另一区域仍可绘制和点击', (tester) async {
    final nodes = ParagraphParser().parse(_examples['链接']!);
    final calls = <String>[];
    Widget pane(String owner) => SizedBox(
      key: ValueKey(owner),
      width: 300,
      child: FluxdoRender(
        cookedHtml: '',
        parsedNodes: nodes,
        linkHandler: (_, href) => calls.add(owner),
      ),
    );
    Widget host(bool left) => MaterialApp(
      home: Scaffold(
        body: Row(children: [if (left) pane('left'), pane('right')]),
      ),
    );
    await tester.pumpWidget(host(true));
    final render = tester.renderObject<RenderCachedParagraph>(
      find.byType(CachedParagraphText).last,
    );
    final entry = ParagraphLayoutCache.obtain(
      render.result.layoutData!,
      render.env,
      render.constraints.minWidth,
      render.constraints.maxWidth,
    );
    FlattenCache.evictAll();
    ParagraphLayoutCache.evictAll();
    expect(entry.isDisposed, isFalse);
    await tester.pumpWidget(host(false));
    render.markNeedsPaint();
    await tester.pump();
    expect(entry.isDisposed, isFalse);
    await tester.tapAt(_textPoint(tester, 'link'));
    expect(calls, ['right']);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(entry.isDisposed, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('纯文字及嵌套样式跨挂载仍复用排版', (tester) async {
    final nodes = ParagraphParser().parse(
      '<p>正文 <strong>加粗 <em>斜体</em></strong> 尾部</p>',
    );
    await tester.pumpWidget(_host(nodes, [], 'first'));
    final result = tester
        .widget<CachedParagraphText>(find.byType(CachedParagraphText))
        .result;
    final flattenMisses = FlattenCache.misses;
    final layoutMisses = ParagraphLayoutCache.misses;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(_host(nodes, [], 'second'));
    expect(
      tester
          .widget<CachedParagraphText>(find.byType(CachedParagraphText))
          .result,
      same(result),
    );
    expect(FlattenCache.misses, flattenMisses);
    expect(ParagraphLayoutCache.misses, layoutMisses);
  });
}
