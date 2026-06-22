import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo_render/fluxdo_render.dart';

void main() {
  testWidgets('FluxdoRender placeholder renders cookedHtml length', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: FluxdoRender(cookedHtml: '<p>hello</p>'),
      ),
    );

    expect(find.textContaining('FluxdoRender placeholder'), findsOneWidget);
    expect(find.textContaining('12 chars'), findsOneWidget);
  });
}
