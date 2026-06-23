/// HTML cooked → `List<BlockNode>` 解析器(阶段 1.1 范围)。
///
/// 当前作用域:
/// - 块级:`<p>`(其他块级标签 fallback 成 ParagraphNode + textContent)
/// - 行内:文本 / `<em>` / `<i>` / `<strong>` / `<b>` / `<br>`
///
/// 后续阶段会扩展 heading / list / blockquote / 等。

library;

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../node/node.dart';

class ParagraphParser {
  const ParagraphParser();

  /// 把 cooked HTML 解析成 BlockNode 序列。
  ///
  /// - 顶层 `<p>` → `ParagraphNode`
  /// - 顶层裸文本(罕见,如 fragment 直接挂文本节点) → `ParagraphNode([TextRun(...)])`
  /// - 顶层未识别块级(如 `<h1>` 在阶段 1.1 未实现)→ 当作 paragraph,只取
  ///   textContent
  /// - 顶层 inline-only(没用 `<p>` 包,某些 cooked 形态)→ 把这一组合并
  ///   成单个 ParagraphNode
  List<BlockNode> parse(String html) {
    if (html.isEmpty) return const [];

    final fragment = html_parser.parseFragment(html);
    final out = <BlockNode>[];
    final pendingInlines = <InlineNode>[];

    void flushInlines() {
      if (pendingInlines.isEmpty) return;
      out.add(ParagraphNode(inlines: List.unmodifiable(pendingInlines)));
      pendingInlines.clear();
    }

    for (final node in fragment.nodes) {
      switch (node) {
        case dom.Element():
          final tag = node.localName?.toLowerCase() ?? '';
          if (_isInlineTag(tag)) {
            // 顶层 inline 元素 → 累积到 pending
            _collectInline(node, pendingInlines);
          } else {
            flushInlines();
            // 块级
            switch (tag) {
              case 'p':
                final inlines = <InlineNode>[];
                for (final child in node.nodes) {
                  _collectInlineFromAnyNode(child, inlines);
                }
                out.add(ParagraphNode(inlines: List.unmodifiable(inlines)));
              default:
                // 未识别块级:fallback 为 paragraph,取所有 textContent 包成一段
                final inlines = <InlineNode>[];
                for (final child in node.nodes) {
                  _collectInlineFromAnyNode(child, inlines);
                }
                if (inlines.isNotEmpty) {
                  out.add(ParagraphNode(inlines: List.unmodifiable(inlines)));
                }
            }
          }
        case dom.Text():
          final text = node.text;
          if (text.trim().isNotEmpty) {
            pendingInlines.add(TextRun(text));
          }
        // 其他节点类型(注释 / 文档类型等)忽略
      }
    }

    flushInlines();
    return List.unmodifiable(out);
  }

  /// 把一个 inline element 转成 InlineNode 加入 out。
  void _collectInline(dom.Element el, List<InlineNode> out) {
    final tag = el.localName?.toLowerCase() ?? '';
    final children = <InlineNode>[];
    for (final child in el.nodes) {
      _collectInlineFromAnyNode(child, children);
    }
    switch (tag) {
      case 'em' || 'i':
        out.add(EmRun(children: List.unmodifiable(children)));
      case 'strong' || 'b':
        out.add(StrongRun(children: List.unmodifiable(children)));
      case 'br':
        out.add(const LineBreakRun());
      default:
        // 未识别 inline:展平子节点
        out.addAll(children);
    }
  }

  /// 把任意 DOM 节点(文本 / inline element / 不该出现的块级)转成 InlineNode。
  void _collectInlineFromAnyNode(dom.Node node, List<InlineNode> out) {
    switch (node) {
      case dom.Text():
        final text = node.text;
        if (text.isNotEmpty) {
          out.add(TextRun(text));
        }
      case dom.Element():
        _collectInline(node, out);
      // 其他节点忽略
    }
  }

  /// 已支持的 inline 标签集合。
  static const _inlineTags = {'em', 'i', 'strong', 'b', 'br'};

  bool _isInlineTag(String tag) => _inlineTags.contains(tag);
}
