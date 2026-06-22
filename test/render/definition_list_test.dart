/// 验证 DefinitionListNode 渲染:dt 文本可见(常规字重)+ dd 左缩进 40。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo_render/src/node/node.dart';
import 'package:fluxdo_render/src/render/node_factory.dart';

void main() {
  Future<void> pump(WidgetTester tester, DefinitionListNode node) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => NodeFactory().buildDefinitionList(ctx, node),
          ),
        ),
      ),
    );
  }

  testWidgets('dt + dd 文本均渲染', (tester) async {
    await pump(
      tester,
      const DefinitionListNode(
        id: 'dl',
        items: [
          DefinitionItem(
            term: [TextRun('术语')],
            definitions: [
              [
                ParagraphNode(id: 'p1', inlines: [TextRun('释义内容')]),
              ],
            ],
          ),
        ],
      ),
    );
    expect(find.text('术语'), findsOneWidget);
    expect(find.text('释义内容'), findsOneWidget);
  });

  testWidgets('dd 左缩进 40(存在 left padding>=40 的 Padding)', (tester) async {
    await pump(
      tester,
      const DefinitionListNode(
        id: 'dl',
        items: [
          DefinitionItem(
            term: [TextRun('T')],
            definitions: [
              [
                ParagraphNode(id: 'p1', inlines: [TextRun('D')]),
              ],
            ],
          ),
        ],
      ),
    );
    // 至少有一个 Padding 的 left == 40(dd 缩进)。
    final paddings = tester.widgetList<Padding>(find.byType(Padding));
    final hasIndent = paddings.any((p) {
      final pad = p.padding;
      return pad is EdgeInsets && pad.left == 40.0;
    });
    expect(hasIndent, isTrue, reason: 'dd 应有 left:40 缩进对齐浏览器默认');
  });
}
