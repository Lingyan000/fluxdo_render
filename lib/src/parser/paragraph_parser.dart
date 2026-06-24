/// HTML cooked → `List<BlockNode>` 解析器(阶段 1 范围)。
///
/// 当前作用域:
/// - 块级:`<p>` / `<h1>` - `<h6>` / `<ul>` / `<ol>` / `<blockquote>` /
///   `<hr>` / `<pre>`(其他块级标签 fallback 成 ParagraphNode + textContent)
/// - 行内:文本 / `<em>` / `<i>` / `<strong>` / `<b>` / `<br>` /
///   `<a href>` / `<code>` / `<img>`
///
/// 后续阶段会扩展 quote_card / spoiler / 等。

library;

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../node/node.dart';

class ParagraphParser {
  ParagraphParser();

  /// 本次 parse 调用中收集的 fnId → contentHtml 映射。
  /// `parse` 入口扫一次 fragment 填,sup.footnote-ref 解析时直接 lookup。
  /// **注意:不是线程安全 — ParagraphParser 不应被多线程同时调用同一实例。**
  /// 实践上每次 parse 都会重置,无需调用方关心。
  Map<String, String> _footnotes = const {};

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

    // 全局 image index counter,按 image 出现顺序自增分配 indexInPost。
    // 给主项目算 Hero tag / gallery viewer 索引用。
    var imageIndexCounter = 0;
    int nextImageIndex() => imageIndexCounter++;

    // 一次性扫整个 fragment 建立 fnId → contentHtml 映射,
    // 后续 sup.footnote-ref 解析时直接 lookup(避免 inline 节点再回查)。
    _footnotes = _collectFootnoteContents(fragment);

    return _parseBlocks(fragment.nodes, nextId, nextImageIndex);
  }

  /// 扫整个 fragment 收集 `section.footnotes` / `ol.footnotes-list` 下的
  /// 所有 `<li id="fnId">` → contentHtml 映射。
  ///
  /// contentHtml 处理:
  /// - 移除 backref(`<a class="footnote-backref">↩︎</a>`)
  /// - 若整体被 `<p>...</p>` 单层包裹,剥掉外层 p(legacy 同处理)
  /// - trim
  ///
  /// 找不到任何 footnotes section 时返回空 map。
  Map<String, String> _collectFootnoteContents(dom.DocumentFragment fragment) {
    final out = <String, String>{};
    // 收 section.footnotes 或 ol.footnotes-list 内所有 li
    final candidates = <dom.Element>[
      ...fragment.querySelectorAll('section.footnotes li'),
      ...fragment.querySelectorAll('ol.footnotes-list li'),
    ];
    for (final li in candidates) {
      final id = li.attributes['id']?.trim();
      if (id == null || id.isEmpty) continue;
      if (out.containsKey(id)) continue;
      var html = li.innerHtml;
      // 去掉 backref(可能在末尾,可能含 emoji ↩)
      html = html.replaceAll(
        RegExp(
          r'<a[^>]*class="[^"]*footnote-backref[^"]*"[^>]*>[\s\S]*?</a>',
          caseSensitive: false,
        ),
        '',
      );
      // 剥掉单层 <p>...</p>
      html = html
          .replaceAll(RegExp(r'^\s*<p>\s*'), '')
          .replaceAll(RegExp(r'\s*</p>\s*$'), '')
          .trim();
      if (html.isNotEmpty) out[id] = html;
    }
    return out;
  }


  /// 顶层 parse 调它处理 fragment.nodes;blockquote 递归调它处理 inner。
  ///
  /// 处理流程:
  /// - 块级 element → 直接产 BlockNode
  /// - inline element / 裸 text → 累积到 pendingInlines,遇到下一个块级
  ///   或结束时 flush 成 ParagraphNode
  List<BlockNode> _parseBlocks(
    Iterable<dom.Node> nodes,
    String Function() nextId,
    int Function() nextImageIndex,
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
          // 顶层裸 <br>:Discourse cooked 经常在 block 之间塞 <br> 作为
          // markdown 段间格式残留(浏览器里因为 block 之间已有 margin 而
          // 几乎不可见),不能让它单起一行 ParagraphNode 占额外高度。
          if (tag == 'br' && pendingInlines.isEmpty) continue;
          // div.lazy-video-container:懒加载视频卡片(youtube / vimeo / tiktok)
          if (tag == 'div' && node.classes.contains('lazy-video-container')) {
            flushInlines();
            out.add(_parseLazyVideo(node, nextId));
            continue;
          }
          // div.d-image-grid:多图网格(Discourse 原生 image-grid 组件)。
          // 优先于 lightbox-wrapper 检测,因为 grid 内可能含多个 lightbox-wrapper。
          if (tag == 'div' && node.classes.contains('d-image-grid')) {
            flushInlines();
            out.add(_parseImageGrid(node, nextId, nextImageIndex));
            continue;
          }
          // div.lightbox-wrapper 当 inline 流:cooked 里多张图常常是连续
          // 的 `<div class="lightbox-wrapper">` 块,如果各产独立 ParagraphNode,
          // 段间累加 1em+1em margin,两张图之间空一大截。改让它进 pending,
          // 跟相邻 image 合并到同一 ParagraphNode。
          if (tag == 'div' && node.classes.contains('lightbox-wrapper')) {
            final imgRun = _imageRunFromLightboxWrapper(node, nextImageIndex);
            if (imgRun != null) pendingInlines.add(imgRun);
            continue;
          }
          if (_isInlineTag(tag)) {
            // inline 元素 → 累积到 pending
            _collectInline(node, pendingInlines, nextImageIndex);
          } else {
            flushInlines();
            // 块级
            switch (tag) {
              case 'p':
                final inlines = <InlineNode>[];
                for (final child in node.nodes) {
                  _collectInlineFromAnyNode(child, inlines, nextImageIndex);
                }
                // 空 paragraph 不产节点。HTML5 在某些 implicit p-close 情况下
                // (例如 `<p><div>...</div></p>` 里 div 自动关闭 p,后续 </p>
                // 无配对会产生空 p)会有这种残留,渲染时多出空段落不美观。
                if (inlines.isEmpty) break;
                out.add(ParagraphNode(
                  id: nextId(),
                  inlines: List.unmodifiable(inlines),
                ));
              case 'h1' || 'h2' || 'h3' || 'h4' || 'h5' || 'h6':
                final level = int.parse(tag.substring(1));
                final inlines = <InlineNode>[];
                for (final child in node.nodes) {
                  _collectInlineFromAnyNode(child, inlines, nextImageIndex);
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
                  nextImageIndex: nextImageIndex,
                ));
              case 'blockquote':
                // blockquote 是块级容器,先尝试识别 Obsidian Callout 形态
                // (首段以 [!type] 起头),否则普通 BlockquoteNode 递归。
                final callout = _tryParseCallout(node, nextId, nextImageIndex);
                if (callout != null) {
                  out.add(callout);
                } else {
                  out.add(BlockquoteNode(
                    id: nextId(),
                    children: _parseBlocks(node.nodes, nextId, nextImageIndex),
                  ));
                }
              case 'hr':
                // hr.footnotes-sep:legacy 隐藏(脚注体系的分隔)。
                // 其他 hr 才走 HorizontalRuleNode。
                if (node.classes.contains('footnotes-sep')) break;
                out.add(HorizontalRuleNode(id: nextId()));
              case 'pre':
                // `<pre><code class="lang-xxx">...</code></pre>` —— 代码块。
                // 取 textContent(已解码 HTML 实体),从 class 提语言。
                final codeEl = node.children.firstWhere(
                  (c) => c.localName?.toLowerCase() == 'code',
                  orElse: () => node,
                );
                final rawText = codeEl.text;
                // 去掉末尾换行避免多空行(legacy 同样处理)
                final code = rawText.endsWith('\n')
                    ? rawText.substring(0, rawText.length - 1)
                    : rawText;
                String? language;
                final className = codeEl.className;
                if (className.isNotEmpty) {
                  final m = RegExp(r'lang-(\w+)').firstMatch(className);
                  if (m != null) language = m.group(1)?.toLowerCase();
                }
                out.add(CodeBlockNode(
                  id: nextId(),
                  code: code,
                  language: language,
                ));
              case 'aside':
                // class="quote" → QuoteCardNode
                // class="onebox" / 含 *-onebox 子类 → OneboxNode
                if (node.classes.contains('quote')) {
                  out.add(_parseQuoteCard(node, nextId, nextImageIndex));
                } else if (node.classes.contains('onebox') ||
                    node.classes.any((c) => c.endsWith('-onebox'))) {
                  out.add(_parseOnebox(node, nextId));
                } else {
                  // 其他 aside:走 fallback textContent
                  final text = node.text;
                  if (text.trim().isNotEmpty) {
                    out.add(ParagraphNode(
                      id: nextId(),
                      inlines: List.unmodifiable([TextRun(text)]),
                    ));
                  }
                }
              case 'div' when node.classes.contains('spoiler') ||
                    node.classes.contains('spoiled'):
                // 块级 spoiler:div.spoiler / div.spoiled
                out.add(SpoilerBlockNode(
                  id: nextId(),
                  children: _parseBlocks(node.nodes, nextId, nextImageIndex),
                ));
              case 'details':
                // 折叠块:<details><summary>标题</summary>内容</details>
                out.add(_parseDetails(node, nextId, nextImageIndex));
              case 'section' when node.classes.contains('footnotes'):
                // 脚注列表区(隐藏占位 — 真正的脚注内容已在 _collectFootnoteContents
                // 提前 inline 到 FootnoteRefRun)
                out.add(FootnotesSectionNode(id: nextId()));
              case 'iframe':
                // 嵌入 iframe — 子包不渲染 webview,只产 IframeNode 让主项目
                // 通过 iframeBuilder 注入真实 widget,fallback 显示占位卡。
                out.add(_parseIframe(node, nextId));
              case 'table':
                // 表格 — thead/tbody/tr/th/td 递归;cell 内 children
                // 走 _parseBlocks(保留 inline 样式 + 嵌套块级)
                final t = _parseTable(node, nextId, nextImageIndex);
                if (t != null) out.add(t);
              // 注意:div.lightbox-wrapper 在块级 switch 之前已被截获
              // 走 pendingInlines 流(不会到达这里),目的是让连续多张
              // lightbox 图合并到同一 ParagraphNode,消除 1em+1em 段间距。
              default:
                // 未识别块级:fallback 为 paragraph,只取纯 textContent,
                // 不识别内部 inline tag(因为我们还不知道该块的语义 ——
                // 比如 <pre><code> 在 code_block 节点实现前,fallback 应该
                // 是平铺源码,而不是把 <code> 当成 inline code 渲染灰底)。
                //
                // 但跳过 skip 元素(svg / d-icon / meta / lb-spacer),
                // 它们没有有意义的文字内容(只是 UI 占位)。
                if (_isSkipElement(tag, node)) break;
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
    required int Function() nextImageIndex,
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
              nextImageIndex: nextImageIndex,
            ));
            continue;
          }
        }
        // 跳过 li 直属的纯空白文本(HTML 缩进 + 换行,markdown 渲染时
        // 自动加的,在浏览器里不显示;不跳过会让 InlineSpanText 多渲染
        // 一行 `\n`,跟下面的子 list 之间空一截)
        if (liChild is dom.Text && liChild.text.trim().isEmpty) continue;
        _collectInlineFromAnyNode(liChild, inlines, nextImageIndex);
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

  /// 解析 `<aside class="quote">` 为 QuoteCardNode。
  ///
  /// 提取 data-username / data-topic / data-post + img.avatar + title 标题 +
  /// blockquote 内容(递归 _parseBlocks)。
  ///
  /// 兼容两种标题形态:
  /// - 新版:`.quote-title__text-content > a`
  /// - 老版:`.title > a`(legacy quote_card_builder 同样回退)
  QuoteCardNode _parseQuoteCard(
    dom.Element asideEl,
    String Function() nextId,
    int Function() nextImageIndex,
  ) {
    final username = asideEl.attributes['data-username']?.trim() ?? '';
    final topicId = int.tryParse(asideEl.attributes['data-topic'] ?? '');
    final postNumber = int.tryParse(asideEl.attributes['data-post'] ?? '');

    final avatarEl = asideEl.querySelector('img.avatar');
    final avatarUrl = avatarEl?.attributes['src']?.trim();

    // 标题:新版 .quote-title__text-content > a;老版 .title > a
    final titleAEl = asideEl.querySelector(
          '.quote-title__text-content a',
        ) ??
        asideEl.querySelector('.title a');
    String? titleText;
    String? titleHref;
    if (titleAEl != null) {
      titleText = titleAEl.text.trim();
      titleHref = titleAEl.attributes['href']?.trim();
      if (titleText.isEmpty) titleText = null;
      if ((titleHref ?? '').isEmpty) titleHref = null;
    }

    final blockquoteEl = asideEl.querySelector('blockquote');
    final children = blockquoteEl == null
        ? const <BlockNode>[]
        : _parseBlocks(blockquoteEl.nodes, nextId, nextImageIndex);

    return QuoteCardNode(
      id: nextId(),
      username: username,
      avatarUrl: (avatarUrl ?? '').isEmpty ? null : avatarUrl,
      titleText: titleText,
      titleHref: titleHref,
      topicId: topicId,
      postNumber: postNumber,
      children: children,
    );
  }

  /// 解析 `<aside class="onebox">` / `<aside class="*-onebox">` 为 OneboxNode。
  ///
  /// 子包只提结构化关键字段 + 保留 rawHtml(给主项目 OneboxBuilder 兜底)。
  /// kind 识别参考 legacy `onebox_type.dart::detectOneboxType` 的 6 大类
  /// (不细化到 githubRepo / githubIssue 等 24 种子类型 — 那是 builder 内
  /// 基于 URL 二次判断的事)。
  OneboxNode _parseOnebox(dom.Element asideEl, String Function() nextId) {
    final classes = <String>{};
    classes.addAll(asideEl.classes);
    // 嵌套 article / 子 aside 的 class 也算(legacy 同套路)
    final articleEl = asideEl.querySelector('article');
    if (articleEl != null) classes.addAll(articleEl.classes);

    OneboxKind kind;
    if (classes.contains('user-onebox')) {
      kind = OneboxKind.user;
    } else if (classes.contains('github-onebox') ||
        classes.contains('onebox-github') ||
        classes.any((c) => c.startsWith('github'))) {
      kind = OneboxKind.github;
    } else if (classes.contains('twitterstatus') ||
        classes.contains('twitter-tweet') ||
        classes.contains('reddit') ||
        classes.contains('reddit-onebox') ||
        classes.contains('instagram-onebox') ||
        classes.contains('instagram') ||
        classes.contains('threads-onebox') ||
        classes.contains('tiktok-onebox')) {
      kind = OneboxKind.social;
    } else if (classes.contains('youtube-onebox') ||
        classes.contains('lazyYT') ||
        classes.contains('vimeo-onebox') ||
        classes.contains('loom-onebox')) {
      kind = OneboxKind.video;
    } else if (classes.contains('stackexchange-onebox') ||
        classes.contains('stackoverflow-onebox') ||
        classes.contains('hackernews-onebox') ||
        classes.contains('ycombinator') ||
        classes.contains('pastebin-onebox') ||
        classes.contains('googledocs-onebox') ||
        classes.contains('pdf-onebox') ||
        classes.contains('amazon-onebox')) {
      kind = OneboxKind.tech;
    } else {
      kind = OneboxKind.defaultKind;
    }

    // url:data-onebox-src 优先 → header a / h3 a / h4 a
    String url = asideEl.attributes['data-onebox-src']?.trim() ?? '';
    if (url.isEmpty) {
      final headerA = asideEl.querySelector('header a');
      url = headerA?.attributes['href']?.trim() ?? '';
    }
    if (url.isEmpty) {
      final h3a = asideEl.querySelector('h3 a');
      url = h3a?.attributes['href']?.trim() ?? '';
    }
    if (url.isEmpty) {
      final h4a = asideEl.querySelector('h4 a');
      url = h4a?.attributes['href']?.trim() ?? '';
    }

    // title:h3 a / h4 a / h3 / h4 text
    final titleA = asideEl.querySelector('h4 a') ??
        asideEl.querySelector('h3 a');
    final title = titleA?.text.trim() ??
        asideEl.querySelector('h3')?.text.trim() ??
        asideEl.querySelector('h4')?.text.trim() ??
        '';

    // description:第一个 p
    final description = asideEl.querySelector('p')?.text.trim() ?? '';

    // favicon:img.site-icon / img.favicon
    final iconEl = asideEl.querySelector('img.site-icon') ??
        asideEl.querySelector('img.favicon');
    final faviconUrl = iconEl?.attributes['src']?.trim() ?? '';

    // thumbnail:.thumbnail / .aspect-image img
    final thumbEl = asideEl.querySelector('img.thumbnail') ??
        asideEl.querySelector('.aspect-image img') ??
        asideEl.querySelector('.thumbnail');
    final thumbnailUrl = thumbEl?.attributes['src']?.trim() ?? '';

    // sourceName:.source a / .source
    final sourceEl = asideEl.querySelector('.source a') ??
        asideEl.querySelector('.source');
    final sourceName = sourceEl?.text.trim() ?? '';

    return OneboxNode(
      id: nextId(),
      kind: kind,
      url: url.isEmpty ? null : url,
      title: title.isEmpty ? null : title,
      description: description.isEmpty ? null : description,
      faviconUrl: faviconUrl.isEmpty ? null : faviconUrl,
      thumbnailUrl: thumbnailUrl.isEmpty ? null : thumbnailUrl,
      sourceName: sourceName.isEmpty ? null : sourceName,
      rawHtml: asideEl.outerHtml,
    );
  }

  /// 解析 `<details>` 为 DetailsNode。
  ///
  /// - summary:`<summary>` 子节点的 textContent(trim)
  /// - children:除 summary 外所有节点递归 _parseBlocks
  /// - initiallyOpen:`<details open>` 属性
  DetailsNode _parseDetails(
    dom.Element detailsEl,
    String Function() nextId,
    int Function() nextImageIndex,
  ) {
    final summaryEl = detailsEl.querySelector('summary');
    final summary = summaryEl?.text.trim() ?? '';

    // 收集非 summary 子节点用于递归解析
    final bodyNodes = <dom.Node>[];
    for (final c in detailsEl.nodes) {
      if (c is dom.Element && c.localName?.toLowerCase() == 'summary') {
        continue;
      }
      bodyNodes.add(c);
    }
    final children = _parseBlocks(bodyNodes, nextId, nextImageIndex);

    return DetailsNode(
      id: nextId(),
      summary: summary,
      children: children,
      initiallyOpen: detailsEl.attributes.containsKey('open'),
    );
  }

  /// 尝试把 `<blockquote>` 识别为 Obsidian Callout(`[!type](+|-)?`)。
  ///
  /// 命中条件:第一个直接子 `<p>` 的 textContent 首行(`<br>` 分割前)
  /// 匹配 `^\[!([^\]]+)\]([+-])?\s*(.*)`。匹配失败返回 null,由外层
  /// 回落到普通 BlockquoteNode。
  ///
  /// 命中后的处理:
  /// - kind:`CalloutKind.fromType(type.toLowerCase())`
  /// - foldable:`+ → true`,`- → false`,否则 null
  /// - title:首行剥掉 `[!type](+|-)?\s*` 后的剩余文本(空时 null)
  /// - children:
  ///   - 首段 `<br>` 后的剩余 inline → 一个新 ParagraphNode(若非空)
  ///   - 首段之后的所有兄弟节点 → 递归 _parseBlocks
  CalloutNode? _tryParseCallout(
    dom.Element blockquoteEl,
    String Function() nextId,
    int Function() nextImageIndex,
  ) {
    // 第一个直接子 <p>(不递归嵌套 blockquote 内的 p)
    dom.Element? firstP;
    var firstPIndex = -1;
    for (var i = 0; i < blockquoteEl.children.length; i++) {
      final c = blockquoteEl.children[i];
      if (c.localName?.toLowerCase() == 'p') {
        firstP = c;
        firstPIndex = i;
        break;
      }
    }
    if (firstP == null) return null;

    // 取首段 textContent,只看第一行(<br> 之前)做 callout 标记识别
    final firstParaHtml = firstP.innerHtml;
    final brMatch = RegExp(r'<br\s*/?>', caseSensitive: false)
        .firstMatch(firstParaHtml);
    final beforeBr = brMatch == null
        ? firstParaHtml
        : firstParaHtml.substring(0, brMatch.start);
    final firstLineText = beforeBr.replaceAll(RegExp(r'<[^>]*>'), '').trim();

    final match =
        RegExp(r'^\[!([^\]]+)\]([+-])?\s*(.*)').firstMatch(firstLineText);
    if (match == null) return null;

    final typeRaw = match.group(1)!.trim().toLowerCase();
    final foldMarker = match.group(2);
    final titleRaw = match.group(3)?.trim();
    final bool? foldable = switch (foldMarker) {
      '+' => true,
      '-' => false,
      _ => null,
    };

    // 收集首段 <br> 之后的剩余 inline(若有)→ 单独一个 ParagraphNode
    final childNodes = <dom.Node>[];
    if (brMatch != null) {
      // trim 掉 <br> 后的 leading/trailing 空白(典型 cooked 里 `<br>\n正文`,
      // 不 trim 的话 fragment.parse 产生的 TextNode 带头部 \n,渲染时占一
      // 整行空高度 — 视觉上 callout 标题和正文之间多一行空白)
      final afterBrHtml = firstParaHtml.substring(brMatch.end).trim();
      if (afterBrHtml.isNotEmpty) {
        // 用 fragment parse 让它产生跟原 DOM 一致的节点
        final frag = html_parser.parseFragment(afterBrHtml);
        childNodes.addAll(frag.nodes);
      }
    }

    // 首段之后的所有兄弟节点都加进 children DOM 流
    // (用 nodes 而非 children,以保留文本节点和其他 inline)
    final allNodes = blockquoteEl.nodes;
    // 找到首段在 nodes 中的位置(children 用的是 element-only 索引,
    // 这里需要 nodes 索引)
    var firstPNodeIndex = -1;
    var skipped = 0;
    for (var i = 0; i < allNodes.length; i++) {
      final n = allNodes[i];
      if (n is dom.Element && n.localName?.toLowerCase() == 'p') {
        if (skipped == firstPIndex) {
          firstPNodeIndex = i;
          break;
        }
        skipped++;
      }
    }
    if (firstPNodeIndex >= 0) {
      for (var i = firstPNodeIndex + 1; i < allNodes.length; i++) {
        childNodes.add(allNodes[i]);
      }
    }

    // 把首段剩余 inline + 后续节点 一起递归解析成 BlockNode
    // (剩余 inline 会被 _parseBlocks 收成 pendingInlines → ParagraphNode)
    final children = childNodes.isEmpty
        ? const <BlockNode>[]
        : _parseBlocks(childNodes, nextId, nextImageIndex);

    return CalloutNode(
      id: nextId(),
      kind: CalloutKind.fromType(typeRaw),
      typeRaw: typeRaw,
      title: (titleRaw == null || titleRaw.isEmpty) ? null : titleRaw,
      foldable: foldable,
      children: children,
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

  /// 从 `<div class="lightbox-wrapper">` 元素提取 ImageRun。
  ///
  /// 结构:
  ///   <div class="lightbox-wrapper">
  ///     <a class="lightbox" href="原图URL">
  ///       <img src="缩略图URL" alt="..." width=... height=...>
  ///       <div class="meta">...filename + 尺寸 + svg icons</div>
  ///     </a>
  ///   </div>
  ///
  /// 找不到内嵌 img 时返回 null(调用方应跳过)。
  ImageRun? _imageRunFromLightboxWrapper(
    dom.Element wrapperEl,
    int Function() nextImageIndex,
  ) {
    final img = wrapperEl.querySelector('a.lightbox > img') ??
        wrapperEl.querySelector('img');
    if (img == null) return null;
    final aEl = wrapperEl.querySelector('a.lightbox');
    final lightboxUrl = aEl?.attributes['href']?.trim();
    final src = img.attributes['src']?.trim() ?? '';
    final alt = img.attributes['alt']?.trim() ?? '';
    final w = double.tryParse(img.attributes['width'] ?? '');
    final h = double.tryParse(img.attributes['height'] ?? '');
    return ImageRun(
      src: src,
      alt: alt,
      width: w,
      height: h,
      indexInPost: nextImageIndex(),
      lightboxUrl: (lightboxUrl ?? '').isEmpty ? null : lightboxUrl,
    );
  }

  /// 解析 `<div class="d-image-grid">` 为 ImageGridNode。
  ///
  /// 形态:
  /// ```html
  /// <div class="d-image-grid" data-columns="3" data-mode="grid">
  ///   <div class="lightbox-wrapper">
  ///     <a class="lightbox" href="原图"><img src="缩略" width=.. height=..></a>
  ///   </div>
  ///   <img src="..." />  <!-- 也可能直接是裸 img -->
  /// </div>
  /// ```
  ///
  /// 处理:
  /// - `data-columns`:int 解析,默认 2(legacy 默认值)
  /// - `data-mode="carousel"` 或 class 含 `d-image-grid--carousel` →
  ///   [ImageGridMode.carousel],否则 [ImageGridMode.grid]
  /// - 收集所有后代 `<img>`,但跳过 emoji / avatar / thumbnail / yt 缩略图
  ///   (legacy `extractGridImages` 同套路 — 这些是 UI 占位非内容图)
  /// - lightbox-wrapper 包裹的 img → 复用 `_imageRunFromLightboxWrapper`
  ///   提取 lightboxUrl;裸 img → 直接 ImageRun(无 lightboxUrl)
  ImageGridNode _parseImageGrid(
    dom.Element gridEl,
    String Function() nextId,
    int Function() nextImageIndex,
  ) {
    final cols = int.tryParse(gridEl.attributes['data-columns'] ?? '') ?? 2;
    final mode = (gridEl.attributes['data-mode'] == 'carousel' ||
            gridEl.classes.contains('d-image-grid--carousel'))
        ? ImageGridMode.carousel
        : ImageGridMode.grid;

    final images = <ImageRun>[];
    // 已被 lightbox-wrapper 收过的 img,后续直接 img 遍历时要跳过去重
    final consumedImgs = <dom.Element>{};

    // 先扫 lightbox-wrapper(优先它们,这样能拿到 lightboxUrl)
    for (final wrapper in gridEl.querySelectorAll('div.lightbox-wrapper')) {
      final innerImg = wrapper.querySelector('a.lightbox > img') ??
          wrapper.querySelector('img');
      if (innerImg == null) continue;
      if (_isSkipImage(innerImg)) continue;
      final run = _imageRunFromLightboxWrapper(wrapper, nextImageIndex);
      if (run != null) {
        images.add(run);
        consumedImgs.add(innerImg);
      }
    }

    // 再扫剩余裸 img(不在已消费集合内)
    for (final img in gridEl.querySelectorAll('img')) {
      if (consumedImgs.contains(img)) continue;
      if (_isSkipImage(img)) continue;
      final src = img.attributes['src']?.trim() ?? '';
      if (src.isEmpty) continue;
      final alt = img.attributes['alt']?.trim() ?? '';
      final w = double.tryParse(img.attributes['width'] ?? '');
      final h = double.tryParse(img.attributes['height'] ?? '');
      images.add(ImageRun(
        src: src,
        alt: alt,
        width: w,
        height: h,
        indexInPost: nextImageIndex(),
      ));
    }

    return ImageGridNode(
      id: nextId(),
      images: List.unmodifiable(images),
      columns: cols,
      mode: mode,
    );
  }

  /// d-image-grid 内应跳过的图(emoji / 头像 / 缩略 / yt 占位等 UI 元素)。
  /// 对齐 legacy `extractGridImages` 的 skip list。
  bool _isSkipImage(dom.Element img) {
    final classes = img.classes;
    return classes.contains('emoji') ||
        classes.contains('avatar') ||
        classes.contains('thumbnail') ||
        classes.contains('ytp-thumbnail-image');
  }

  /// 解析 `<div class="lazy-video-container">` 为 LazyVideoNode。
  ///
  /// 形态(legacy lazy_video_builder.dart 同结构):
  /// ```html
  /// <div class="lazy-video-container"
  ///      data-provider-name="youtube"
  ///      data-video-id="abc"
  ///      data-video-title="标题"
  ///      data-video-start-time="1m30s">
  ///   <a class="title-link" href="https://youtube.com/watch?v=abc">
  ///     <img src="缩略图.jpg" />
  ///   </a>
  /// </div>
  /// ```
  ///
  /// 处理:
  /// - data-provider-name → LazyVideoProvider.fromName
  /// - data-video-id / data-video-title / data-video-start-time 直接提
  /// - 缩略图:取 div 内 `<img>` 的 src
  /// - 链接:取 `a.title-link` 的 href,fallback 到第一个 `<a>` 的 href
  LazyVideoNode _parseLazyVideo(
    dom.Element divEl,
    String Function() nextId,
  ) {
    final attrs = divEl.attributes;
    final provider = LazyVideoProvider.fromName(
      attrs['data-provider-name']?.trim() ?? '',
    );
    final videoId = attrs['data-video-id']?.trim() ?? '';
    final title = attrs['data-video-title']?.trim() ?? '';
    final startTime = attrs['data-video-start-time']?.trim() ?? '';

    final img = divEl.querySelector('img');
    final thumbnailUrl = img?.attributes['src']?.trim() ?? '';

    final titleA = divEl.querySelector('a.title-link') ??
        divEl.querySelector('a');
    final url = titleA?.attributes['href']?.trim() ?? '';

    return LazyVideoNode(
      id: nextId(),
      provider: provider,
      videoId: videoId,
      title: title,
      thumbnailUrl: thumbnailUrl,
      startTime: startTime,
      url: url,
    );
  }

  /// 解析 `<iframe>` 为 IframeNode(对齐 legacy
  /// `IframeAttributes.fromElement`)。
  ///
  /// - src 优先 `src`,fallback `data-src`(lazy 形态)
  /// - width/height tryParse
  /// - sandbox / allow 按空白 / 分号拆分
  /// - allowfullscreen:属性存在 / 值为 true / "" / allow 含 fullscreen
  /// - loading="lazy" → lazyLoad=true
  IframeNode _parseIframe(dom.Element el, String Function() nextId) {
    final attrs = el.attributes;

    final src = (attrs['src']?.trim().isNotEmpty == true
            ? attrs['src']
            : attrs['data-src']) ??
        '';
    final width = double.tryParse(attrs['width'] ?? '');
    final height = double.tryParse(attrs['height'] ?? '');
    final title = attrs['title']?.trim();

    final sandboxRaw = attrs['sandbox'];
    final sandboxFlags = sandboxRaw == null
        ? <String>{}
        : sandboxRaw
            .split(RegExp(r'\s+'))
            .where((s) => s.isNotEmpty)
            .toSet();

    final allowRaw = attrs['allow'];
    final allowFlags = allowRaw == null
        ? <String>{}
        : allowRaw
            .split(';')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toSet();

    final fullscreenAttr = attrs['allowfullscreen'];
    final allowFullscreen = attrs.containsKey('allowfullscreen') &&
            (fullscreenAttr == null ||
                fullscreenAttr == 'true' ||
                fullscreenAttr == '' ||
                fullscreenAttr == 'allowfullscreen') ||
        allowFlags.any((p) => p.startsWith('fullscreen'));

    final referrerPolicy = attrs['referrerpolicy']?.trim();
    final lazyLoad = attrs['loading']?.trim() == 'lazy';

    return IframeNode(
      id: nextId(),
      src: src,
      width: width,
      height: height,
      title: (title == null || title.isEmpty) ? null : title,
      sandboxFlags: sandboxFlags,
      allowFlags: allowFlags,
      allowFullscreen: allowFullscreen,
      referrerPolicy:
          (referrerPolicy == null || referrerPolicy.isEmpty) ? null : referrerPolicy,
      lazyLoad: lazyLoad,
      cssClasses: el.classes.toSet(),
    );
  }

  /// 解析 `<table>` 为 TableNode。
  ///
  /// 形态:
  /// - 含 `<thead><tr>...<th>...</th></tr></thead><tbody><tr>...</tr></tbody>`
  /// - 或只有 `<tbody><tr>...</tr></tbody>`
  /// - 或裸 `<tr>...</tr>`(无 thead/tbody)
  ///
  /// 处理:
  /// - thead 内每个 tr → header 行(cell.isHeader=true)
  /// - tbody / 裸 tr → body 行
  /// - cell.children = _parseBlocks(td/th.nodes)(支持 cell 内 inline +
  ///   嵌套 block;绝大多数 cell 就是单段 ParagraphNode)
  /// - columnCount = max(row.length)
  ///
  /// 返回 null:无任何 tr。
  TableNode? _parseTable(
    dom.Element tableEl,
    String Function() nextId,
    int Function() nextImageIndex,
  ) {
    final rows = <List<TableCellData>>[];
    var hasHeader = false;

    final theads = tableEl.getElementsByTagName('thead');
    if (theads.isNotEmpty) {
      hasHeader = true;
      for (final tr in theads.first.getElementsByTagName('tr')) {
        rows.add(_parseTableRow(tr, nextId, nextImageIndex, forceHeader: true));
      }
    }

    final tbodies = tableEl.getElementsByTagName('tbody');
    if (tbodies.isNotEmpty) {
      for (final tr in tbodies.first.getElementsByTagName('tr')) {
        rows.add(_parseTableRow(tr, nextId, nextImageIndex));
      }
    } else if (theads.isEmpty) {
      // 裸 tr(无 thead/tbody)— 全当 body
      for (final tr in tableEl.getElementsByTagName('tr')) {
        rows.add(_parseTableRow(tr, nextId, nextImageIndex));
      }
    }

    if (rows.isEmpty) return null;

    final columnCount =
        rows.map((r) => r.length).reduce((a, b) => a > b ? a : b);
    if (columnCount == 0) return null;

    return TableNode(
      id: nextId(),
      rows: List.unmodifiable(rows.map(List<TableCellData>.unmodifiable)),
      columnCount: columnCount,
      hasHeader: hasHeader,
    );
  }

  /// 解析 `<tr>` 内的 `<th>` / `<td>`,每个 cell 走 _parseBlocks 递归。
  ///
  /// [forceHeader]:thead 内的 tr,即使是 `<td>` 也算 header。
  List<TableCellData> _parseTableRow(
    dom.Element tr,
    String Function() nextId,
    int Function() nextImageIndex, {
    bool forceHeader = false,
  }) {
    final cells = <TableCellData>[];
    for (final child in tr.children) {
      final tag = child.localName?.toLowerCase() ?? '';
      if (tag != 'th' && tag != 'td') continue;
      final isHeader = forceHeader || tag == 'th';
      final children = _parseBlocks(child.nodes, nextId, nextImageIndex);
      cells.add(TableCellData(
        children: List.unmodifiable(children),
        isHeader: isHeader,
      ));
    }
    return cells;
  }

  /// 把一个 inline element 转成 InlineNode 加入 out。
  void _collectInline(
    dom.Element el,
    List<InlineNode> out,
    int Function() nextImageIndex,
  ) {
    final tag = el.localName?.toLowerCase() ?? '';
    // 纯展示 / 占位元素:Discourse cooked 注入的 UI 图标 / 元数据容器,
    // 不参与文字流。不跳过会进 textContent 当文字渲染(出现 use href
    // 字面值 / filename 重复 / fa-... 占位文字 等)
    if (_isSkipElement(tag, el)) return;
    final children = <InlineNode>[];
    for (final child in el.nodes) {
      _collectInlineFromAnyNode(child, children, nextImageIndex);
    }
    switch (tag) {
      case 'em' || 'i':
        out.add(EmRun(children: List.unmodifiable(children)));
      case 'strong' || 'b':
        out.add(StrongRun(children: List.unmodifiable(children)));
      case 'br':
        out.add(const LineBreakRun());
      case 'ins':
        // 编辑历史 diff:`<ins>` 是新增。最简降级 = underline em。
        // legacy 用 .diff-ins 加绿底,留到阶段 2 优化。
        out.add(EmRun(children: List.unmodifiable(children)));
      case 'del' || 's':
        // 编辑历史 diff:`<del>` 是删除。最简降级 = strikethrough。
        // s 是 HTML5 的"不再相关"语义,视觉跟 del 一致。
        // 这里复用 EmRun 字段不合适,直接走"包裹文本"形态:展平 children
        // 加 line-through 是更准确,但 sealed 没"StrikethroughRun"节点。
        // 短期方案:展平内容,不加样式(留 inline 节点扩展给阶段 2)。
        out.addAll(children);
      case 'sup' || 'sub':
        // sup.footnote-ref 单独识别为 FootnoteRefRun(主项目可点弹脚注)。
        // 形态:<sup class="footnote-ref"><a href="#fn:abc">1</a></sup>
        if (tag == 'sup' && el.classes.contains('footnote-ref')) {
          final aEl = el.querySelector('a');
          final href = aEl?.attributes['href']?.trim() ?? '';
          // 取 a 文本作为编号(legacy 形态可能已是 "1" 也可能已是 "[1]")
          var number = (aEl?.text ?? '').trim();
          number = number.replaceAll(RegExp(r'^\[|\]$'), '');
          // fnId 从 href "#fn:abc" 提取
          final fnId = href.startsWith('#') ? href.substring(1) : '';
          if (number.isNotEmpty && fnId.isNotEmpty) {
            out.add(FootnoteRefRun(
              number: number,
              fnId: fnId,
              contentHtml: _footnotes[fnId],
            ));
            return;
          }
          // 解析失败 → 展平兜底
        }
        // 其他 <sup> / <sub>(化学式等):子包不支持 baseline 偏移,
        // 降级 = 展平内容,不上标(信息保留,视觉差一档)。
        out.addAll(children);
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
        final src = el.attributes['src']?.trim() ?? '';
        // class="emoji" 走 EmojiRun(行内表情图)
        if (el.classes.contains('emoji')) {
          // alt/title 里去掉首尾 `:`(Discourse 形如 `:heart:`)
          final raw = (el.attributes['title'] ?? el.attributes['alt'] ?? '').trim();
          final name = raw.replaceAll(RegExp(r'^:|:$'), '');
          out.add(EmojiRun(
            name: name,
            url: src,
            isOnlyEmoji: el.classes.contains('only-emoji'),
          ));
        } else {
          // 普通内容图片走 ImageRun(主项目注入 builder)
          final alt = el.attributes['alt']?.trim() ?? '';
          final w = double.tryParse(el.attributes['width'] ?? '');
          final h = double.tryParse(el.attributes['height'] ?? '');
          out.add(ImageRun(
            src: src,
            alt: alt,
            width: w,
            height: h,
            indexInPost: nextImageIndex(),
          ));
        }
      case 'span':
        // span.spoiler / span.spoiled → SpoilerRun
        if (el.classes.contains('spoiler') || el.classes.contains('spoiled')) {
          out.add(SpoilerRun(children: List.unmodifiable(children)));
          return;
        }
        // span.discourse-local-date → LocalDateRun(主项目接 builder 渲染
        // 真实带时区换算的 chip;子包 fallback 显示服务端预渲染文本)
        if (el.classes.contains('discourse-local-date')) {
          final attrs = el.attributes;
          final date = attrs['data-date']?.trim() ?? '';
          if (date.isEmpty) {
            // 无效:date 必填,降级展平
            out.addAll(children);
            return;
          }
          final time = attrs['data-time']?.trim();
          final timezone = attrs['data-timezone']?.trim();
          final timezonesRaw = attrs['data-timezones']?.trim() ?? '';
          final timezones = timezonesRaw.isEmpty
              ? const <String>[]
              : timezonesRaw
                  .split('|')
                  .map((s) => s.trim())
                  .where((s) => s.isNotEmpty)
                  .toList(growable: false);
          out.add(LocalDateRun(
            date: date,
            time: (time == null || time.isEmpty) ? null : time,
            timezone: (timezone == null || timezone.isEmpty) ? null : timezone,
            timezones: timezones,
            format: attrs['data-format']?.trim(),
            displayedTimezone: attrs['data-displayed-timezone']?.trim(),
            countdown: attrs.containsKey('data-countdown'),
            range: attrs['data-range']?.trim(),
            fallbackText: el.text.trim(),
          ));
          return;
        }
        // span.click-count → ClickCountRun(链接旁的点击数小 chip,
        // 纯展示节点;Discourse 用 _injectClickCounts 在 <a> 后注入)
        if (el.classes.contains('click-count')) {
          final raw = el.text.trim();
          // legacy 用 thin space ( ) 包数字,去掉首尾让数字纯净
          final count = raw.replaceAll(RegExp(r'^ | $'), '').trim();
          if (count.isNotEmpty) {
            out.add(ClickCountRun(count));
            return;
          }
        }
        // 其他 span 留后续阶段,当前展平
        out.addAll(children);
      default:
        // 未识别 inline:展平子节点
        out.addAll(children);
    }
  }

  /// 把任意 DOM 节点(文本 / inline element / 不该出现的块级)转成 InlineNode。
  void _collectInlineFromAnyNode(
    dom.Node node,
    List<InlineNode> out,
    int Function() nextImageIndex,
  ) {
    switch (node) {
      case dom.Text():
        final text = node.text;
        if (text.isNotEmpty) {
          out.add(TextRun(text));
        }
      case dom.Element():
        _collectInline(node, out, nextImageIndex);
      // 其他节点忽略
    }
  }

  /// 已支持的 inline 标签集合。
  static const _inlineTags = {'em', 'i', 'strong', 'b', 'br', 'a', 'code', 'img', 'span', 'ins', 'del', 's', 'sup', 'sub'};

  bool _isInlineTag(String tag) => _inlineTags.contains(tag);

  /// 判断元素是否应该**整体跳过**(不渲染、不取 textContent)。
  ///
  /// Discourse cooked 里有几类元素仅作 UI 占位,不该出现在文字流:
  /// - `<svg>`(d-icon / Discourse 自带图标 / lightbox 展开图标 等)
  /// - `.d-icon`(同上)
  /// - `.meta`(lightbox 的文件名 + 尺寸 + KB 容器,我们已用结构化字段)
  /// - `.lb-spacer`(legacy 给 lightbox 之间留间距的固定高度块)
  ///
  /// 不跳过时:
  /// - `<svg><use href="#far-image"/></svg>` 的 textContent 是空,但同
  ///   段落出现这个会让 paragraph 多出空 inline 噪音
  /// - `.meta` 的 `<span class="filename">hash</span><span class="informations">1686×128 15.7 KB</span>`
  ///   会被 fallback textContent 收成 "hash 1686×128 15.7 KB" 字符串,
  ///   就是用户截图里看到的乱码
  bool _isSkipElement(String tag, dom.Element el) {
    if (tag == 'svg') return true;
    final classes = el.classes;
    if (classes.contains('d-icon')) return true;
    if (classes.contains('meta')) return true;
    if (classes.contains('lb-spacer')) return true;
    return false;
  }

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
