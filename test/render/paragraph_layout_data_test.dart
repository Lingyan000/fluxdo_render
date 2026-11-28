import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo_render/src/flatten/paragraph_layout_data.dart';
import 'package:fluxdo_render/src/flatten/inline_flattener.dart';
import 'package:fluxdo_render/src/render/cached_paragraph_text.dart';
import 'package:fluxdo_render/src/selection/projection.dart';

const _rootStyle = TextStyle(fontSize: 16, color: Color(0xff123456));
const _env = ParagraphEnv(
  rootStyle: _rootStyle,
  textAlign: TextAlign.start,
  textDirection: TextDirection.ltr,
  textScaler: TextScaler.noScaling,
);
const _dimensions = [
  PlaceholderDimensions(
    size: Size(20, 16),
    alignment: ui.PlaceholderAlignment.middle,
  ),
];

TextSpan _span({
  TextStyle style = _rootStyle,
  GestureRecognizer? recognizer,
  Widget child = const SizedBox(),
}) => TextSpan(
  style: style,
  children: [
    const TextSpan(text: '段落 '),
    TextSpan(
      style: const TextStyle(
        fontWeight: FontWeight.bold,
        color: Color(0xff660000),
      ),
      children: [
        TextSpan(text: 'link', recognizer: recognizer),
        const TextSpan(
          style: TextStyle(fontStyle: FontStyle.italic, letterSpacing: 0.4),
          children: [TextSpan(text: ' 嵌套样式')],
        ),
      ],
    ),
    WidgetSpan(alignment: ui.PlaceholderAlignment.middle, child: child),
    const TextSpan(text: '\n第二行 hello world'),
  ],
);

Future<List<int>> _pixels(ui.Paragraph paragraph) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawParagraph(paragraph, Offset.zero);
  final picture = recorder.endRecording();
  final image = await picture.toImage(320, 180);
  final data = await image.toByteData();
  final bytes = data!.buffer.asUint8List().toList();
  image.dispose();
  picture.dispose();
  return bytes;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(ParagraphLayoutCache.evictAll);
  tearDown(ParagraphLayoutCache.evictAll);

  test('没有 text 的样式父节点带回调时也不能共享 flatten 产物', () {
    final span = TextSpan(
      onEnter: (_) {},
      children: const [TextSpan(text: '正文')],
    );
    final result = FlattenResult(
      span: span,
      recognizers: [],
      projection: RenderTextProjection.empty,
      mount: SpanMountContext(),
      islands: [],
    );
    expect(result.canShare, isFalse);
    expect(
      result.layoutData,
      ParagraphLayoutData.fromSpan(
        const TextSpan(children: [TextSpan(text: '正文')]),
        [],
      ),
    );
  });

  test('不同手势和组件共享相同布局，释放原手势不影响缓存', () {
    final firstRecognizer = TapGestureRecognizer()..onTap = () {};
    final secondRecognizer = TapGestureRecognizer()..onTap = () {};
    final first = ParagraphLayoutData.fromSpan(
      _span(recognizer: firstRecognizer),
      _dimensions,
    )!;
    final second = ParagraphLayoutData.fromSpan(
      _span(recognizer: secondRecognizer, child: const Text('独立组件')),
      _dimensions,
    )!;
    expect(first, second);
    expect(first.hashCode, second.hashCode);
    final entry = ParagraphLayoutCache.obtain(first, _env, 0, 280);
    firstRecognizer.dispose();
    secondRecognizer.dispose();
    expect(ParagraphLayoutCache.obtain(second, _env, 0, 280), same(entry));
    expect(
      ParagraphLayoutCache.intrinsics(first, _env),
      same(ParagraphLayoutCache.intrinsics(second, _env)),
    );
    expect(entry.paragraph.getBoxesForPlaceholders(), hasLength(1));
  });

  test('布局键区分文字、样式和占位尺寸', () {
    final data = ParagraphLayoutData.fromSpan(_span(), _dimensions)!;
    final entry = ParagraphLayoutCache.obtain(data, _env, 0, 280);
    for (final other in [
      ParagraphLayoutData.fromSpan(const TextSpan(text: '其他正文'), [])!,
      ParagraphLayoutData.fromSpan(
        _span(style: _rootStyle.copyWith(fontSize: 20)),
        _dimensions,
      )!,
      ParagraphLayoutData.fromSpan(
        _span(style: _rootStyle.copyWith(color: const Color(0xffaabbcc))),
        _dimensions,
      )!,
      ParagraphLayoutData.fromSpan(_span(), const [
        PlaceholderDimensions(
          size: Size(40, 30),
          alignment: ui.PlaceholderAlignment.middle,
        ),
      ])!,
    ]) {
      expect(other, isNot(data));
      expect(
        ParagraphLayoutCache.obtain(other, _env, 0, 280),
        isNot(same(entry)),
      );
    }
  });

  test('布局键区分环境、最小宽度及小于半像素的约束变化', () {
    final data = ParagraphLayoutData.fromSpan(
      const TextSpan(text: 'short'),
      [],
    )!;
    final entry = ParagraphLayoutCache.obtain(data, _env, 0, 280);
    final minimum = ParagraphLayoutCache.obtain(data, _env, 240, 280);
    expect(minimum.size.width, 240);
    expect(minimum, isNot(same(entry)));
    expect(
      ParagraphLayoutCache.obtain(data, _env, 0, 280.1),
      isNot(same(entry)),
    );
    expect(ParagraphLayoutCache.obtain(data, _env, 280, 280).size.width, 280);
    for (final environment in [
      ParagraphEnv(
        rootStyle: _rootStyle.copyWith(fontSize: 18),
        textAlign: TextAlign.start,
        textDirection: TextDirection.ltr,
        textScaler: TextScaler.noScaling,
      ),
      const ParagraphEnv(
        rootStyle: _rootStyle,
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
        textScaler: TextScaler.noScaling,
      ),
      const ParagraphEnv(
        rootStyle: _rootStyle,
        textAlign: TextAlign.start,
        textDirection: TextDirection.rtl,
        textScaler: TextScaler.noScaling,
      ),
      const ParagraphEnv(
        rootStyle: _rootStyle,
        textAlign: TextAlign.start,
        textDirection: TextDirection.ltr,
        textScaler: TextScaler.linear(1.5),
      ),
    ]) {
      expect(
        ParagraphLayoutCache.obtain(data, environment, 0, 280),
        isNot(same(entry)),
      );
    }
  });

  test('未知占位尺寸不能进入共享布局', () {
    expect(ParagraphLayoutData.fromSpan(_span(), [null]), isNull);
    expect(ParagraphLayoutData.fromSpan(_span(), []), isNull);
    expect(
      ParagraphLayoutData.fromSpan(const TextSpan(text: '文字'), _dimensions),
      isNull,
    );
  });

  for (final scale in [1.0, 1.5]) {
    for (final direction in TextDirection.values) {
      test('布局快照与原始 TextSpan 构建的像素和选区一致 scale=$scale $direction', () async {
        final recognizer = TapGestureRecognizer()..onTap = () {};
        addTearDown(recognizer.dispose);
        final span = _span(recognizer: recognizer);
        final scaler = TextScaler.linear(scale);
        final env = ParagraphEnv(
          rootStyle: _rootStyle,
          textAlign: TextAlign.start,
          textDirection: direction,
          textScaler: scaler,
        );
        final expectedBuilder = ui.ParagraphBuilder(
          _rootStyle.getParagraphStyle(
            textAlign: env.textAlign,
            textDirection: direction,
            textScaler: scaler,
          ),
        );
        TextSpan(style: _rootStyle, children: [span]).build(
          expectedBuilder,
          textScaler: scaler,
          dimensions: [
            PlaceholderDimensions(
              size: Size(20 * scale, 16 * scale),
              alignment: ui.PlaceholderAlignment.middle,
            ),
          ],
        );
        final expected = expectedBuilder.build()
          ..layout(const ui.ParagraphConstraints(width: 280));
        addTearDown(expected.dispose);
        final actual = ParagraphLayoutCache.obtain(
          ParagraphLayoutData.fromSpan(span, _dimensions)!,
          env,
          280,
          280,
        ).paragraph;
        expect(actual.height, expected.height);
        expect(actual.alphabeticBaseline, expected.alphabeticBaseline);
        expect(
          actual.getBoxesForPlaceholders(),
          expected.getBoxesForPlaceholders(),
        );
        final text = span.toPlainText();
        for (var i = 0; i < text.length; i++) {
          expect(
            actual.getBoxesForRange(i, i + 1),
            expected.getBoxesForRange(i, i + 1),
          );
        }
        expect(await _pixels(actual), await _pixels(expected));
      });
    }
  }
}
