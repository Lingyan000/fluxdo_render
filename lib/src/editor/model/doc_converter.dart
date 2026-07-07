/// 编辑文档 ↔ 阅读端 BlockNode 树 双向互转。
///
/// **零丢失原则**:
/// - 不可编辑的 inline(link/image/spoiler/... M2 暂不进编辑白名单)→
///   所在块**整体岛化**(IslandBlock 原引用直存),不做有损降级;
/// - 列表含块级子节点 / 引用内含不可编辑块 → 整棵树岛化(不拆半棵);
/// - IslandBlock 导出时原 node 引用直出(identity 保真)。
///
/// 列表/引用的树 ↔ 扁平转换:
/// - 导入:ListNode DFS 展平为连续 `TextBlock(listItem, depth)` run;
///   BlockquoteNode 递归展平,途经块 quoteDepth+1;
/// - 导出:连续 listItem run 深度栈重建 ListNode 树;连续 quoteDepth>0
///   run 递归包 BlockquoteNode。
library;

import '../../node/node.dart';
import 'editable_text_content.dart';
import 'editor_block.dart';

/// M2 编辑白名单:能进 TextBlock 的 inline 类型。
bool isEditableInline(InlineNode n) => switch (n) {
      TextRun() || LineBreakRun() || EmojiRun() || MentionRun() => true,
      EmRun(:final children) => children.every(isEditableInline),
      StrongRun(:final children) => children.every(isEditableInline),
      InlineCodeRun() => true,
      StyledRun(:final kind, :final children) => switch (kind) {
          InlineStyleKind.underline ||
          InlineStyleKind.lineThrough =>
            children.every(isEditableInline),
          _ => false,
        },
      _ => false,
    };

bool _allEditable(List<InlineNode> inlines) => inlines.every(isEditableInline);

/// 阅读端节点树 → 编辑文档。
///
/// [nextId]:块 id 分配器(EditorState 侧惯例 `e_N`)。
List<EditorBlock> blockNodesToDoc(
  List<BlockNode> nodes,
  String Function() nextId,
) {
  final out = <EditorBlock>[];

  void addIsland(BlockNode node) => out.add(IslandBlock(id: nextId(), node: node));

  void addText(
    EditableTextContent content, {
    TextBlockKind kind = TextBlockKind.paragraph,
    int headingLevel = 1,
    bool ordered = false,
    int depth = 0,
    int listStart = 1,
    int quoteDepth = 0,
  }) {
    out.add(TextBlock(
      id: nextId(),
      content: content,
      kind: kind,
      headingLevel: headingLevel,
      ordered: ordered,
      depth: depth,
      listStart: listStart,
      quoteDepth: quoteDepth,
    ));
  }

  /// 列表整树可编辑性:所有(递归)item 无块级子节点且 inlines 全过白名单。
  bool listEditable(ListNode list) {
    for (final item in list.items) {
      if (item.blocks != null) return false;
      if (!_allEditable(item.inlines)) return false;
      for (final sub in item.children ?? const <ListNode>[]) {
        if (!listEditable(sub)) return false;
      }
    }
    return true;
  }

  /// 展平列表(已验证可编辑)。首项带 listStart。
  void flattenList(ListNode list, int depth, int quoteDepth) {
    for (var i = 0; i < list.items.length; i++) {
      final item = list.items[i];
      addText(
        EditableTextContent.fromInlines(item.inlines),
        kind: TextBlockKind.listItem,
        ordered: list.ordered,
        depth: depth,
        listStart: i == 0 && depth == 0 ? list.start : 1,
        quoteDepth: quoteDepth,
      );
      for (final sub in item.children ?? const <ListNode>[]) {
        flattenList(sub, depth + 1, quoteDepth);
      }
    }
  }

  /// 引用整树可编辑性:children 全部是可编辑段落/标题/列表/嵌套引用/空行。
  bool quoteEditable(BlockquoteNode quote) {
    for (final child in quote.children) {
      final ok = switch (child) {
        ParagraphNode(:final inlines) => _allEditable(inlines),
        HeadingNode(:final inlines) => _allEditable(inlines),
        final ListNode list => listEditable(list),
        final BlockquoteNode nested => quoteEditable(nested),
        BlankLineNode() => true,
        _ => false,
      };
      if (!ok) return false;
    }
    return true;
  }

  void walk(BlockNode node, int quoteDepth) {
    switch (node) {
      case ParagraphNode(:final inlines):
        if (_allEditable(inlines)) {
          addText(EditableTextContent.fromInlines(inlines),
              quoteDepth: quoteDepth);
        } else {
          addIsland(node);
        }
      case HeadingNode(:final level, :final inlines):
        if (_allEditable(inlines)) {
          addText(
            EditableTextContent.fromInlines(inlines),
            kind: TextBlockKind.heading,
            headingLevel: level,
            quoteDepth: quoteDepth,
          );
        } else {
          addIsland(node);
        }
      case ListNode():
        if (listEditable(node)) {
          flattenList(node, node.depth, quoteDepth);
        } else {
          addIsland(node);
        }
      case BlockquoteNode(:final children):
        if (quoteEditable(node)) {
          for (final child in children) {
            walk(child, quoteDepth + 1);
          }
        } else {
          addIsland(node);
        }
      case BlankLineNode():
        addText(EditableTextContent.empty, quoteDepth: quoteDepth);
      default:
        addIsland(node);
    }
  }

  for (final node in nodes) {
    walk(node, 0);
  }
  // 注意:不在此补"至少一个 TextBlock"—— 那是 EditorState 的文档不变量
  // (其构造器自动补空段);converter 保持纯转换,否则全岛输入的往返
  // 会多出幽灵 BlankLineNode,破坏投影守恒。
  return out;
}

/// 编辑文档 → 阅读端节点树(给阅读端渲染/M3 markdown 序列化)。
List<BlockNode> docToBlockNodes(List<EditorBlock> doc) {
  var idCounter = 0;
  String nextId() => 'b_${idCounter++}';

  final out = <BlockNode>[];
  var i = 0;

  // 顶层游标推进;引用 run / 列表 run 由子函数消费连续段。
  while (i < doc.length) {
    final block = doc[i];

    if (block is IslandBlock) {
      out.add(block.node); // identity 直出
      i++;
      continue;
    }
    block as TextBlock;

    if (block.quoteDepth > 0) {
      // 连续 quoteDepth>0 run → 递归包 BlockquoteNode
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
      out.add(_buildQuote(run, 1, nextId));
      continue;
    }

    if (block.isListItem) {
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
      out.addAll(_buildLists(run, 0, nextId));
      continue;
    }

    out.add(_textBlockToNode(block, nextId));
    i++;
  }
  return out;
}

/// 单个非列表文本块 → 节点。
BlockNode _textBlockToNode(TextBlock block, String Function() nextId) {
  if (block.isHeading) {
    return HeadingNode(
      id: nextId(),
      level: block.headingLevel,
      inlines: _exportInlines(block),
    );
  }
  if (block.content.length == 0) {
    return BlankLineNode(id: nextId());
  }
  return ParagraphNode(id: nextId(), inlines: _exportInlines(block));
}

/// toInlines + only-emoji 还原:整块恰一个 emoji 原子(无其他内容)时
/// 标记 isOnlyEmoji(Discourse 大表情语义)。
List<InlineNode> _exportInlines(TextBlock block) {
  final inlines = block.content.toInlines();
  if (inlines.length == 1 && inlines.first is EmojiRun) {
    final e = inlines.first as EmojiRun;
    if (!e.isOnlyEmoji) {
      return [EmojiRun(name: e.name, url: e.url, isOnlyEmoji: true)];
    }
  }
  return inlines;
}

/// 连续 quoteDepth ≥ [level] 的 run → BlockquoteNode(递归处理更深层)。
BlockquoteNode _buildQuote(
  List<TextBlock> run,
  int level,
  String Function() nextId,
) {
  final children = <BlockNode>[];
  var i = 0;
  while (i < run.length) {
    final b = run[i];
    if (b.quoteDepth > level) {
      final deeper = <TextBlock>[];
      while (i < run.length && run[i].quoteDepth > level) {
        deeper.add(run[i]);
        i++;
      }
      children.add(_buildQuote(deeper, level + 1, nextId));
      continue;
    }
    if (b.isListItem) {
      final listRun = <TextBlock>[];
      while (i < run.length &&
          run[i].isListItem &&
          run[i].quoteDepth == level) {
        listRun.add(run[i]);
        i++;
      }
      children.addAll(_buildLists(listRun, 0, nextId));
      continue;
    }
    children.add(_textBlockToNode(b, nextId));
    i++;
  }
  return BlockquoteNode(id: nextId(), children: children);
}

/// 连续 listItem run(同 quoteDepth)→ ListNode 树(深度栈重建)。
///
/// 相邻同 depth 且 ordered 不同 → 关组开新列表(对齐 HTML ul/ol 分家)。
List<ListNode> _buildLists(
  List<TextBlock> run,
  int baseDepth,
  String Function() nextId,
) {
  final out = <ListNode>[];
  var i = 0;
  while (i < run.length) {
    final first = run[i];
    final ordered = first.ordered;
    final items = <ListItem>[];
    final start = first.listStart;

    while (i < run.length) {
      final b = run[i];
      if (b.depth < baseDepth) break;
      if (b.depth == baseDepth) {
        if (b.ordered != ordered) break; // ul/ol 分家
        i++;
        // 吞掉紧随其后的更深层(挂为本 item 的子列表)
        final deeper = <TextBlock>[];
        while (i < run.length && run[i].depth > baseDepth) {
          deeper.add(run[i]);
          i++;
        }
        items.add(ListItem(
          inlines: b.content.toInlines(),
          children: deeper.isEmpty
              ? null
              : _buildLists(deeper, baseDepth + 1, nextId),
        ));
      } else {
        // run 以更深层开头(缩进悬空):按提升到本层处理
        final deeper = <TextBlock>[];
        while (i < run.length && run[i].depth > baseDepth) {
          deeper.add(run[i]);
          i++;
        }
        final sublists = _buildLists(deeper, baseDepth + 1, nextId);
        items.add(ListItem(inlines: const [], children: sublists));
      }
    }

    out.add(ListNode(
      id: nextId(),
      ordered: ordered,
      items: items,
      depth: baseDepth,
      start: start,
    ));
  }
  return out;
}
