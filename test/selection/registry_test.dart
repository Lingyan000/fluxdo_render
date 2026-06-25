import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo_render/src/node/inline_node.dart';
import 'package:fluxdo_render/src/render/inline_span_text.dart';
import 'package:fluxdo_render/src/selection/selection_registry.dart';
import 'package:fluxdo_render/src/selection/selection_scope.dart';

void main() {
  Widget wrap(SelectionController controller, List<Widget> children) {
    return MaterialApp(
      home: Scaffold(
        body: SelectionScope(
          controller: controller,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ),
    );
  }

  InlineSpanText para(String text) => InlineSpanText(
        inlines: [TextRun(text)],
        baseStyle: const TextStyle(fontSize: 14),
      );

  testWidgets('N 个段落 → registry 注册 N 个块', (tester) async {
    final controller = SelectionController(SelectionRegistry());
    await tester.pumpWidget(wrap(controller, [
      para('第一段'),
      para('第二段'),
      para('第三段'),
    ]));
    await tester.pumpAndSettle();
    expect(controller.registry.length, 3);
  });

  testWidgets('visualOrder 按几何 y 升序', (tester) async {
    final controller = SelectionController(SelectionRegistry());
    await tester.pumpWidget(wrap(controller, [
      para('上'),
      para('中'),
      para('下'),
    ]));
    await tester.pumpAndSettle();
    final order = controller.registry.visualOrder();
    expect(order.length, 3);
    // 全局 y 递增
    final ys = [for (final h in order) h.globalRect()!.top];
    for (var i = 1; i < ys.length; i++) {
      expect(ys[i] >= ys[i - 1], isTrue, reason: 'visualOrder 应按 y 升序');
    }
  });

  testWidgets('dispose 段落 → registry 注销', (tester) async {
    final controller = SelectionController(SelectionRegistry());
    await tester.pumpWidget(wrap(controller, [para('A'), para('B')]));
    await tester.pumpAndSettle();
    expect(controller.registry.length, 2);

    // 移除一个段落
    await tester.pumpWidget(wrap(controller, [para('A')]));
    await tester.pumpAndSettle();
    expect(controller.registry.length, 1);
  });

  testWidgets('handle.projection 反映段落内容', (tester) async {
    final controller = SelectionController(SelectionRegistry());
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SelectionScope(
            controller: controller,
            child: InlineSpanText(
              inlines: const [
                TextRun('心情'),
                EmojiRun(name: 'heart', url: 'x'),
              ],
              baseStyle: const TextStyle(fontSize: 14),
              emojiImageBuilder: (ctx, emoji, size) =>
                  SizedBox(width: size, height: size),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final h = controller.registry.all.first;
    expect(h.projection.projectAll(), '心情:heart:');
    // RenderParagraph 实时可取
    expect(h.paragraph, isNotNull);
    expect(h.projection.renderLength, h.paragraph!.text.toPlainText().length);
  });

  testWidgets('无 SelectionScope 时不崩(退化不可选)', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: para('无选区上下文')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('无选区上下文'), findsOneWidget);
  });
}
