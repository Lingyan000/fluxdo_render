/// 阅读端 hashtag 药丸的整链路回归(cooked → 解析 → flatten → 渲染)。
library;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo_render/fluxdo_render.dart';

const _cooked =
    '<p>看看 <a class="hashtag-cooked" href="/c/dev/4" data-type="category" '
    'data-slug="dev" data-ref="dev"><svg class="fa d-icon d-icon-folder svg-icon">'
    '<use href="#folder"></use></svg><span>开发调优</span></a> 板块</p>';

void main() {
  testWidgets('选区开启时也不会把整段涂成一大块', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 600,
          height: 400,
          child: FluxdoRender(cookedHtml: _cooked),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.folder_outlined), findsOneWidget);
    expect(find.text('开发调优'), findsOneWidget);
    final pill = find.byType(Container).evaluate().isEmpty
        ? null
        : tester.getSize(find.byType(Container).first);
    if (pill != null) {
      expect(pill.height, lessThan(60));
      expect(pill.width, lessThan(240));
    }
  });

  testWidgets('正文标签显示图标和名称，点击保留标签引用和名称里的井号', (tester) async {
    const href = '/tag/c-sharp';
    const ref = 'c-sharp::tag';
    final taps = <(String, String?, String)>[];
    final original = hashtagTapHandler;
    addTearDown(() => hashtagTapHandler = original);
    hashtagTapHandler = (_, href, ref, label) {
      taps.add((href, ref, label));
      return true;
    };
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: FluxdoRender(
          cookedHtml: '<p><a class="hashtag-cooked" href="$href" '
              'data-type="tag" data-ref="$ref"><span>#C#</span></a></p>',
        ),
      ),
    ));

    expect(find.byIcon(Icons.sell_outlined), findsOneWidget);
    await tester.tap(find.text('C#'));
    expect(taps, [(href, ref, 'C#')]);
  });

  testWidgets('连续换行的分类和标签由正文分行，底色内边距可点击', (tester) async {
    const cooked = '<p><a class="hashtag-cooked" href="/c/welfare/1" '
        'data-slug="welfare">福利羊毛</a> x<br>'
        '<a class="hashtag-cooked" href="/c/offtopic/2" '
        'data-slug="offtopic">搞七捻三</a> ✓<br>'
        '<a class="hashtag-cooked" href="/tag/42-tag" '
        'data-ref="开源推广::tag"><span>#开源推广</span></a></p>';
    final opened = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: FluxdoRender(
          cookedHtml: cooked,
          baseTextStyle: const TextStyle(fontSize: 16, height: 1.5),
          linkHandler: (_, href) => opened.add(href),
        ),
      ),
    ));

    final targets = find.byType(ContentTapTarget);
    const labels = ['福利羊毛', '搞七捻三', '开源推广'];
    expect(targets, findsNWidgets(labels.length));
    final backgrounds = find.descendant(
      of: targets,
      matching: find.byType(DecoratedBox),
    );
    expect(backgrounds, findsNWidgets(labels.length));
    Rect? previousBackground;
    for (var i = 0; i < labels.length; i++) {
      final target = tester.getRect(targets.at(i));
      final background = tester.getRect(backgrounds.at(i));
      final label = tester.getRect(find.text(labels[i]));
      const padding = 16 * 0.93 * 0.2;
      expect(target, background);
      expect(label.top - background.top, closeTo(padding, 0.01));
      expect(background.bottom - label.bottom, closeTo(padding, 0.01));
      if (previousBackground != null) {
        expect(background.top, greaterThan(previousBackground.bottom));
      }
      previousBackground = background;
    }

    const edgeInset = Offset(0, 0.5);
    await tester.tapAt(tester.getRect(targets.first).bottomCenter - edgeInset);
    await tester.tapAt(tester.getRect(targets.at(1)).topCenter + edgeInset);
    await tester.tapAt(tester.getRect(targets.last).topCenter + edgeInset);
    expect(opened, ['/c/welfare/1', '/c/offtopic/2', '/tag/42-tag']);
  });

  testWidgets('只有标签时按段落行高自动折行，放大字号时按比例缩放', (tester) async {
    const cooked = '<p><a class="hashtag-cooked" href="/tag/1-tag" '
        'data-slug="first">开源推广</a><a class="hashtag-cooked" '
        'href="/tag/2-tag" data-slug="second">开发工具</a></p>';
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    Future<({double gap, Size size})> layoutAt(
      double lineHeight, {
      double textScale = 1,
    }) async {
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 110 * textScale,
                child: FluxdoRender(
                  cookedHtml: cooked,
                  baseTextStyle: TextStyle(fontSize: 16, height: lineHeight),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final tags = find.byType(ContentTapTarget);
      final first = tester.getRect(tags.first);
      final second = tester.getRect(tags.last);
      return (gap: second.top - first.bottom, size: first.size);
    }

    final normal = await layoutAt(1.5);
    final loose = await layoutAt(2);
    expect(normal.gap, greaterThan(0));
    expect(loose.size, normal.size);
    expect(loose.gap, greaterThan(normal.gap));

    final enlarged = await layoutAt(1.5, textScale: 2);
    expect(enlarged.size.width, closeTo(normal.size.width * 2, 0.01));
    expect(enlarged.size.height, closeTo(normal.size.height * 2, 0.01));
    expect(enlarged.gap, greaterThan(0));
  });
}
