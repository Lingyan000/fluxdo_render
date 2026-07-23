import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo_render/editor.dart' show FluxdoEditor;
import 'package:fluxdo_render/src/editor/input/input_rules.dart';
import 'package:fluxdo_render/src/editor/model/editable_text_content.dart';
import 'package:fluxdo_render/src/editor/model/editor_state.dart';
import 'package:fluxdo_render/src/editor/widget/editable_paragraph.dart';
import 'package:fluxdo_render/src/flatten/inline_flattener.dart';

void main() {
  test('format delimiters expand only around the active caret', () {
    final content = EditableTextContent(
      text: 'beforeboldafter',
      marks: const [MarkSpan(start: 6, end: 10, kind: MarkKind.strong)],
    );
    const flattener = InlineFlattener();

    final collapsed = flattener.flatten(
      content.toInlines(forEditing: true),
      const TextStyle(fontSize: 14),
    );
    expect(collapsed.span.toPlainText(), content.text);
    expect(collapsed.projection.projectAll(), content.text);
    expect(collapsed.projection.contentLength, content.length);

    final expanded = flattener.flatten(
      content.toInlines(forEditing: true, revealMarkdownAt: 8),
      const TextStyle(fontSize: 14),
    );
    expect(expanded.span.toPlainText(), 'before**bold**after');
    expect(expanded.projection.projectAll(), content.text);
    expect(expanded.projection.contentLength, content.length);
    expect(expanded.projection.renderOffsetForContent(6), 8);
    expect(expanded.projection.renderOffsetForContent(10), 14);
    expect(expanded.projection.contentOffsetForRender(7), 6);
    expect(expanded.projection.contentOffsetForRender(12), 10);

    final outside = flattener.flatten(
      content.toInlines(forEditing: true, revealMarkdownAt: 5),
      const TextStyle(fontSize: 14),
    );
    expect(outside.span.toPlainText(), content.text);
  });

  test('all editable mark kinds expose their source delimiters', () {
    final cases = <(MarkSpan, String)>[
      (const MarkSpan(start: 0, end: 1, kind: MarkKind.strong), '**x**'),
      (const MarkSpan(start: 0, end: 1, kind: MarkKind.em), '*x*'),
      (
        const MarkSpan(start: 0, end: 1, kind: MarkKind.inlineCode),
        '`\u00a0x\u00a0`',
      ),
      (const MarkSpan(start: 0, end: 1, kind: MarkKind.underline), '[u]x[/u]'),
      (const MarkSpan(start: 0, end: 1, kind: MarkKind.lineThrough), '~~x~~'),
      (
        const MarkSpan(start: 0, end: 1, kind: MarkKind.spoilerInline),
        '[spoiler]x[/spoiler]',
      ),
      (
        const MarkSpan(start: 0, end: 1, kind: MarkKind.link, attr: '/t/1'),
        '[x](/t/1)',
      ),
    ];
    const flattener = InlineFlattener();

    for (final (mark, rendered) in cases) {
      final content = EditableTextContent(text: 'x', marks: [mark]);
      final result = flattener.flatten(
        content.toInlines(forEditing: true, revealMarkdownAt: 1),
        const TextStyle(fontSize: 14),
      );
      expect(result.span.toPlainText(), rendered, reason: '${mark.kind}');
      expect(result.projection.projectAll(), 'x', reason: '${mark.kind}');
      expect(result.projection.contentLength, 1, reason: '${mark.kind}');
    }
  });

  test(
    'typing the opening delimiter around existing text applies the mark',
    () {
      final state = EditorState.fromTexts(['粗体** tail']);
      addTearDown(state.dispose);
      final block = state.blocks.first as TextBlock;
      state.updateSelection(
        EditorSelection.collapsed(EditorPosition(blockId: block.id, offset: 0)),
      );

      state.insertText('**');
      final result = tryApplyInputRules(state, block.id, typedChar: '*');

      expect(result, InputRuleOutcome.applied);
      final updated = state.blocks.first as TextBlock;
      expect(updated.content.text, '粗体 tail');
      expect(updated.content.marks, const [
        MarkSpan(start: 0, end: 2, kind: MarkKind.strong),
      ]);
      expect(state.selection!.extent.offset, 0);
    },
  );

  testWidgets('FluxdoEditor toggles delimiters with focus movement', (
    tester,
  ) async {
    final state = EditorState(
      blocks: [
        TextBlock(
          id: 'e_0',
          content: EditableTextContent(
            text: 'bold tail',
            marks: const [MarkSpan(start: 0, end: 4, kind: MarkKind.strong)],
          ),
        ),
      ],
    );
    addTearDown(state.dispose);
    state.updateSelection(
      const EditorSelection.collapsed(
        EditorPosition(blockId: 'e_0', offset: 2),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: FluxdoEditor(state: state, autofocus: true)),
      ),
    );
    await tester.pump();
    await tester.pump();

    RichText paragraph() => tester.widget<RichText>(
      find.descendant(
        of: find.byType(EditableParagraph),
        matching: find.byType(RichText),
      ),
    );

    expect(paragraph().text.toPlainText(), '**bold** tail');

    state.updateSelection(
      const EditorSelection.collapsed(
        EditorPosition(blockId: 'e_0', offset: 6),
      ),
    );
    await tester.pump();
    expect(paragraph().text.toPlainText(), 'bold tail');

    state.updateSelection(
      const EditorSelection.collapsed(
        EditorPosition(blockId: 'e_0', offset: 2),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FluxdoEditor(
            state: state,
            autofocus: true,
            liveMarkdownPreview: false,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(paragraph().text.toPlainText(), 'bold tail');
  });
}
