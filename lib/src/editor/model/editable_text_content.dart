/// 可编辑段落的扁平行内模型。
///
/// 编辑操作(插入/删除/切分/合并)在**扁平坐标**上做:一个段落 =
/// 一段纯文本 + 若干互不嵌套约束的样式区间([MarkSpan])。这与
/// ProseMirror 的 inline 表示(text + marks)同构 —— 编辑是 O(区间数)
/// 的简单区间调整,不需要在嵌套树上找路径。
///
/// 渲染时通过 [toInlines] 转回 [InlineNode] 树喂现有 InlineFlattener,
/// 保证编辑态与阅读态视觉零差异(行内代码 NBSP 灰底等精调全部复用)。
///
/// **M1 范围**:纯文本 + 简单样式(em/strong/inline-code/styled)。
/// 原子节点(emoji/mention/image 等)M2 引入 atom 表后支持;M1 里
/// [EditableTextContent.fromInlines] 遇到不支持的节点按投影文本降级
/// (见 [_flattenInto] 的 fallback 分支)。
library;

import 'package:flutter/foundation.dart';

import '../../node/inline_node.dart';

/// 行内样式种类(编辑模型用,与 InlineNode 树的映射见 [MarkKind.wrap])。
enum MarkKind {
  em,
  strong,
  inlineCode,
  underline,
  lineThrough,
}

/// 一段样式区间 `[start, end)`(扁平文本坐标)。
@immutable
class MarkSpan {
  const MarkSpan({required this.start, required this.end, required this.kind});

  final int start;
  final int end;
  final MarkKind kind;

  bool get isEmpty => start >= end;

  MarkSpan copyWith({int? start, int? end}) =>
      MarkSpan(start: start ?? this.start, end: end ?? this.end, kind: kind);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MarkSpan &&
          runtimeType == other.runtimeType &&
          start == other.start &&
          end == other.end &&
          kind == other.kind;

  @override
  int get hashCode => Object.hash(start, end, kind);

  @override
  String toString() => 'MarkSpan($kind [$start,$end))';
}

/// 段落的扁平可编辑内容(不可变;编辑原语返回新实例)。
@immutable
class EditableTextContent {
  EditableTextContent({required this.text, List<MarkSpan> marks = const []})
      : marks = List.unmodifiable(
          marks.where((m) => !m.isEmpty).toList()
            ..sort((a, b) {
              final c = a.start.compareTo(b.start);
              return c != 0 ? c : a.end.compareTo(b.end);
            }),
        );

  static final EditableTextContent empty = EditableTextContent(text: '');

  final String text;

  /// 按 start 升序;同 kind 区间不重叠(构造方保证语义,本类不强校验)。
  final List<MarkSpan> marks;

  int get length => text.length;

  // -----------------------------------------------------------------
  // InlineNode 树 ↔ 扁平 双向转换
  // -----------------------------------------------------------------

  /// 从渲染节点树构建扁平模型。
  ///
  /// M1 支持:TextRun / EmRun / StrongRun / InlineCodeRun /
  /// StyledRun(underline|lineThrough) / LineBreakRun(转 '\n')。
  /// 其余节点(emoji/mention/image/link/...)降级为其纯文本表示
  /// (对齐 projection 的逻辑投影),样式丢弃 —— M2 的 atom 表会替换
  /// 这个 fallback。
  factory EditableTextContent.fromInlines(List<InlineNode> inlines) {
    final buf = StringBuffer();
    final marks = <MarkSpan>[];
    _flattenInto(inlines, buf, marks, const []);
    return EditableTextContent(text: buf.toString(), marks: marks);
  }

  static void _flattenInto(
    List<InlineNode> nodes,
    StringBuffer buf,
    List<MarkSpan> marks,
    List<MarkKind> activeKinds,
  ) {
    for (final node in nodes) {
      switch (node) {
        case TextRun(:final text):
          _appendText(buf, marks, activeKinds, text);
        case LineBreakRun():
          _appendText(buf, marks, activeKinds, '\n');
        case EmRun(:final children):
          _flattenInto(children, buf, marks, [...activeKinds, MarkKind.em]);
        case StrongRun(:final children):
          _flattenInto(children, buf, marks, [...activeKinds, MarkKind.strong]);
        case InlineCodeRun(:final text):
          _appendText(buf, marks, [...activeKinds, MarkKind.inlineCode], text);
        case StyledRun(:final kind, :final children):
          final mapped = switch (kind) {
            InlineStyleKind.underline => MarkKind.underline,
            InlineStyleKind.lineThrough => MarkKind.lineThrough,
            _ => null,
          };
          _flattenInto(
            children,
            buf,
            marks,
            mapped == null ? activeKinds : [...activeKinds, mapped],
          );
        // ---- M1 降级分支:按纯文本收编,样式/交互丢弃(TODO M2 atom 表) ----
        case LinkRun(:final children):
          _flattenInto(children, buf, marks, activeKinds);
        case EmojiRun(:final name):
          _appendText(buf, marks, activeKinds, name.isEmpty ? '' : ':$name:');
        case MentionRun(:final username):
          _appendText(buf, marks, activeKinds, '@$username');
        case ImageRun(:final alt):
          _appendText(buf, marks, activeKinds, alt);
        case SpoilerRun(:final children):
          _flattenInto(children, buf, marks, activeKinds);
        case ColoredRun(:final children):
          _flattenInto(children, buf, marks, activeKinds);
        case FootnoteRefRun():
        case LocalDateRun():
        case ClickCountRun():
        case MathInlineRun():
          // 无稳定文本表示的节点:M1 丢弃(编辑器不会由这些内容发起)。
          break;
      }
    }
  }

  static void _appendText(
    StringBuffer buf,
    List<MarkSpan> marks,
    List<MarkKind> activeKinds,
    String text,
  ) {
    if (text.isEmpty) return;
    final start = buf.length;
    buf.write(text);
    final end = buf.length;
    for (final kind in activeKinds) {
      // 与紧邻的同 kind 区间合并(嵌套展开会产生相邻碎段)。
      final lastIdx = marks.lastIndexWhere((m) => m.kind == kind);
      if (lastIdx >= 0 && marks[lastIdx].end == start) {
        marks[lastIdx] = marks[lastIdx].copyWith(end: end);
      } else {
        marks.add(MarkSpan(start: start, end: end, kind: kind));
      }
    }
  }

  /// 转回 InlineNode 树(渲染用)。
  ///
  /// 策略:按所有区间边界切文本为片段,每个片段带其覆盖样式集合,
  /// 相邻同样式片段已在边界切分时天然分开(不再合并 —— InlineFlattener
  /// 对相邻同样式 span 的渲染结果一致)。嵌套顺序固定:
  /// strong > em > underline > lineThrough 外层到内层;inlineCode 独占
  /// (InlineCodeRun 只持纯文本,与其他样式互斥,冲突时 code 优先)。
  List<InlineNode> toInlines() {
    if (text.isEmpty) return const [];

    // 1. 收集切点
    final cuts = <int>{0, text.length};
    for (final m in marks) {
      cuts.add(m.start.clamp(0, text.length));
      cuts.add(m.end.clamp(0, text.length));
    }
    // '\n' 单独成段(转 LineBreakRun)
    for (var i = 0; i < text.length; i++) {
      if (text[i] == '\n') {
        cuts.add(i);
        cuts.add(i + 1);
      }
    }
    final points = cuts.toList()..sort();

    // 2. 逐片段构建
    final out = <InlineNode>[];
    for (var i = 0; i + 1 < points.length; i++) {
      final s = points[i];
      final e = points[i + 1];
      if (s >= e) continue;
      final piece = text.substring(s, e);
      if (piece == '\n') {
        out.add(const LineBreakRun());
        continue;
      }
      final kinds = <MarkKind>{
        for (final m in marks)
          if (m.start <= s && m.end >= e) m.kind,
      };
      out.add(_wrapPiece(piece, kinds));
    }
    return out;
  }

  static InlineNode _wrapPiece(String piece, Set<MarkKind> kinds) {
    if (kinds.contains(MarkKind.inlineCode)) {
      return InlineCodeRun(piece);
    }
    InlineNode node = TextRun(piece);
    if (kinds.contains(MarkKind.lineThrough)) {
      node = StyledRun(kind: InlineStyleKind.lineThrough, children: [node]);
    }
    if (kinds.contains(MarkKind.underline)) {
      node = StyledRun(kind: InlineStyleKind.underline, children: [node]);
    }
    if (kinds.contains(MarkKind.em)) {
      node = EmRun(children: [node]);
    }
    if (kinds.contains(MarkKind.strong)) {
      node = StrongRun(children: [node]);
    }
    return node;
  }

  // -----------------------------------------------------------------
  // 编辑原语(全部返回新实例)
  // -----------------------------------------------------------------

  /// 在 [offset] 处插入 [inserted]。样式区间调整规则:
  /// - 区间完全在插入点前/后:不变/整体右移;
  /// - 插入点在区间内部(start < offset < end):区间拉长(延续样式,
  ///   对齐主流编辑器"在粗体中间打字仍是粗体");
  /// - 插入点恰在区间边界:不延续(在粗体结尾打字回到正常)。
  EditableTextContent insert(int offset, String inserted) {
    assert(offset >= 0 && offset <= text.length);
    if (inserted.isEmpty) return this;
    final len = inserted.length;
    final newMarks = <MarkSpan>[];
    for (final m in marks) {
      if (m.end <= offset) {
        newMarks.add(m);
      } else if (m.start >= offset) {
        newMarks.add(m.copyWith(start: m.start + len, end: m.end + len));
      } else {
        newMarks.add(m.copyWith(end: m.end + len));
      }
    }
    return EditableTextContent(
      text: text.replaceRange(offset, offset, inserted),
      marks: newMarks,
    );
  }

  /// 删除 `[start, end)` 区间。
  EditableTextContent delete(int start, int end) {
    assert(start >= 0 && end <= text.length && start <= end);
    if (start == end) return this;
    final len = end - start;
    final newMarks = <MarkSpan>[];
    for (final m in marks) {
      // 区间平移/收缩:与删除区间求差。
      final ns = m.start <= start
          ? m.start
          : (m.start >= end ? m.start - len : start);
      final ne = m.end <= start ? m.end : (m.end >= end ? m.end - len : start);
      final span = m.copyWith(start: ns, end: ne);
      if (!span.isEmpty) newMarks.add(span);
    }
    return EditableTextContent(
      text: text.replaceRange(start, end, ''),
      marks: newMarks,
    );
  }

  /// 替换 `[start, end)` 为 [replacement](IME composing 更新的主路径)。
  EditableTextContent replace(int start, int end, String replacement) =>
      delete(start, end).insert(start, replacement);

  /// 在 [offset] 处切成两半(回车分段)。
  (EditableTextContent before, EditableTextContent after) split(int offset) {
    assert(offset >= 0 && offset <= text.length);
    final before = delete(offset, text.length);
    final after = delete(0, offset);
    return (before, after);
  }

  /// 与 [other] 拼接(段首退格合并)。
  EditableTextContent concat(EditableTextContent other) {
    final base = text.length;
    return EditableTextContent(
      text: text + other.text,
      marks: [
        ...marks,
        for (final m in other.marks)
          m.copyWith(start: m.start + base, end: m.end + base),
      ],
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EditableTextContent &&
          runtimeType == other.runtimeType &&
          text == other.text &&
          listEquals(marks, other.marks);

  @override
  int get hashCode => Object.hash(text, Object.hashAll(marks));

  @override
  String toString() =>
      'EditableTextContent(${text.length} chars, ${marks.length} marks)';
}
