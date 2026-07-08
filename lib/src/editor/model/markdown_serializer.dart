/// 编辑文档 → raw markdown 序列化(提交/草稿/双模切换用)。
///
/// 目标是产出**能被 Discourse cook 还原为等价 cooked** 的 markdown ——
/// 不追求与原始输入逐字节一致(markdown 表达同一结构有多种写法),
/// 追求 cook 后语义等价。
///
/// 与 doc_converter 的关系:doc_converter 是 doc ↔ BlockNode(结构层),
/// 本文件是 doc → markdown 文本(表示层)。markdown → doc 反方向走
/// cook(JS bundle)→ parse → blockNodesToDoc,不在子包内。
library;

import 'dart:ui' show Color;

import '../../node/node.dart';
import 'editable_text_content.dart';
import 'editor_block.dart';

/// 整篇文档 → markdown。
String docToMarkdown(List<EditorBlock> doc) {
  final chunks = <String>[];
  var i = 0;
  while (i < doc.length) {
    final block = doc[i];

    if (block is TextBlock && block.quoteDepth > 0) {
      // 连续 quote run 作为一个 chunk:块间用 `>` 前缀空行连接(裸空行
      // 会把一个 blockquote 劈成两个 —— cook 实测)。
      final run = <TextBlock>[];
      while (i < doc.length) {
        final b = doc[i];
        if (b is TextBlock && b.quoteDepth > 0) {
          run.add(b);
          i++;
        } else {
          break;
        }
      }
      chunks.add(_serializeQuoteRun(run));
      continue;
    }

    if (block is TextBlock && block.isListItem) {
      // 连续 listItem run 作为一个 chunk(项间单换行,序号连续计算)
      final run = <TextBlock>[];
      while (i < doc.length) {
        final b = doc[i];
        if (b is TextBlock && b.isListItem && b.quoteDepth == 0) {
          run.add(b);
          i++;
        } else {
          break;
        }
      }
      chunks.add(_serializeListRun(run));
      continue;
    }

    chunks.add(_serializeBlock(block));
    i++;
  }
  // 块间空行;过滤全空 chunk(如未知岛)后拼接
  return chunks.where((c) => c.isNotEmpty).join('\n\n');
}

String _serializeBlock(EditorBlock block) => switch (block) {
      final TextBlock tb => _serializeTextBlock(tb),
      final IslandBlock ib => serializeIslandNode(ib.node),
    };

String _serializeTextBlock(TextBlock block) {
  var text = _inlineToMarkdown(block.content);

  if (block.isHeading) {
    text = '${'#' * block.headingLevel} $text';
  }
  return text;
}

String _serializeListRun(List<TextBlock> run) {
  // 缩进规则(CommonMark):子列表缩进 = 各级祖先 marker 的**实际宽度**
  // 累计(`- ` 2 字符、`12. ` 4 字符)。固定 2 空格在 ol 下不够
  // (`1. ` 宽 3,2 空格缩进的"子项"会被解析回顶层 —— cook 实测)。
  // markerWidth[d] = 当前 depth d 项的 marker 宽;indent(d) = 前 d 级之和。
  final markerWidth = <int>[];
  int indentOf(int depth) {
    var sum = 0;
    for (var d = 0; d < depth && d < markerWidth.length; d++) {
      sum += markerWidth[d];
    }
    return sum;
  }

  // 顶层 ul/ol 切换 = 两个独立列表,必须空行分隔(单换行会被解析进
  // 前一个列表的延续上下文)。
  final segments = <List<String>>[];
  var lines = <String>[];
  bool? topOrdered;

  final counters = <(bool, int), int>{};
  for (final b in run) {
    if (b.depth == 0 && topOrdered != null && b.ordered != topOrdered) {
      segments.add(lines);
      lines = <String>[];
      counters.clear();
      markerWidth.clear();
    }
    if (b.depth == 0) topOrdered = b.ordered;

    final key = (b.ordered, b.depth);
    final ordinal = counters[key] ?? b.listStart;
    counters[key] = ordinal + 1;
    counters.removeWhere((k, _) => k.$2 > b.depth);

    final marker = b.ordered ? '$ordinal. ' : '- ';
    // 记录本级 marker 宽,裁掉更深层的过期记录
    if (markerWidth.length > b.depth) {
      markerWidth.removeRange(b.depth, markerWidth.length);
    }
    while (markerWidth.length < b.depth) {
      markerWidth.add(2); // 缺级兜底(悬空深项):按 ul 宽度
    }
    markerWidth.add(marker.length);

    final indent = ' ' * indentOf(b.depth);
    lines.add('$indent$marker${_inlineToMarkdown(b.content)}');
  }
  segments.add(lines);
  return segments
      .where((s) => s.isNotEmpty)
      .map((s) => s.join('\n'))
      .join('\n\n');
}

/// 连续 quoteDepth>0 run → 单个引用 chunk。
///
/// 关键(cook 实测):同一 blockquote 内的块间分隔必须是 **`>` 前缀空行**
/// (`> A\n>\n> B`)—— 裸空行(`> A\n\n> B`)会劈成两个相邻 blockquote,
/// 往返后结构漂移。深度不同的相邻块,分隔行用较浅侧深度的前缀
/// (`> 外\n>\n> > 内` 合并为嵌套,同样实测)。
String _serializeQuoteRun(List<TextBlock> run) {
  // 先按"连续 listItem(同 depth 组内自然连续)/单块"分组,组内不插空行
  final groups = <List<TextBlock>>[];
  for (final b in run) {
    if (b.isListItem &&
        groups.isNotEmpty &&
        groups.last.last.isListItem &&
        groups.last.last.quoteDepth == b.quoteDepth) {
      groups.last.add(b);
    } else {
      groups.add([b]);
    }
  }

  final lines = <String>[];
  int? prevDepth;
  for (final g in groups) {
    final depth = g.first.quoteDepth;
    if (prevDepth != null) {
      // 组间分隔:较浅侧深度的 `>` 空行(去尾空格)
      final sepDepth = depth < prevDepth ? depth : prevDepth;
      lines.add(('> ' * sepDepth).trimRight());
    }
    prevDepth = depth;

    if (g.first.isListItem) {
      final prefix = '> ' * depth;
      // 列表组:项间单换行,组内序号连续
      final body = _serializeListRun([
        for (final b in g) b.copyWith(quoteDepth: 0),
      ]);
      lines.addAll(body.split('\n').map((l) => '$prefix$l'));
    } else {
      final b = g.single;
      final prefix = '> ' * depth;
      var text = _inlineToMarkdown(b.content);
      if (b.isHeading) text = '${'#' * b.headingLevel} $text';
      lines.addAll(
          text.split('\n').map((l) => l.isEmpty ? prefix.trimRight() : '$prefix$l'));
    }
  }
  return lines.join('\n');
}

// ---------------------------------------------------------------------
// 行内序列化:扁平模型(text + marks + atoms)→ markdown 标记对
// ---------------------------------------------------------------------

/// mark 开/闭标记(嵌套固定序:spoiler > link > strong > em > underline >
/// lineThrough;inlineCode 独占由 toInlines 语义保证,这里同优先级处理即可)。
const _markOrder = [
  MarkKind.spoilerInline,
  MarkKind.link,
  MarkKind.strong,
  MarkKind.em,
  MarkKind.underline,
  MarkKind.lineThrough,
  MarkKind.inlineCode,
];

String _openTag(MarkSpan m, {required bool htmlEmphasis}) =>
    switch (m.kind) {
      MarkKind.strong => htmlEmphasis ? '<strong>' : '**',
      MarkKind.em => htmlEmphasis ? '<em>' : '*',
      MarkKind.inlineCode => '`',
      MarkKind.underline => '[u]',
      MarkKind.lineThrough => '~~',
      MarkKind.spoilerInline => '[spoiler]',
      MarkKind.link => '[',
    };

String _closeTag(MarkSpan m, {required bool htmlEmphasis}) =>
    switch (m.kind) {
      MarkKind.strong => htmlEmphasis ? '</strong>' : '**',
      MarkKind.em => htmlEmphasis ? '</em>' : '*',
      MarkKind.inlineCode => '`',
      MarkKind.underline => '[/u]',
      MarkKind.lineThrough => '~~',
      MarkKind.spoilerInline => '[/spoiler]',
      MarkKind.link => '](${m.attr ?? ''})',
    };

/// 是否存在交错区间(a.start < b.start < a.end < b.end)。
///
/// 交错时 LIFO 补闭重开会产生 `***`/`****` 之类的相邻同字符定界符,
/// CommonMark 贪婪匹配会破坏语义(cook 实测)。此时 strong/em 降级为
/// `<strong>/<em>` HTML 标签 —— cook sanitizer 放行且 cooked 结构与
/// markdown 定界符产物完全一致(实测),只是 raw 可读性略降(罕见路径)。
bool _hasCrossingMarks(List<MarkSpan> marks) {
  for (var i = 0; i < marks.length; i++) {
    for (var j = i + 1; j < marks.length; j++) {
      final a = marks[i];
      final b = marks[j];
      if (a.start < b.start && b.start < a.end && a.end < b.end) return true;
      if (b.start < a.start && a.start < b.end && b.end < a.end) return true;
    }
  }
  return false;
}

String _inlineToMarkdown(EditableTextContent content) {
  final text = content.text;
  if (text.isEmpty) return '';

  final htmlEmphasis = _hasCrossingMarks(content.marks);

  // 边界事件表:offset → 该处闭合/开启的 mark 区间
  final opens = <int, List<MarkSpan>>{};
  final closes = <int, List<MarkSpan>>{};
  for (final m in content.marks) {
    opens.putIfAbsent(m.start, () => []).add(m);
    closes.putIfAbsent(m.end, () => []).add(m);
  }

  final buf = StringBuffer();
  // 活动栈(开启顺序);闭合时按 LIFO 补闭到目标再重开(处理交错区间)
  final active = <MarkSpan>[];

  void emitCloses(int offset) {
    final toClose = closes[offset];
    if (toClose == null) return;
    // 需要闭合的集合;从栈顶弹到全部闭完,途中被迫闭合的重开
    final pending = [...toClose];
    final reopen = <MarkSpan>[];
    while (pending.isNotEmpty && active.isNotEmpty) {
      final top = active.removeLast();
      buf.write(_closeTag(top, htmlEmphasis: htmlEmphasis));
      if (!pending.remove(top)) reopen.add(top);
    }
    for (final m in reopen.reversed) {
      buf.write(_openTag(m, htmlEmphasis: htmlEmphasis));
      active.add(m);
    }
  }

  void emitOpens(int offset) {
    final toOpen = opens[offset];
    if (toOpen == null) return;
    // 固定序开启(spoiler/link 最外)
    final sorted = [...toOpen]
      ..sort((a, b) =>
          _markOrder.indexOf(a.kind).compareTo(_markOrder.indexOf(b.kind)));
    for (final m in sorted) {
      buf.write(_openTag(m, htmlEmphasis: htmlEmphasis));
      active.add(m);
    }
  }

  bool activeHas(MarkKind kind) => active.any((m) => m.kind == kind);

  var inCode = false;
  for (var i = 0; i <= text.length; i++) {
    emitCloses(i);
    if (i < text.length) {
      // code 状态跟踪(code 内不转义 markdown 元字符)
      inCode = activeHas(MarkKind.inlineCode);
    }
    emitOpens(i);
    if (i >= text.length) break;
    inCode = activeHas(MarkKind.inlineCode);

    final ch = text[i];
    if (ch == kAtomChar) {
      final atom = content.atoms[i];
      buf.write(switch (atom) {
        EmojiRun(:final name) => name.isEmpty ? '' : ':$name:',
        MentionRun(:final username) => '@$username',
        _ => '',
      });
    } else if (ch == '\n') {
      // 硬换行:行尾双空格
      buf.write('  \n');
    } else {
      buf.write(inCode ? ch : _escapeInline(ch, i, text));
    }
  }
  // 收尾:未闭合的全部闭合(理论 marks 都有 end,防御)
  while (active.isNotEmpty) {
    buf.write(_closeTag(active.removeLast(), htmlEmphasis: htmlEmphasis));
  }

  return _escapeLineStarts(buf.toString());
}

/// 行内元字符转义(对齐 ProseMirror defaultMarkdownSerializer.escape 口径:
/// 只转义会被 markdown 误解析的字符,不地毯式转义)。
String _escapeInline(String ch, int index, String text) {
  switch (ch) {
    case '[':
      // checklist 例外:`[x]`/`[X]`/`[ ]` 是 Discourse checklist 语法
      // (parser 把 span.chcklst-box 还原成这个字面量),转义会把勾选框
      // 变回纯文本。仅当后面不是 `(`(不会被误认成链接)时保留。
      if (_isChecklistAt(text, index)) return ch;
      return '\\$ch';
    case ']':
      if (index >= 2 && _isChecklistAt(text, index - 2)) return ch;
      return '\\$ch';
    case '*':
    case '_':
    case '`':
      return '\\$ch';
    case '~':
      // 只有连续两个 ~ 才是删除线,单个不转义
      final next = index + 1 < text.length ? text[index + 1] : '';
      final prev = index > 0 ? text[index - 1] : '';
      return (next == '~' || prev == '~') ? '\\$ch' : ch;
    default:
      return ch;
  }
}

/// [index] 处是否是 checklist 方框(`[x]`/`[X]`/`[ ]`,且其后非 `(`)。
bool _isChecklistAt(String text, int index) {
  if (index < 0 || index + 3 > text.length) return false;
  if (text[index] != '[' || text[index + 2] != ']') return false;
  final mid = text[index + 1];
  if (mid != 'x' && mid != 'X' && mid != ' ') return false;
  return index + 3 >= text.length || text[index + 3] != '(';
}

/// 行首元字符转义(#/>/-/+/数字. 在行首会被解析为块语法)。
String _escapeLineStarts(String text) {
  return text.split('\n').map((line) {
    final m = RegExp(r'^(\s*)([#>+-]|\d+[.)])(\s|$)').firstMatch(line);
    if (m == null) return line;
    final lead = m.group(1)!;
    final mark = m.group(2)!;
    return '$lead\\$mark${line.substring(lead.length + mark.length)}';
  }).join('\n');
}

// ---------------------------------------------------------------------
// 孤岛序列化(阅读端 BlockNode → markdown)
// ---------------------------------------------------------------------

/// 岛节点是否可无损序列化回 markdown。
///
/// false 的类型(poll 选项散在 cooked 结构里无法重建 / chat 客户端 cook
/// 不支持 / policy 属性名不定):序列化输出空串。**这不是静默丢内容**——
/// 编辑已有帖子的导入门禁(二次 cook 等价校验,见主项目 composer_doc_codec)
/// 会因 cooked 不等而拦下整帖,降级源码模式;编辑器内新建内容不会产生
/// 这些岛。
bool islandSerializable(BlockNode node) => switch (node) {
      PollNode() || ChatTranscriptNode() || PolicyNode() => false,
      _ => true,
    };

/// 单个岛节点 → markdown。
///
/// 目标形态 = **raw 的规范写法**(bbcode / markdown / 白名单 HTML),使
/// 「serialize 产物再 cook」与「原 raw 的 cook」等价。语法均经 cook bundle
/// 探针实测(details/spoiler/grid/quote/date/footnote/…)。
///
/// 公开 API:岛源码编辑(双击岛 → 对话框初值)与测试都用。
String serializeIslandNode(BlockNode node) {
  switch (node) {
    case ParagraphNode(:final inlines):
      return _serializeIslandInlines(inlines);
    case HeadingNode(:final level, :final inlines):
      return '${'#' * level} ${_serializeIslandInlines(inlines)}';
    case CodeBlockNode(:final code, :final language):
      final fence = code.contains('```') ? '````' : '```';
      return '$fence${language ?? ''}\n$code\n$fence';
    case HorizontalRuleNode():
      return '---';
    case BlankLineNode():
      return '';
    case MathBlockNode(:final latex):
      return '\$\$\n$latex\n\$\$';
    case OneboxNode(:final url):
      return url ?? '';
    case LazyVideoNode(:final url):
      // onebox 语义:裸 URL 独行(服务端重 cook 时自然 onebox 化)
      return url;
    case TableNode(:final rows, :final columnCount, :final hasHeader):
      return _serializeTable(rows, columnCount, hasHeader);
    case ListNode():
      return _serializeListNode(node, 0);
    case BlockquoteNode(:final children):
      final inner = children
          .map(serializeIslandNode)
          .where((s) => s.isNotEmpty)
          .join('\n\n');
      return inner.split('\n').map((l) => l.isEmpty ? '>' : '> $l').join('\n');
    case QuoteCardNode():
      return _serializeQuoteCard(node);
    case SpoilerBlockNode(:final children):
      final inner = children
          .map(serializeIslandNode)
          .where((s) => s.isNotEmpty)
          .join('\n\n');
      return '[spoiler]\n$inner\n[/spoiler]';
    case DetailsNode(:final summary, :final children, :final initiallyOpen):
      final inner = children
          .map(serializeIslandNode)
          .where((s) => s.isNotEmpty)
          .join('\n\n');
      final summaryAttr = summary.isEmpty ? '' : '="$summary"';
      final openAttr = initiallyOpen ? ' open' : '';
      return '[details$summaryAttr$openAttr]\n$inner\n[/details]';
    case CalloutNode():
      return _serializeCallout(node);
    case ImageGridNode(:final images, :final mode):
      final body = images
          .map((img) => _serializeImageRun(img))
          .join('\n');
      final modeAttr =
          mode == ImageGridMode.carousel ? ' mode=carousel' : '';
      return '[grid$modeAttr]\n$body\n[/grid]';
    case FootnotesSectionNode(:final entries):
      return entries
          .map((e) =>
              '[^${e.number}]: ${_serializeIslandInlines(e.inlines)}')
          .join('\n\n');
    case VideoNode(:final src, :final origSrc):
      // upload:// 上传 → `![|video](短链)`;直链 → 裸 URL(onebox 语义)
      final upload = origSrc ??
          (src.startsWith('upload://') ? src : null);
      if (upload != null) return '![|video]($upload)';
      return src;
    case AudioNode(:final src, :final origSrc):
      final upload = origSrc ??
          (src.startsWith('upload://') ? src : null);
      if (upload != null) return '![|audio]($upload)';
      return src;
    case IframeNode():
      return _serializeIframe(node);
    case SvgNode(:final svgSource):
      // raw 里就是裸 svg HTML(服务端白名单放行;客户端 cook 会剥属性,
      // 编辑导入门禁自然拦下 —— 这里保真输出服务端形态)
      return svgSource;
    case DefinitionListNode(:final items):
      return _serializeDefinitionList(items);
    case PollNode() || ChatTranscriptNode() || PolicyNode():
      // 已知不可序列化(islandSerializable=false):选项/属性散在 cooked
      // 结构里无法无损重建 raw。空串 —— 导入门禁负责拦整帖(编辑器内
      // 也不可能新建这些岛)。
      return '';
  }
}

/// `[quote="user, post:N, topic:M, username:real, full:true"]` 重建。
///
/// raw 参数顺序对齐 Discourse composer 的 buildQuote:显示名在首位、
/// username: 只在有独立显示名时出现。cooked 属性由 cook 探针实测:
/// data-username / data-display-name / data-post / data-topic / data-full。
String _serializeQuoteCard(QuoteCardNode node) {
  final parts = <String>[];
  if (node.displayName != null) {
    parts.add(node.displayName!);
  } else if (node.username.isNotEmpty) {
    parts.add(node.username);
  }
  if (node.postNumber != null) parts.add('post:${node.postNumber}');
  if (node.topicId != null) parts.add('topic:${node.topicId}');
  if (node.displayName != null && node.username.isNotEmpty) {
    parts.add('username:${node.username}');
  }
  if (node.full) parts.add('full:true');

  final open = parts.isEmpty ? '[quote]' : '[quote="${parts.join(', ')}"]';
  final inner = node.children
      .map(serializeIslandNode)
      .where((s) => s.isNotEmpty)
      .join('\n\n');
  return '$open\n$inner\n[/quote]';
}

/// Obsidian callout:`> [!type](+|-)? 标题` + 正文各行 `> ` 前缀。
String _serializeCallout(CalloutNode node) {
  final fold = switch (node.foldable) {
    true => '+',
    false => '-',
    null => '',
  };
  final title = (node.title ?? '').isEmpty ? '' : ' ${node.title}';
  final lines = <String>['> [!${node.typeRaw}]$fold$title'];
  final inner = node.children
      .map(serializeIslandNode)
      .where((s) => s.isNotEmpty)
      .join('\n\n');
  if (inner.isNotEmpty) {
    for (final l in inner.split('\n')) {
      lines.add(l.isEmpty ? '>' : '> $l');
    }
  }
  return lines.join('\n');
}

/// iframe 白名单 HTML 重建(raw 里就是裸 `<iframe>`;allowed_iframes
/// 命中才被 cook 放行,不命中的门禁自然拦)。
String _serializeIframe(IframeNode node) {
  final buf = StringBuffer('<iframe src="${node.src}"');
  if (node.width != null) {
    buf.write(' width="${_fmtNum(node.width!)}"');
  }
  if (node.height != null) {
    buf.write(' height="${_fmtNum(node.height!)}"');
  }
  if (node.title != null && node.title!.isNotEmpty) {
    buf.write(' title="${node.title}"');
  }
  if (node.allowFullscreen) buf.write(' allowfullscreen');
  if (node.allowFlags.isNotEmpty) {
    buf.write(' allow="${node.allowFlags.join('; ')}"');
  }
  if (node.sandboxFlags.isNotEmpty) {
    buf.write(' sandbox="${node.sandboxFlags.join(' ')}"');
  }
  if (node.referrerPolicy != null) {
    buf.write(' referrerpolicy="${node.referrerPolicy}"');
  }
  if (node.lazyLoad) buf.write(' loading="lazy"');
  buf.write('></iframe>');
  return buf.toString();
}

/// `<dl>` 白名单 HTML 重建(markdown 无 dl 语法,raw 里就是裸 HTML;
/// cook 探针实测原样放行)。
String _serializeDefinitionList(List<DefinitionItem> items) {
  final buf = StringBuffer('<dl>');
  for (final item in items) {
    if (item.term.isNotEmpty) {
      buf.write('<dt>${_serializeIslandInlines(item.term)}</dt>');
    }
    for (final dd in item.definitions) {
      final inner = dd
          .map(serializeIslandNode)
          .where((s) => s.isNotEmpty)
          .join('\n\n');
      buf.write('<dd>$inner</dd>');
    }
  }
  buf.write('</dl>');
  return buf.toString();
}

/// 数字属性:整数值不带小数点(690.0 → "690",与 raw 习惯一致)。
String _fmtNum(double v) =>
    v == v.roundToDouble() ? v.round().toString() : v.toString();

/// 图片 → `![alt|WxH](src)`。upload 图优先写 origSrc 短链(raw 规范形态);
/// lightbox 缩略图写原图短链/URL 而非 `_2_690x52` 优化版。
String _serializeImageRun(ImageRun img) {
  final src = img.origSrc ??
      (img.src.startsWith('upload://') ? img.src : (img.lightboxUrl ?? img.src));
  final size = (img.width != null && img.height != null)
      ? '|${img.width!.round()}x${img.height!.round()}'
      : '';
  return '![${img.alt}$size]($src)';
}

/// 岛化段落的 inline 序列化(可能含 LinkRun/ImageRun 等白名单外节点 ——
/// 岛就是因它们而生)。每个类型写回 raw 规范语法(cook 探针实测)。
String _serializeIslandInlines(List<InlineNode> inlines) {
  final buf = StringBuffer();
  for (final n in inlines) {
    switch (n) {
      case TextRun(:final text):
        buf.write(text);
      case LineBreakRun():
        buf.write('  \n');
      case EmRun(:final children):
        buf.write('*${_serializeIslandInlines(children)}*');
      case StrongRun(:final children):
        buf.write('**${_serializeIslandInlines(children)}**');
      case InlineCodeRun(:final text):
        buf.write('`$text`');
      case LinkRun(
          :final href,
          :final children,
          :final isAttachment,
          :final filename,
          :final origHref,
          :final hashtagRef,
          :final isOneboxLink,
        ):
        if (hashtagRef != null) {
          // hashtag 写回 `#{ref}`(写 URL 会退化成死链接)
          buf.write('#$hashtagRef');
        } else if (isAttachment) {
          // `[name.pdf|attachment](upload://…)`;origHref 是预览形态的
          // 短链,baked 形态 href 本身可能就是 /uploads 路径 —— 保持原样
          final target = origHref ?? href;
          final name =
              filename.isNotEmpty ? filename : _serializeIslandInlines(children);
          buf.write('[$name|attachment]($target)');
        } else if (isOneboxLink) {
          // onebox 系:raw 是裸 URL(行内标题动态取,不能固化)
          buf.write(href);
        } else {
          buf.write('[${_serializeIslandInlines(children)}]($href)');
        }
      case ImageRun():
        buf.write(_serializeImageRun(n));
      case EmojiRun(:final name):
        buf.write(name.isEmpty ? '' : ':$name:');
      case MentionRun(:final username):
        buf.write('@$username');
      case SpoilerRun(:final children):
        buf.write('[spoiler]${_serializeIslandInlines(children)}[/spoiler]');
      case MathInlineRun(:final latex):
        buf.write('\$$latex\$');
      case FootnoteRefRun(:final number):
        // 引用侧;脚注正文由 FootnotesSectionNode 输出 `[^N]: …`
        buf.write('[^$number]');
      case LocalDateRun():
        buf.write(_serializeLocalDate(n));
      case ColoredRun():
        // [color]/[bgcolor] BBCode 是 linux.do 未装插件的语法(cook 探针:
        // 原样输出文本);着色 span 只能来自服务端放行的 HTML —— 写回同形态
        buf.write(_serializeColored(n));
      case StyledRun(:final kind, :final children):
        final inner = _serializeIslandInlines(children);
        buf.write(switch (kind) {
          InlineStyleKind.underline => '[u]$inner[/u]',
          InlineStyleKind.lineThrough => '~~$inner~~',
          InlineStyleKind.superscript => '<sup>$inner</sup>',
          InlineStyleKind.subscript => '<sub>$inner</sub>',
          InlineStyleKind.small => '<small>$inner</small>',
          InlineStyleKind.big => '<big>$inner</big>',
          InlineStyleKind.mark => '<mark>$inner</mark>',
          InlineStyleKind.monospace => '<kbd>$inner</kbd>',
        });
      case ClickCountRun():
        break; // 服务端注入的展示节点,raw 里不存在
    }
  }
  return buf.toString();
}

/// `[date=… time=… timezone="…"]` BBCode 重建(cook 探针实测属性名)。
String _serializeLocalDate(LocalDateRun n) {
  final buf = StringBuffer('[date=${n.date}');
  if (n.time != null) buf.write(' time=${n.time}');
  if (n.timezone != null) buf.write(' timezone="${n.timezone}"');
  if (n.format != null) buf.write(' format="${n.format}"');
  if (n.timezones.isNotEmpty) {
    buf.write(' timezones="${n.timezones.join('|')}"');
  }
  if (n.displayedTimezone != null) {
    buf.write(' displayedTimezone="${n.displayedTimezone}"');
  }
  if (n.countdown) buf.write(' countdown="true"');
  buf.write(']');
  return buf.toString();
}

/// 着色 span 重建(`<span style="color:…">`,服务端 HTML 白名单形态)。
String _serializeColored(ColoredRun n) {
  String hex(Color c) {
    final v = c.toARGB32() & 0xFFFFFF;
    return '#${v.toRadixString(16).padLeft(6, '0')}';
  }

  final styles = <String>[
    if (n.color != null) 'color:${hex(n.color!)}',
    if (n.background != null) 'background-color:${hex(n.background!)}',
  ];
  final inner = _serializeIslandInlines(n.children);
  if (styles.isEmpty) return inner;
  return '<span style="${styles.join(';')}">$inner</span>';
}

String _serializeListNode(ListNode list, int depth) {
  final lines = <String>[];
  for (var i = 0; i < list.items.length; i++) {
    final item = list.items[i];
    final indent = '  ' * depth;
    final marker = list.ordered ? '${list.start + i}. ' : '- ';
    lines.add('$indent$marker${_serializeIslandInlines(item.inlines)}');
    for (final sub in item.children ?? const <ListNode>[]) {
      lines.add(_serializeListNode(sub, depth + 1));
    }
    // 块级子节点(岛化列表可能含):缩进后原样接
    for (final b in item.blocks ?? const <BlockNode>[]) {
      final s = serializeIslandNode(b);
      if (s.isNotEmpty) {
        lines.add(s.split('\n').map((l) => '$indent  $l').join('\n'));
      }
    }
  }
  return lines.join('\n');
}

String _serializeTable(
  List<List<TableCellData>> rows,
  int columnCount,
  bool hasHeader,
) {
  if (rows.isEmpty) return '';

  String cellText(TableCellData cell) => cell.children
      .map(serializeIslandNode)
      .where((s) => s.isNotEmpty)
      .join(' ')
      .replaceAll('\n', ' ')
      .replaceAll('|', r'\|');

  String rowLine(List<TableCellData> row) {
    final cells = [
      for (var c = 0; c < columnCount; c++)
        c < row.length ? cellText(row[c]) : '',
    ];
    return '| ${cells.join(' | ')} |';
  }

  final lines = <String>[];
  final divider = '| ${List.filled(columnCount, '---').join(' | ')} |';
  if (hasHeader) {
    lines.add(rowLine(rows.first));
    lines.add(divider);
    for (final row in rows.skip(1)) {
      lines.add(rowLine(row));
    }
  } else {
    // markdown 表格必须有 header 行;无 header 时补空头
    lines.add('| ${List.filled(columnCount, ' ').join(' | ')} |');
    lines.add(divider);
    for (final row in rows) {
      lines.add(rowLine(row));
    }
  }
  return lines.join('\n');
}
