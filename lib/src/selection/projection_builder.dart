/// 从 InlineNode 树构建 [RenderTextProjection](渲染偏移 ↔ 逻辑投影映射表)。
///
/// **与 InlineFlattener 共享同一份 `inlines` 输入**,但只关心"渲染偏移 +
/// 投影文本",不碰 builder/handler/recognizer。两者必须在**渲染偏移模型**上
/// 保持一致(已探针实测 Flutter 3.44):
/// - TextSpan 贡献其文本长度;
/// - WidgetSpan(emoji/mention/image/spoiler/footnote/localDate/clickCount/math)
///   各贡献 **1** 个 ￼(U+FFFC);
/// - Em/Strong/Link 是 TextSpan children,偏移连续递归。
///
/// 投影规则(对齐主项目 HtmlTextMapper._collectTextNodes 的口径):
/// - TextRun/InlineCodeRun → 原文
/// - LineBreakRun → `\n`
/// - EmojiRun → `:name:`(空名 → `''`)
/// - MentionRun → `@username`
/// - ImageRun → alt(空 → `''`)
/// - SpoilerRun → 子节点投影全文(渲染层占 1 ￼,但投影成真实文本,对齐 cooked)
/// - FootnoteRefRun → number(对齐 cooked `<sup>N`)
/// - LocalDateRun → fallbackText(服务端预渲染文本)
/// - MathInlineRun → `''`(第一版,待 dogfood 校准)
/// - ClickCountRun → `''`(注入的,cooked 没有,必须排除)
library;

import '../node/inline_node.dart';
import 'projection.dart';

/// 把 inline 节点列表构建成映射表。根 span 的渲染偏移从 0 开始。
RenderTextProjection buildInlineProjection(List<InlineNode> inlines) {
  final entries = <ProjectionEntry>[];
  var cursor = 0;

  void addText(String text, ProjectionKind kind) {
    if (text.isEmpty) return;
    entries.add(ProjectionEntry(
      renderStart: cursor,
      renderLen: text.length,
      logicalText: text,
      kind: kind,
    ));
    cursor += text.length;
  }

  // 占位符:渲染层占 1 个 ￼,逻辑投影为 [logical](可空)。
  void addPlaceholder(String logical, ProjectionKind kind) {
    entries.add(ProjectionEntry(
      renderStart: cursor,
      renderLen: 1,
      logicalText: logical,
      kind: kind,
    ));
    cursor += 1;
  }

  // 把一组子节点投影拼成单串(给 spoiler 原子投影用)。
  String concatLogical(List<InlineNode> nodes) =>
      buildInlineProjection(nodes).projectAll();

  void walk(List<InlineNode> nodes) {
    for (final node in nodes) {
      switch (node) {
        case TextRun(:final text):
          addText(text, ProjectionKind.text);
        case LineBreakRun():
          addText('\n', ProjectionKind.lineBreak);
        case InlineCodeRun(:final text):
          addText(text, ProjectionKind.inlineCode);
        case EmRun(:final children):
          walk(children);
        case StrongRun(:final children):
          walk(children);
        case LinkRun(:final children):
          walk(children);
        case EmojiRun(:final name):
          addPlaceholder(name.isEmpty ? '' : ':$name:', ProjectionKind.emoji);
        case MentionRun(:final username):
          addPlaceholder('@$username', ProjectionKind.mention);
        case ImageRun(:final alt):
          addPlaceholder(alt, ProjectionKind.image);
        case SpoilerRun(:final children):
          // 渲染层是 1 个 WidgetSpan(￼),投影成子文本全文(对齐 cooked)。
          addPlaceholder(concatLogical(children), ProjectionKind.spoiler);
        case FootnoteRefRun(:final number):
          addPlaceholder(number, ProjectionKind.footnote);
        case LocalDateRun(:final fallbackText):
          addPlaceholder(fallbackText, ProjectionKind.localDate);
        case ClickCountRun():
          // 注入的,原始 cooked 没有 → 排除(空投影)。
          addPlaceholder('', ProjectionKind.clickCount);
        case MathInlineRun():
          // 第一版不投影(待 dogfood 校准)。
          addPlaceholder('', ProjectionKind.mathInline);
      }
    }
  }

  walk(inlines);
  return RenderTextProjection(entries);
}
