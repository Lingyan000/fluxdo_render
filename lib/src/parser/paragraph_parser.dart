/// HTML cooked → `List<BlockNode>` 解析器(阶段 1 范围)。
///
/// 当前作用域:
/// - 块级:`<p>` / `<h1>` - `<h6>`(其他块级标签 fallback 成 ParagraphNode + textContent)
/// - 行内:文本 / `<em>` / `<i>` / `<strong>` / `<b>` / `<br>` /
///   `<a href>` / `<code>`
///
/// 后续阶段会扩展 list / blockquote / code_block / 等。

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
  ///
  /// 每个产出的 BlockNode 分配稳定 id("b_0", "b_1", ...),id 仅在
  /// 这一次 parse 调用内有意义,不跨调用稳定(同一 html parse 两次 id
  /// 相同是因为顺序确定,不需要额外保证)。
  List<BlockNode> parse(String html) {
    if (html.isEmpty) return const [];

    final fragment = html_parser.parseFragment(html);
    final out = <BlockNode>[];
    final pendingInlines = <InlineNode>[];

    String nextId() => 'b_${out.length}';

    void flushInlines() {
      if (pendingInlines.isEmpty) return;
      out.add(ParagraphNode(
        id: nextId(),
        inlines: List.unmodifiable(pendingInlines),
      ));
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
                out.add(ParagraphNode(
                  id: nextId(),
                  inlines: List.unmodifiable(inlines),
                ));
              case 'h1' || 'h2' || 'h3' || 'h4' || 'h5' || 'h6':
                final level = int.parse(tag.substring(1));
                final inlines = <InlineNode>[];
                for (final child in node.nodes) {
                  _collectInlineFromAnyNode(child, inlines);
                }
                out.add(HeadingNode(
                  id: nextId(),
                  level: level,
                  inlines: List.unmodifiable(inlines),
                ));
              default:
                // 未识别块级:fallback 为 paragraph,只取纯 textContent,
                // 不识别内部 inline tag(因为我们还不知道该块的语义 ——
                // 比如 <pre><code> 在 code_block 节点实现前,fallback 应该
                // 是平铺源码,而不是把 <code> 当成 inline code 渲染灰底)。
                final text = node.text;
                if (text.trim().isNotEmpty) {
                  out.add(ParagraphNode(
                    id: nextId(),
                    inlines: List.unmodifiable([TextRun(text)]),
                  ));
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
      case 'a':
        final href = el.attributes['href']?.trim() ?? '';
        if (href.isEmpty) {
          // 空 href:fallback 为纯样式(展平子节点,不可点)
          out.addAll(children);
        } else {
          out.add(LinkRun(href: href, children: List.unmodifiable(children)));
        }
      case 'code':
        // 浏览器 `<code>` 的实际语义:展示原始字面值,内部 markup 视觉
        // 被 monospace 盖住意义。这里直接把所有 textContent 拼成一段,
        // 不保留嵌套样式。
        out.add(InlineCodeRun(_textContent(el)));
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
  static const _inlineTags = {'em', 'i', 'strong', 'b', 'br', 'a', 'code'};

  bool _isInlineTag(String tag) => _inlineTags.contains(tag);

  /// 把元素子树的所有 text 节点拼成一段(用于 InlineCodeRun)。
  /// 不递归 attribute、不做 trim、保留所有空白。
  String _textContent(dom.Element el) {
    final buf = StringBuffer();
    void visit(dom.Node n) {
      if (n is dom.Text) {
        buf.write(n.text);
      } else if (n is dom.Element) {
        for (final c in n.nodes) {
          visit(c);
        }
      }
    }
    for (final c in el.nodes) {
      visit(c);
    }
    return buf.toString();
  }
}
