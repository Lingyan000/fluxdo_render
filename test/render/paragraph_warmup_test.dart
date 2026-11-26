/// ParagraphWarmup 单测:预热产物与挂载路径 key 同源(缓存命中)。
library;

import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo_render/fluxdo_render.dart';

void main() {
  setUp(() {
    FlattenCache.evictAll();
    ParagraphLayoutCache.evictAll();
    ParagraphWarmupProbe.reset();
    GlyphPrebaker.resetStatsForTesting();
  });

  tearDown(GlyphPrebaker.resetStatsForTesting);

  testWidgets('预热后挂载:flatten 与排版均缓存命中', (tester) async {
    const nodes = <BlockNode>[
      ParagraphNode(id: 'b_0', inlines: [TextRun('warm me up before you go')]),
      ParagraphNode(id: 'b_1', inlines: [TextRun('second paragraph body')]),
    ];

    // 第一次挂载:登记探针(真实 theme/env/宽度)。
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: FluxdoRender(cookedHtml: '', parsedNodes: nodes),
      ),
    ));
    expect(ParagraphWarmupProbe.snapshot(), isNotNull,
        reason: '直绘块挂载后探针应已收敛');

    // 卸载(模拟 sliver 回收)+ 清缓存(模拟这些段落从未见过)。
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    FlattenCache.evictAll();
    ParagraphLayoutCache.evictAll();

    // 预热(探针快照 + 任意挂载 context)。
    final ctx = tester.element(find.byType(SizedBox));
    final snapshot = ParagraphWarmupProbe.snapshot()!;
    final next = ParagraphWarmup.warmParagraphs(
      nodes: nodes,
      ctx: snapshot,
      context: ctx,
      totalImagesInPost: 0,
      budgetMicros: 1 << 30,
    );
    expect(next, -1, reason: '预算充足应一次热完');

    final flattenMissesAfterWarm = FlattenCache.misses;
    final layoutMissesAfterWarm = ParagraphLayoutCache.misses;
    expect(FlattenCache.length, 2);
    expect(ParagraphLayoutCache.length, greaterThanOrEqualTo(2));

    // 重新挂载:两层缓存都应命中,miss 不再增长。
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: FluxdoRender(cookedHtml: '', parsedNodes: nodes),
      ),
    ));
    expect(FlattenCache.misses, flattenMissesAfterWarm,
        reason: '挂载 flatten 应全部命中预热产物');
    expect(ParagraphLayoutCache.misses, layoutMissesAfterWarm,
        reason: '挂载排版应全部命中预热产物');
  });

  testWidgets('探针未收敛时 snapshot 为 null', (tester) async {
    expect(ParagraphWarmupProbe.snapshot(), isNull);
  });

  testWidgets('局部 Theme 挤出根主题缓存时，等值主题不导致文字缓存失效；真实换色时正常更新',
      (tester) async {
    final nodes = <BlockNode>[
      for (var i = 0; i < 24; i++)
        ParagraphNode(
          id: 'p_$i',
          inlines: [
            TextRun('第 $i 段正文内容 '),
            LinkRun(href: 'https://example.com/$i', children: [
              TextRun('链接$i'),
            ]),
          ],
        ),
    ];

    var tick = 0;
    var showLocalThemes = false;
    var seedColor = Colors.blue;
    late StateSetter setHostState;

    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          setHostState = setState;
          final baseTheme = ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: seedColor),
          );
          return MaterialApp(
            theme: baseTheme,
            themeAnimationDuration: Duration.zero,
            home: Scaffold(
              body: SingleChildScrollView(
                child: Column(
                  children: [
                    Text('tick=$tick'),
                    FluxdoRender(cookedHtml: '', parsedNodes: nodes),
                    if (showLocalThemes)
                      for (var i = 0; i < 24; i++)
                        Builder(
                          builder: (ctx) => Theme(
                            // 构造多个全新 ThemeData 挤出 Flutter 全局本地化主题缓存
                            data: Theme.of(ctx).copyWith(
                              splashColor: Color.fromARGB(255, i, i, i),
                            ),
                            child: Builder(
                              builder: (innerCtx) {
                                Theme.of(innerCtx);
                                return const SizedBox.shrink();
                              },
                            ),
                          ),
                        ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );

    final flattenMissesBefore = FlattenCache.misses;
    final layoutMissesBefore = ParagraphLayoutCache.misses;

    // 挂载一批局部 Theme 挤出根主题缓存，再触发正文宿主 rebuild
    setHostState(() {
      showLocalThemes = true;
      tick++;
    });
    await tester.pump();
    setHostState(() {
      tick++;
    });
    await tester.pump();

    expect(FlattenCache.misses, flattenMissesBefore,
        reason: '主题值未变时不应因 Theme.of 返回新对象而击穿 FlattenCache');
    expect(ParagraphLayoutCache.misses, layoutMissesBefore,
        reason: '主题值未变时不应触发段落重排');

    // 真实切换主题配色后，FlattenCache 必须失效并按新色重压平
    setHostState(() {
      showLocalThemes = false;
      seedColor = Colors.red;
      tick++;
    });
    await tester.pump();

    expect(FlattenCache.misses, greaterThan(flattenMissesBefore),
        reason: '真实切换主题主色后必须失效并重新压平');
  });

  testWidgets('宽度从 280 变为 360 后，段落预热立即使用新宽度且挂载命中', (tester) async {
    final initialNodes = <BlockNode>[
      for (var i = 0; i < 24; i++)
        ParagraphNode(
          id: 'w_$i',
          inlines: [TextRun('初始宽度测试段落 $i 用于占据大量历史样本')],
        ),
    ];
    final nextNodes = <BlockNode>[
      for (var i = 0; i < 4; i++)
        ParagraphNode(
          id: 'n_$i',
          inlines: [TextRun('新宽度待预热段落 $i 应该被精准命中')],
        ),
    ];

    // 先在 280 宽下挂载 24 段
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 280,
          child: SingleChildScrollView(
            child: FluxdoRender(cookedHtml: '', parsedNodes: initialNodes),
          ),
        ),
      ),
    ));
    expect(ParagraphWarmupProbe.snapshot()!.maxWidth, closeTo(280, 0.5));

    // 切到 360 宽且只挂载 4 段
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 360,
          child: FluxdoRender(
            cookedHtml: '',
            parsedNodes: initialNodes.take(4).toList(),
          ),
        ),
      ),
    ));

    final snapshot = ParagraphWarmupProbe.snapshot()!;
    expect(snapshot.maxWidth, closeTo(360, 0.5),
        reason: '活跃实例更新为 360 后不应继续沿用旧宽度 280');

    final ctx = tester.element(find.byType(Scaffold));
    final next = ParagraphWarmup.warmParagraphs(
      nodes: nextNodes,
      ctx: snapshot,
      context: ctx,
      totalImagesInPost: 0,
      budgetMicros: 1 << 30,
    );
    expect(next, -1);

    final layoutMissesAfterWarm = ParagraphLayoutCache.misses;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 360,
          child: FluxdoRender(cookedHtml: '', parsedNodes: nextNodes),
        ),
      ),
    ));
    expect(ParagraphLayoutCache.misses, layoutMissesAfterWarm,
        reason: '360 宽预热的 4 段文字在 360 宽挂载时应全部命中');
  });

  testWidgets('ParagraphWarmupScope 隔离不同页面宽度，互不污染', (tester) async {
    final trackerA = ParagraphWarmupTracker();
    final trackerB = ParagraphWarmupTracker();
    final nodesA = <BlockNode>[
      for (var i = 0; i < 12; i++)
        ParagraphNode(id: 'a_$i', inlines: [TextRun('页面 A 段落 $i')]),
    ];
    final nodesB = <BlockNode>[
      for (var i = 0; i < 2; i++)
        ParagraphNode(id: 'b_$i', inlines: [TextRun('页面 B 段落 $i')]),
    ];

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Row(
          children: [
            ParagraphWarmupScope(
              tracker: trackerA,
              child: SizedBox(
                width: 240,
                child: SingleChildScrollView(
                  child: FluxdoRender(cookedHtml: '', parsedNodes: nodesA),
                ),
              ),
            ),
            ParagraphWarmupScope(
              tracker: trackerB,
              child: SizedBox(
                width: 380,
                child: SingleChildScrollView(
                  child: FluxdoRender(cookedHtml: '', parsedNodes: nodesB),
                ),
              ),
            ),
          ],
        ),
      ),
    ));

    expect(trackerA.snapshot()!.maxWidth, closeTo(240, 0.5));
    expect(trackerB.snapshot()!.maxWidth, closeTo(380, 0.5));
  });

  testWidgets('GlyphPrebaker 按 DPR 缩放、串行背压、跳过已缓存段落且取消时安全释放引用',
      (tester) async {
    final nodes = <BlockNode>[
      for (var i = 0; i < 4; i++)
        ParagraphNode(id: 'g_$i', inlines: [TextRun('字形预烤测试段落 $i')]),
    ];

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 300,
          child: FluxdoRender(cookedHtml: '', parsedNodes: [nodes.first]),
        ),
      ),
    ));
    final snapshot = ParagraphWarmupProbe.snapshot()!;
    final ctx = tester.element(find.byType(Scaffold));

    final recordedBakes = <(int count, int w, int h, double dpr)>[];
    final completers = <Completer<void>>[];
    GlyphPrebaker.debugOnBake = (count, w, h, dpr) {
      recordedBakes.add((count, w, h, dpr));
    };
    GlyphPrebaker.debugImageRunner = (picture, w, h) {
      final c = Completer<void>();
      completers.add(c);
      return c.future;
    };

    final baker = GlyphPrebaker();

    // 预热 4 段：第 0 段已缓存应跳过预烤，仅新排版的 3 段进入离屏预烤，且按 3.0x DPR 缩放
    ParagraphWarmup.warmParagraphs(
      nodes: nodes,
      ctx: snapshot,
      context: ctx,
      totalImagesInPost: 0,
      glyphBaker: baker,
      devicePixelRatio: 3.0,
      budgetMicros: 1 << 30,
    );
    expect(recordedBakes.length, 1);
    expect(recordedBakes.first.$1, 3, reason: '已命中的段落不应重复预烤');
    expect(recordedBakes.first.$4, 3.0, reason: '应按传入的 3.0x DPR 缩放');
    expect(recordedBakes.first.$2, greaterThan(100),
        reason: '物理像素宽度应已按 3.0x DPR 放大');

    // 第一批尚未完成时再入队新段落：应排队背压，不并发发起第二张 toImage
    final moreNodes = <BlockNode>[
      ParagraphNode(id: 'g_extra_1', inlines: [TextRun('第二批待烤段落 A')]),
      ParagraphNode(id: 'g_extra_2', inlines: [TextRun('第二批待烤段落 B')]),
    ];
    ParagraphWarmup.warmParagraphs(
      nodes: moreNodes,
      ctx: snapshot,
      context: ctx,
      totalImagesInPost: 0,
      glyphBaker: baker,
      devicePixelRatio: 3.0,
      budgetMicros: 1 << 30,
    );
    expect(recordedBakes.length, 1, reason: '前一批在途时必须串行背压');
    expect(baker.pendingCount, 2);

    // 排队期间发生 LRU 清空，clear() 取消队列时必须安全释放持有引用且不崩
    ParagraphLayoutCache.evictAll();
    baker.clear();
    expect(baker.pendingCount, 0);

    // 放行第一批完成，不应再触发已取消的第二批
    completers.first.complete();
    await tester.pump();
    expect(recordedBakes.length, 1);

    baker.dispose();
  });
}
