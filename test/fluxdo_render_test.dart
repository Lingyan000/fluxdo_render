import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo_render/fluxdo_render.dart';

void main() {
  Future<void> pump(WidgetTester tester, String html) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FluxdoRender(cookedHtml: html),
        ),
      ),
    );
  }

  group('FluxdoRender 集成', () {
    testWidgets('简单段落渲染', (tester) async {
      await pump(tester, '<p>hello</p>');
      expect(find.text('hello'), findsOneWidget);
    });

    testWidgets('含 em / strong 的段落用 RichText', (tester) async {
      await pump(tester, '<p>a <em>b</em> <strong>c</strong></p>');
      // 整段被合并到 Text.rich,visible 文本是拼接结果
      expect(find.text('a b c'), findsOneWidget);
    });

    testWidgets('多个段落渲染多个 RichText', (tester) async {
      await pump(tester, '<p>p1</p><p>p2</p>');
      expect(find.text('p1'), findsOneWidget);
      expect(find.text('p2'), findsOneWidget);
    });

    testWidgets('空 HTML 渲染 SizedBox.shrink', (tester) async {
      await pump(tester, '');
      // 没有 Text widget 出现
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('cookedHtml 变化时重 parse', (tester) async {
      await pump(tester, '<p>before</p>');
      expect(find.text('before'), findsOneWidget);

      await pump(tester, '<p>after</p>');
      expect(find.text('after'), findsOneWidget);
      expect(find.text('before'), findsNothing);
    });
  });
}
