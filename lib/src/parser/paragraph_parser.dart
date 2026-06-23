/// HTML cooked → `List<BlockNode>` 解析器(阶段 1 范围)。
///
/// 当前作用域:
/// - 块级:`<p>` / `<h1>` - `<h6>` / `<ul>` / `<ol>` / `<blockquote>` /
///   `<hr>`(其他块级标签 fallback 成 ParagraphNode + textContent)
/// - 行内:文本 / `<em>` / `<i>` / `<strong>` / `<b>` / `<br>` /
///   `<a href>` / `<code>` / `<img class="emoji">`
///
/// 后续阶段会扩展 code_block / 等。

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

    // 全局 id counter — 嵌套块级(list / blockquote 等)也用这个分配,
    // 保证一次 parse 内的 BlockNode id 全局唯一。
    var idCounter = 0;
    String nextId() => 'b_${idCounter++}';

    return _parseBlocks(fragment.nodes, nextId);
  }

  /// 把一组 DOM 节点解析成 BlockNode 序列。
  /// 顶层 parse 调它处理 fragment.nodes;blockquote 递归调它处理 inner。
  ///
  /// 处理流程:
  /// - 块级 element → 直接产 BlockNode
  /// - inline element / 裸 text → 累积到 pendingInlines,遇到下一个块级
  ///   或结束时 flush 成 ParagraphNode
  List<BlockNode> _parseBlocks(
    Iterable<dom.Node> nodes,
    String Function() nextId,
  ) {
    final out = <BlockNode>[];
    final pendingInlines = <InlineNode>[];

    void flushInlines() {
      if (pendingInlines.isEmpty) return;
      out.add(ParagraphNode(
        id: nextId(),
        inlines: List.unmodifiable(pendingInlines),
      ));
      pendingInlines.clear();
    }

    for (final node in nodes) {
      switch (node) {
        case dom.Element():
          final tag = node.localName?.toLowerCase() ?? '';
          if (_isInlineTag(tag)) {
            // inline 元素 → 累积到 pending
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
              case 'ul' || 'ol':
                out.add(_parseList(
                  node,
                  ordered: tag == 'ol',
                  depth: 0,
                  nextId: nextId,
                ));
              case 'blockquote':
                // blockquote 是块级容器,递归处理内部 BlockNode
                out.add(BlockquoteNode(
                  id: nextId(),
                  children: _parseBlocks(node.nodes, nextId),
                ));
              case 'hr':
                out.add(HorizontalRuleNode(id: nextId()));
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

  /// 把 `<ul>` / `<ol>` 解析成 ListNode,递归处理嵌套子 list。
  ListNode _parseList(
    dom.Element listEl, {
    required bool ordered,
    required int depth,
    required String Function() nextId,
  }) {
    final items = <ListItem>[];
    for (final child in listEl.nodes) {
      if (child is! dom.Element) continue;
      if (child.localName?.toLowerCase() != 'li') continue;

      final inlines = <InlineNode>[];
      final subLists = <ListNode>[];
      for (final liChild in child.nodes) {
        if (liChild is dom.Element) {
          final liTag = liChild.localName?.toLowerCase() ?? '';
          if (liTag == 'ul' || liTag == 'ol') {
            subLists.add(_parseList(
              liChild,
              ordered: liTag == 'ol',
              depth: depth + 1,
              nextId: nextId,
            ));
            continue;
          }
        }
        // 跳过 li 直属的纯空白文本(HTML 缩进 + 换行,markdown 渲染时
        // 自动加的,在浏览器里不显示;不跳过会让 InlineSpanText 多渲染
        // 一行 `\n`,跟下面的子 list 之间空一截)
        if (liChild is dom.Text && liChild.text.trim().isEmpty) continue;
        _collectInlineFromAnyNode(liChild, inlines);
      }
      // 把首尾 TextRun 的 leading/trailing whitespace(`\n`、缩进 space)
      // 去掉,但保留中间 inline 之间的空格(`"x <em>y</em> z"` 里两端空格
      // 是有意义的)。
      _trimEdgeWhitespace(inlines);
      items.add(ListItem(
        inlines: List.unmodifiable(inlines),
        children: subLists.isEmpty ? null : List.unmodifiable(subLists),
      ));
    }
    return ListNode(
      id: nextId(),
      ordered: ordered,
      depth: depth,
      items: List.unmodifiable(items),
    );
  }

  /// 原地去掉 inline 列表首尾 TextRun 的 leading/trailing whitespace
  /// (`\n`、 tab、 space、 缩进等)。中间的 TextRun 不动。
  ///
  /// 用于 li 的 inline 收尾:HTML 缩进引入的 `\n` 在浏览器里不渲染,
  /// 但在 RichText 里会变成空行,必须清理。
  void _trimEdgeWhitespace(List<InlineNode> inlines) {
    if (inlines.isEmpty) return;
    // leading
    if (inlines.first is TextRun) {
      final t = (inlines.first as TextRun).text;
      final trimmed = t.trimLeft();
      if (trimmed.isEmpty) {
        inlines.removeAt(0);
      } else if (trimmed.length != t.length) {
        inlines[0] = TextRun(trimmed);
      }
    }
    if (inlines.isEmpty) return;
    // trailing
    if (inlines.last is TextRun) {
      final t = (inlines.last as TextRun).text;
      final trimmed = t.trimRight();
      if (trimmed.isEmpty) {
        inlines.removeLast();
      } else if (trimmed.length != t.length) {
        inlines[inlines.length - 1] = TextRun(trimmed);
      }
    }
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
        } else if (el.classes.contains('mention')) {
          // class="mention" 优先识别为 MentionRun,跳用户卡;
          // 内部可能含 <img class="emoji mention-status"> 状态 emoji,
          // 把它从展平的 children 里挑出来,纯文本拼回 username
          EmojiRun? statusEmoji;
          final textBuf = StringBuffer();
          for (final c in children) {
            switch (c) {
              case TextRun(:final text):
                textBuf.write(text);
              case EmojiRun():
                statusEmoji ??= c;
              case _:
                // mention 内不期望其他 inline 节点;真出现就丢弃
                break;
            }
          }
          // username 去掉 @ 前缀
          final username = textBuf.toString().trim().replaceFirst(RegExp(r'^@'), '');
          out.add(MentionRun(
            username: username,
            href: href,
            statusEmoji: statusEmoji,
          ));
        } else {
          out.add(LinkRun(href: href, children: List.unmodifiable(children)));
        }
      case 'code':
        // 浏览器 `<code>` 的实际语义:展示原始字面值,内部 markup 视觉
        // 被 monospace 盖住意义。这里直接把所有 textContent 拼成一段,
        // 不保留嵌套样式。
        out.add(InlineCodeRun(_textContent(el)));
      case 'img':
        // 只识别 class="emoji" 的 img — 普通 inline img(图片帖正文)
        // 走阶段 2 image 节点单独实现。
        if (el.classes.contains('emoji')) {
          final src = el.attributes['src']?.trim() ?? '';
          // alt/title 里去掉首尾 `:`(Discourse 形如 `:heart:`)
          final raw = (el.attributes['title'] ?? el.attributes['alt'] ?? '').trim();
          final name = raw.replaceAll(RegExp(r'^:|:$'), '');
          out.add(EmojiRun(
            name: name,
            url: src,
            isOnlyEmoji: el.classes.contains('only-emoji'),
          ));
        }
        // 非 emoji 的 img 暂时丢弃(阶段 2 加 image 节点)
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
  static const _inlineTags = {'em', 'i', 'strong', 'b', 'br', 'a', 'code', 'img'};

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
