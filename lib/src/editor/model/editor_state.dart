/// 编辑器文档状态与事务。
///
/// 设计:**不可变快照 + 事务栈**(对齐 ProseMirror 的 state/transaction,
/// 但简化为快照制 —— M1 文档规模是 composer 级,整表快照成本可忽略):
/// - 文档 = `List<ParagraphBlock>`(M1 只有段落;M2 扩展块类型);
/// - 每个编辑方法产生新快照并 push 历史;
/// - undo/redo = 历史栈上换快照;
/// - IME composing 是**状态而非内容**:composing 文本已实时进文档,
///   [composing] 只记录"当前段落里哪一段是未上屏预编辑"(画下划线用)。
///
/// 历史合并(seal):连续打字/composing 过程产生的快照合并为一个 undo 步,
/// [sealHistory] 在 composition 结束、结构操作(分段/合并/跨段删)、或
/// 空闲超时时调用。
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show TextRange;

import 'package:characters/characters.dart';
import 'package:flutter/foundation.dart';

import 'editable_text_content.dart';

/// 编辑器里的一个段落块:稳定 id + 扁平内容。
@immutable
class ParagraphBlock {
  const ParagraphBlock({required this.id, required this.content});

  final String id;
  final EditableTextContent content;

  ParagraphBlock copyWith({EditableTextContent? content}) =>
      ParagraphBlock(id: id, content: content ?? this.content);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ParagraphBlock &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          content == other.content;

  @override
  int get hashCode => Object.hash(id, content);

  @override
  String toString() => 'ParagraphBlock($id, "${content.text}")';
}

/// 编辑器光标/选区:块 id + 块内**编辑文本偏移**(不是渲染偏移 ——
/// M1 段落无原子占位时两者相等;渲染偏移换算在视图层做)。
@immutable
class EditorPosition {
  const EditorPosition({required this.blockId, required this.offset});

  final String blockId;
  final int offset;

  EditorPosition copyWith({String? blockId, int? offset}) => EditorPosition(
        blockId: blockId ?? this.blockId,
        offset: offset ?? this.offset,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EditorPosition &&
          runtimeType == other.runtimeType &&
          blockId == other.blockId &&
          offset == other.offset;

  @override
  int get hashCode => Object.hash(blockId, offset);

  @override
  String toString() => 'EditorPosition($blockId @$offset)';
}

@immutable
class EditorSelection {
  const EditorSelection({required this.base, required this.extent});

  const EditorSelection.collapsed(EditorPosition position)
      : base = position,
        extent = position;

  final EditorPosition base;
  final EditorPosition extent;

  bool get isCollapsed => base == extent;
  bool get isSingleBlock => base.blockId == extent.blockId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EditorSelection &&
          runtimeType == other.runtimeType &&
          base == other.base &&
          extent == other.extent;

  @override
  int get hashCode => Object.hash(base, extent);

  @override
  String toString() => 'EditorSelection($base → $extent)';
}

/// 历史快照(undo 单元)。
@immutable
class _HistoryEntry {
  const _HistoryEntry({required this.blocks, required this.selection});

  final List<ParagraphBlock> blocks;
  final EditorSelection? selection;
}

/// 编辑器状态机。
class EditorState extends ChangeNotifier {
  EditorState({required List<ParagraphBlock> blocks})
      : assert(blocks.isNotEmpty, '文档至少一个段落'),
        _blocks = List.unmodifiable(blocks);

  /// 便捷构造:从纯文本段落列表建文档。
  factory EditorState.fromTexts(List<String> paragraphs) {
    var counter = 0;
    final state = EditorState(
      blocks: [
        for (final t in (paragraphs.isEmpty ? [''] : paragraphs))
          ParagraphBlock(
            id: 'e_${counter++}',
            content: EditableTextContent(text: t),
          ),
      ],
    );
    state._idCounter = counter;
    return state;
  }

  List<ParagraphBlock> _blocks;
  List<ParagraphBlock> get blocks => _blocks;

  /// 文档修订号:每次 [_blocks] 快照替换 +1(选区/composing 变化不计)。
  /// 视图层用它区分「编辑引发的光标移动」(revision 变了 → 光标瞬时贴上,
  /// 否则快速打字时文字瞬排、光标 100ms 滑行,永远在追)与「纯导航」
  /// (revision 没变 → 平滑滑行)。
  int get docRevision => _docRevision;
  int _docRevision = 0;

  EditorSelection? _selection;
  EditorSelection? get selection => _selection;

  /// 当前段落内的 composing 区间(编辑文本坐标),null/collapsed = 无。
  TextRange _composing = TextRange.empty;
  TextRange get composing => _composing;

  bool get hasComposing =>
      _composing.isValid && !_composing.isCollapsed;

  int _idCounter = 0;
  String _nextId() => 'e_${_idCounter++}';

  // -----------------------------------------------------------------
  // 查询
  // -----------------------------------------------------------------

  int indexOfBlock(String blockId) =>
      _blocks.indexWhere((b) => b.id == blockId);

  ParagraphBlock? blockById(String blockId) {
    final i = indexOfBlock(blockId);
    return i < 0 ? null : _blocks[i];
  }

  /// 归一化选区:返回 (前位置, 后位置)(按文档序)。
  (EditorPosition, EditorPosition)? normalizedSelection() {
    final sel = _selection;
    if (sel == null) return null;
    final bi = indexOfBlock(sel.base.blockId);
    final ei = indexOfBlock(sel.extent.blockId);
    if (bi < 0 || ei < 0) return null;
    if (bi < ei || (bi == ei && sel.base.offset <= sel.extent.offset)) {
      return (sel.base, sel.extent);
    }
    return (sel.extent, sel.base);
  }

  // -----------------------------------------------------------------
  // 历史
  // -----------------------------------------------------------------

  final List<_HistoryEntry> _undoStack = [];
  final List<_HistoryEntry> _redoStack = [];

  /// 栈顶是否"未封口"(后续同类编辑并入该步)。
  bool _openGroup = false;

  /// 空闲自动封口:连续打字每次续期,停顿 [_sealIdleDelay] 后当前组
  /// 自动 seal —— undo 粒度 = 一阵输入(对齐主流编辑器),而非整个会话。
  Timer? _sealIdleTimer;
  static const Duration _sealIdleDelay = Duration(milliseconds: 800);

  static const int _maxHistory = 200;

  /// 在应用变更前记录当前状态。[groupWithPrevious] 为 true 且栈顶未封口
  /// 时不新增条目(连续打字合并为一步)。
  void _recordHistory({required bool groupWithPrevious}) {
    if (groupWithPrevious) {
      _sealIdleTimer?.cancel();
      _sealIdleTimer = Timer(_sealIdleDelay, sealHistory);
    }
    if (groupWithPrevious && _openGroup && _undoStack.isNotEmpty) {
      return;
    }
    _undoStack.add(_HistoryEntry(blocks: _blocks, selection: _selection));
    if (_undoStack.length > _maxHistory) _undoStack.removeAt(0);
    _redoStack.clear();
    _openGroup = groupWithPrevious;
  }

  /// 封口当前历史组(composition 结束/结构操作/空闲/点击时调用)。
  void sealHistory() {
    _sealIdleTimer?.cancel();
    _sealIdleTimer = null;
    _openGroup = false;
  }

  @override
  void dispose() {
    _sealIdleTimer?.cancel();
    super.dispose();
  }

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  void undo() {
    if (_undoStack.isEmpty) return;
    sealHistory();
    _redoStack.add(_HistoryEntry(blocks: _blocks, selection: _selection));
    final entry = _undoStack.removeLast();
    _blocks = entry.blocks;
    _docRevision++;
    // 历史里的选区可能指向已不存在的块/越界偏移(后续操作改过文档),
    // 必须 clamp —— 否则光标落在幽灵块上,IME/渲染全部错位。
    _selection = entry.selection == null
        ? null
        : _clampSelection(entry.selection!);
    _composing = TextRange.empty;
    notifyListeners();
  }

  void redo() {
    if (_redoStack.isEmpty) return;
    sealHistory();
    _undoStack.add(_HistoryEntry(blocks: _blocks, selection: _selection));
    final entry = _redoStack.removeLast();
    _blocks = entry.blocks;
    _docRevision++;
    _selection = entry.selection == null
        ? null
        : _clampSelection(entry.selection!);
    _composing = TextRange.empty;
    notifyListeners();
  }

  // -----------------------------------------------------------------
  // 选区/composing 更新(不产历史)
  // -----------------------------------------------------------------

  void updateSelection(EditorSelection? selection) {
    if (_selection == selection) return;
    _selection = selection == null ? null : _clampSelection(selection);
    // 选区跳走 = composition 语境失效。
    _composing = TextRange.empty;
    notifyListeners();
  }

  void updateComposing(TextRange range) {
    if (_composing == range) return;
    _composing = range;
    notifyListeners();
  }

  EditorSelection _clampSelection(EditorSelection sel) {
    EditorPosition clampPos(EditorPosition p) {
      final block = blockById(p.blockId);
      if (block == null) {
        final last = _blocks.last;
        return EditorPosition(blockId: last.id, offset: last.content.length);
      }
      return EditorPosition(
        blockId: p.blockId,
        offset: p.offset.clamp(0, block.content.length),
      );
    }

    return EditorSelection(base: clampPos(sel.base), extent: clampPos(sel.extent));
  }

  // -----------------------------------------------------------------
  // 事务(每个都:记历史 → 产新快照 → 设新选区 → notify)
  // -----------------------------------------------------------------

  void _commit(
    List<ParagraphBlock> newBlocks,
    EditorSelection? newSelection, {
    required bool groupWithPrevious,
    TextRange composing = TextRange.empty,
  }) {
    _recordHistory(groupWithPrevious: groupWithPrevious);
    _blocks = List.unmodifiable(newBlocks);
    _docRevision++;
    _selection = newSelection == null ? null : _clampSelection(newSelection);
    _composing = composing;
    notifyListeners();
  }

  /// 折叠光标处插入文本(打字主路径;选区非折叠时先删)。
  void insertText(String inserted) {
    final norm = normalizedSelection();
    if (norm == null || inserted.isEmpty) return;
    if (!(_selection?.isCollapsed ?? true)) {
      deleteSelection();
    }
    final pos = _selection!.extent;
    final i = indexOfBlock(pos.blockId);
    if (i < 0) return;
    final block = _blocks[i];
    final newBlocks = [..._blocks];
    newBlocks[i] =
        block.copyWith(content: block.content.insert(pos.offset, inserted));
    _commit(
      newBlocks,
      EditorSelection.collapsed(
        pos.copyWith(offset: pos.offset + inserted.length),
      ),
      groupWithPrevious: true,
    );
  }

  /// IME 主路径:替换 [blockId] 块内 `[start, end)` 为 [replacement],
  /// 光标置于 [caretOffset],composing 透传。
  ///
  /// `start == end && replacement.isEmpty` = 纯选区/composing 更新
  /// (IME 移动光标 / 仅更新 composing 标记),**不记历史**。
  void imeReplace(
    String blockId,
    int start,
    int end,
    String replacement, {
    required int caretOffset,
    TextRange composing = TextRange.empty,
  }) {
    final i = indexOfBlock(blockId);
    if (i < 0) return;
    final block = _blocks[i];
    final safeStart = start.clamp(0, block.content.length);
    final safeEnd = end.clamp(safeStart, block.content.length);
    final isTextChange = safeStart != safeEnd || replacement.isNotEmpty;

    if (!isTextChange) {
      _selection = _clampSelection(EditorSelection.collapsed(
        EditorPosition(blockId: blockId, offset: caretOffset),
      ));
      _composing = composing;
      notifyListeners();
      return;
    }

    _recordHistory(groupWithPrevious: true);
    final newBlocks = [..._blocks];
    newBlocks[i] = block.copyWith(
      content: block.content.replace(safeStart, safeEnd, replacement),
    );
    _blocks = List.unmodifiable(newBlocks);
    _docRevision++;
    _selection = _clampSelection(EditorSelection.collapsed(
      EditorPosition(blockId: blockId, offset: caretOffset),
    ));
    _composing = composing;
    notifyListeners();
  }

  /// 删除当前选区(跨段支持:首尾段残余合并,中间段整删)。
  void deleteSelection() {
    final norm = normalizedSelection();
    if (norm == null) return;
    final (from, to) = norm;
    if (_selection!.isCollapsed) return;
    sealHistory(); // 显式删除是独立 undo 步

    final fi = indexOfBlock(from.blockId);
    final ti = indexOfBlock(to.blockId);
    if (fi < 0 || ti < 0) return;

    final newBlocks = <ParagraphBlock>[];
    if (fi == ti) {
      final block = _blocks[fi];
      newBlocks
        ..addAll(_blocks.sublist(0, fi))
        ..add(block.copyWith(
          content: block.content.delete(from.offset, to.offset),
        ))
        ..addAll(_blocks.sublist(fi + 1));
    } else {
      final head = _blocks[fi].content.delete(
            from.offset, _blocks[fi].content.length);
      final tail = _blocks[ti].content.delete(0, to.offset);
      newBlocks
        ..addAll(_blocks.sublist(0, fi))
        ..add(_blocks[fi].copyWith(content: head.concat(tail)))
        ..addAll(_blocks.sublist(ti + 1));
    }
    _commit(
      newBlocks,
      EditorSelection.collapsed(from),
      groupWithPrevious: false,
    );
    sealHistory();
  }

  /// 光标前删一个字符(折叠态 Backspace;段首触发与上段合并)。
  ///
  /// 字符边界按 UTF-16 code unit 处理会撕裂代理对/emoji —— 用
  /// [String.characters] 语义:删除光标前一个 grapheme cluster。
  void backspace() {
    final sel = _selection;
    if (sel == null) return;
    if (!sel.isCollapsed) {
      deleteSelection();
      return;
    }
    final pos = sel.extent;
    final i = indexOfBlock(pos.blockId);
    if (i < 0) return;
    if (pos.offset == 0) {
      mergeWithPrevious(pos.blockId);
      return;
    }
    final block = _blocks[i];
    // 找光标前一个 grapheme 的起点
    final before = block.content.text.substring(0, pos.offset);
    final lastCluster = before.characters.isEmpty
        ? ''
        : before.characters.last;
    final delStart = pos.offset - lastCluster.length;
    final newBlocks = [..._blocks];
    newBlocks[i] =
        block.copyWith(content: block.content.delete(delStart, pos.offset));
    _commit(
      newBlocks,
      EditorSelection.collapsed(pos.copyWith(offset: delStart)),
      groupWithPrevious: true,
    );
  }

  /// 光标后删一个 grapheme(Forward Delete;段尾触发与下段合并)。
  void deleteForward() {
    final sel = _selection;
    if (sel == null) return;
    if (!sel.isCollapsed) {
      deleteSelection();
      return;
    }
    final pos = sel.extent;
    final i = indexOfBlock(pos.blockId);
    if (i < 0) return;
    final block = _blocks[i];
    if (pos.offset >= block.content.length) {
      // 段尾:把下一段并进来(光标停在 join 点 = 当前位置)。
      if (i + 1 < _blocks.length) mergeWithPrevious(_blocks[i + 1].id);
      return;
    }
    final after = block.content.text.substring(pos.offset);
    final step = after.characters.isEmpty ? 0 : after.characters.first.length;
    if (step == 0) return;
    final newBlocks = [..._blocks];
    newBlocks[i] = block.copyWith(
      content: block.content.delete(pos.offset, pos.offset + step),
    );
    _commit(
      newBlocks,
      EditorSelection.collapsed(pos),
      groupWithPrevious: true,
    );
  }

  /// 光标处回车分段。
  void splitParagraph() {
    final sel = _selection;
    if (sel == null) return;
    if (!sel.isCollapsed) deleteSelection();
    final pos = _selection!.extent;
    final i = indexOfBlock(pos.blockId);
    if (i < 0) return;
    sealHistory();
    final block = _blocks[i];
    final (before, after) = block.content.split(pos.offset);
    final newId = _nextId();
    final newBlocks = [..._blocks];
    newBlocks[i] = block.copyWith(content: before);
    newBlocks.insert(i + 1, ParagraphBlock(id: newId, content: after));
    _commit(
      newBlocks,
      EditorSelection.collapsed(EditorPosition(blockId: newId, offset: 0)),
      groupWithPrevious: false,
    );
    sealHistory();
  }

  /// [blockId] 段与上一段合并(段首退格)。首段无操作。
  void mergeWithPrevious(String blockId) {
    final i = indexOfBlock(blockId);
    if (i <= 0) return;
    sealHistory();
    final prev = _blocks[i - 1];
    final cur = _blocks[i];
    final joinOffset = prev.content.length;
    final newBlocks = [..._blocks];
    newBlocks[i - 1] = prev.copyWith(content: prev.content.concat(cur.content));
    newBlocks.removeAt(i);
    _commit(
      newBlocks,
      EditorSelection.collapsed(
        EditorPosition(blockId: prev.id, offset: joinOffset),
      ),
      groupWithPrevious: false,
    );
    sealHistory();
  }

  /// 全选。
  void selectAll() {
    final first = _blocks.first;
    final last = _blocks.last;
    updateSelection(EditorSelection(
      base: EditorPosition(blockId: first.id, offset: 0),
      extent: EditorPosition(blockId: last.id, offset: last.content.length),
    ));
  }

  /// 光标水平移动 ±1 grapheme(跨段自然衔接)。[extend] = shift 扩选。
  void moveCaretHorizontal(int direction, {bool extend = false}) {
    final sel = _selection;
    if (sel == null) return;
    // 非扩选且有选中范围:折叠到方向端点(主流编辑器语义)。
    if (!extend && !sel.isCollapsed) {
      final norm = normalizedSelection()!;
      updateSelection(
        EditorSelection.collapsed(direction < 0 ? norm.$1 : norm.$2),
      );
      return;
    }
    final pos = sel.extent;
    final i = indexOfBlock(pos.blockId);
    if (i < 0) return;
    final block = _blocks[i];
    EditorPosition? next;
    if (direction < 0) {
      if (pos.offset > 0) {
        final before = block.content.text.substring(0, pos.offset);
        final step = before.characters.isEmpty
            ? 1
            : before.characters.last.length;
        next = pos.copyWith(offset: pos.offset - step);
      } else if (i > 0) {
        final prev = _blocks[i - 1];
        next = EditorPosition(blockId: prev.id, offset: prev.content.length);
      }
    } else {
      if (pos.offset < block.content.length) {
        final after = block.content.text.substring(pos.offset);
        final step = after.characters.isEmpty
            ? 1
            : after.characters.first.length;
        next = pos.copyWith(offset: math.min(pos.offset + step, block.content.length));
      } else if (i + 1 < _blocks.length) {
        next = EditorPosition(blockId: _blocks[i + 1].id, offset: 0);
      }
    }
    if (next == null) return;
    updateSelection(
      extend
          ? EditorSelection(base: sel.base, extent: next)
          : EditorSelection.collapsed(next),
    );
  }
}
