/// 渲染偏移 ↔ 逻辑投影文本 的映射表。
///
/// 一个段落压平成 Text.rich 后有两套坐标系:
/// - **渲染偏移**:RenderParagraph 看到的字符偏移,emoji/mention/image 等
///   WidgetSpan 各占 1 个 ￼(U+FFFC)。命中(getPositionForOffset)/高亮
///   (getBoxesForSelection)都认这个。
/// - **逻辑投影**:复制/引用要的纯文本,emoji→`:name:`、mention→`@username`。
///   这个要喂主项目 HtmlTextMapper 在原始 cooked 里匹配。
///
/// 映射表在 InlineFlattener 压平时**同步构建**(投影规则与 span 构造同源),
/// 每个 InlineSpan 叶子产出一条 [ProjectionEntry]。复制时 [RenderTextProjection.project]
/// 把渲染选区区间翻译成逻辑文本。
library;

import 'package:flutter/foundation.dart';

/// 投影条目的来源类型(调试 + 占位符原子性判定用)。
enum ProjectionKind {
  text,
  lineBreak,
  inlineCode,
  emoji,
  mention,
  image,
  spoiler,
  footnote,
  localDate,
  clickCount,
  mathInline,
}

/// 一段连续渲染偏移区间 `[renderStart, renderStart+renderLen)` → 逻辑文本。
///
/// - **文本类**(text/inlineCode/lineBreak):renderLen == logicalText 的渲染
///   长度,可按字符 substring 部分投影。
/// - **占位类**(emoji/mention/image/...):renderLen 恒为 1(一个 ￼),
///   [logicalText] 是整体投影串(如 `:heart:`),**原子** —— 选区相交即整条
///   计入,不切半。
/// - [logicalText] 为空串 = 不贡献文本(空名 emoji / 空 alt image / clickCount)。
@immutable
class ProjectionEntry {
  const ProjectionEntry({
    required this.renderStart,
    required this.renderLen,
    required this.logicalText,
    required this.kind,
  });

  final int renderStart;
  final int renderLen;
  final String logicalText;
  final ProjectionKind kind;

  /// 渲染偏移区间末端(不含)。
  int get renderEnd => renderStart + renderLen;

  /// 占位类(￼,原子,不可按字符切)。
  bool get isAtomic => kind != ProjectionKind.text &&
      kind != ProjectionKind.inlineCode &&
      kind != ProjectionKind.lineBreak;

  @override
  String toString() =>
      'ProjectionEntry($kind [$renderStart,$renderEnd) "$logicalText")';
}

/// 一个段落(一个 RenderParagraph)的完整映射表。
@immutable
class RenderTextProjection {
  RenderTextProjection(List<ProjectionEntry> entries)
      : entries = List.unmodifiable(entries),
        renderLength = entries.isEmpty ? 0 : entries.last.renderEnd;

  /// 按 renderStart 升序、连续覆盖整段(无空洞、无重叠)。
  final List<ProjectionEntry> entries;

  /// 总渲染长度,应 == RenderParagraph.text.toPlainText().length。
  final int renderLength;

  static final RenderTextProjection empty = RenderTextProjection(const []);

  /// 把渲染偏移区间 `[renderStart, renderEnd)` 投影成逻辑文本。
  ///
  /// - 文本类:取与区间交集的 substring。
  /// - 占位类(￼ 原子):只要区间与该条目有任何交集,就整条写入 [logicalText]。
  ///
  /// 入参越界自动 clamp;start >= end 返回空串。
  String project(int renderStart, int renderEnd) {
    var start = renderStart;
    var end = renderEnd;
    if (start > end) {
      final t = start;
      start = end;
      end = t;
    }
    start = start.clamp(0, renderLength);
    end = end.clamp(0, renderLength);
    if (start >= end) return '';

    final buf = StringBuffer();
    for (final e in entries) {
      // 与 [start, end) 无交集 → 跳过。
      if (e.renderEnd <= start || e.renderStart >= end) continue;

      if (e.isAtomic) {
        // ￼ 原子:相交即整条。
        buf.write(e.logicalText);
        continue;
      }

      // 文本类:logicalText 渲染长度 == renderLen,按字符切交集。
      // (text/inlineCode/lineBreak 的 logicalText.length 应 == renderLen;
      //  lineBreak 是 '\n' 长度 1 == renderLen 1。)
      final localStart = (start - e.renderStart).clamp(0, e.renderLen);
      final localEnd = (end - e.renderStart).clamp(0, e.renderLen);
      if (localStart >= localEnd) continue;
      // 防御:logicalText 可能与 renderLen 不等长(理论不应发生),clamp 到串长。
      final s = localStart.clamp(0, e.logicalText.length);
      final t = localEnd.clamp(0, e.logicalText.length);
      if (s < t) buf.write(e.logicalText.substring(s, t));
    }
    return buf.toString();
  }

  /// 整段逻辑文本(渲染全区间投影)。
  String projectAll() => project(0, renderLength);

  @override
  String toString() =>
      'RenderTextProjection(len=$renderLength, ${entries.length} entries)';
}
