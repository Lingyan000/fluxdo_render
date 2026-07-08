/// 编辑器组装件 —— M1 顶层 widget。
///
/// 职责:
/// - 持有编辑器**自己的** SelectionController/Registry(不走只读全局
///   coordinator 的手势层;高亮/命中/caret 几何复用同一套基建);
/// - 坐标桥接:EditorState 的 (blockId, 编辑文本偏移) ↔ 选区系统的
///   (SelectableBlockId(docOrder), 渲染偏移),经逻辑块表 projection 换算;
/// - 手势:tap 定位光标、拖动扩选;
/// - Focus + IME client 生命周期,帧后回喂光标几何;
/// - 光标 overlay(EditorCaret)。
library;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../node/node.dart' show InlineNode, LocalDateRun, TableNode;
import '../../render/block_text_styles.dart';
import '../../render/node_factory.dart';
import '../../selection/hit_tester.dart';
import '../../selection/selection_geometry.dart';
import '../../selection/selection_registry.dart';
import '../../selection/selection_scope.dart';
import '../input/editor_ime_client.dart';
import '../input/editor_key_handler.dart';
import '../model/editor_state.dart';
import 'editable_paragraph.dart';
import 'editor_caret.dart';
import 'editor_container_shell.dart';
import 'editor_island.dart';
import 'editor_table_grid.dart';

class FluxdoEditor extends StatefulWidget {
  const FluxdoEditor({
    super.key,
    required this.state,
    this.baseTextStyle,
    this.autofocus = false,
    this.nodeFactory,
    this.markdownImporter,
    this.onIslandEditRequest,
    this.onContainerTitleEdit,
    this.onTableEdited,
    this.onAtomTap,
  });

  final EditorState state;

  final TextStyle? baseTextStyle;

  final bool autofocus;

  /// 孤岛块的渲染工厂(主项目注入带 emoji/image builder 的实例;
  /// null 用子包默认 fallback —— demo/测试可用)。
  final NodeFactory? nodeFactory;

  /// 粘贴的 markdown → 编辑块导入器(主项目注入 cook 链路:
  /// markdown → cook → parse → blockNodesToDoc)。null / 返回 null 时
  /// 粘贴降级为纯文本(pastePlainText)。
  ///
  /// 剪贴板策略:复制/剪切写 markdown 文本(跨 app 通用、粘回自身经
  /// cook 还原富内容 —— Discourse 官方富文本 composer 同款语义)。
  final Future<List<EditorBlock>?> Function(String markdown)? markdownImporter;

  /// 双击岛 → 请求编辑(宿主弹源码对话框,改完调 state.replaceIsland)。
  /// null = 岛只读不可编辑。
  final void Function(IslandBlock island)? onIslandEditRequest;

  /// 点容器壳标题(details summary / callout 标题)→ 请求改标题
  /// (宿主弹输入框,改完调 state.updateContainerFrame)。null = 不可改。
  final void Function(ContainerFrame frame)? onContainerTitleEdit;

  /// 表格 cell 编辑确认 → 新 markdown 表格文本(宿主 cook 后
  /// state.replaceIsland)。null = 表格走通用只读岛。
  final void Function(IslandBlock island, String markdown)? onTableEdited;

  /// 单击可编辑原子(date chip)→ 请求编辑(宿主弹属性对话框,确认后
  /// state.replaceAtomAt)。null = 原子只读。
  final void Function(String blockId, int offset, InlineNode atom)? onAtomTap;

  @override
  State<FluxdoEditor> createState() => _FluxdoEditorState();
}

class _FluxdoEditorState extends State<FluxdoEditor> {
  late final SelectionController _controller;
  late final SelectionHitTester _hitTester;
  late final EditorImeClient _ime;
  late final NodeFactory _islandFactory;
  final FocusNode _focusNode = FocusNode(debugLabel: 'FluxdoEditor');
  final GlobalKey _rootKey = GlobalKey();

  /// 编辑器局部坐标系的光标矩形 + 配对修订号(帧后由 hit_tester 计算)。
  ///
  /// 用 ValueNotifier 而非 setState:光标位置每键都变,走整树 setState
  /// 会造成"每键两帧全量 build"(JANK 日志的第二帧 vsyncOverhead 20ms+
  /// 就是它);Notifier 只重建 caret overlay 一个叶子。修订号语义见
  /// EditorCaret.moveGeneration。
  final ValueNotifier<(Rect?, int)> _caretInfo = ValueNotifier((null, 0));

  @override
  void initState() {
    super.initState();
    _controller = SelectionController(SelectionRegistry());
    _hitTester = SelectionHitTester(_controller.registry);
    _ime = EditorImeClient(state: widget.state);
    _islandFactory = widget.nodeFactory ?? NodeFactory();
    widget.state.addListener(_onStateChanged);
    _focusNode.addListener(_onFocusChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _afterFrame());
  }

  @override
  void dispose() {
    _caretInfo.dispose();
    widget.state.removeListener(_onStateChanged);
    _ime.detach();
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  // -----------------------------------------------------------------
  // 状态联动
  // -----------------------------------------------------------------

  /// 编辑帧耗时插桩(debug;>8ms 打印,定位打字卡顿)。
  Stopwatch? _editFrameWatch;

  void _onStateChanged() {
    if (!mounted) return;
    if (kDebugMode) _editFrameWatch = Stopwatch()..start();
    // 外部变更(undo/redo 按钮、程序化改文档)→ IME 的 diff 基准已过期,
    // 必须重喂;IME 自身回调引发的通知、以及拖选进行中(高频选区变化,
    // 结束时 _onPanEnd 统一喂)除外。
    if (!_ime.isApplyingPlatformUpdate && _dragBase == null && _focusNode.hasFocus) {
      _ime.syncFromState(show: false);
    }
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) => _afterFrame());
  }

  void _onFocusChanged() {
    if (_focusNode.hasFocus) {
      // 重新聚焦(Tab / 键盘遍历 / 程序化 requestFocus):恢复光标可编辑。
      // 无选区时落到文档末尾(常规编辑器语义)。
      if (widget.state.selection == null) {
        final last = widget.state.blocks.last;
        widget.state.updateSelection(EditorSelection.collapsed(
          EditorPosition(blockId: last.id, offset: last.selectionLength),
        ));
      }
      _ime.syncFromState();
    } else {
      // 失焦:关 IME + 封历史口;清光标(选区保留 —— 用户可能是去点
      // 工具栏按钮,回来还在原处)。
      _ime.detach();
      widget.state.sealHistory();
    }
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) => _afterFrame());
  }

  /// 帧后:镜像选区给高亮层 + 重算光标矩形 + 回喂 IME 几何。
  void _afterFrame() {
    if (!mounted) return;
    final w = _editFrameWatch;
    if (w != null) {
      _editFrameWatch = null;
      w.stop();
      if (w.elapsedMilliseconds > 8) {
        debugPrint('[EditorPerf] edit frame ${w.elapsedMilliseconds}ms '
            '(blocks=${widget.state.blocks.length})');
      }
    }
    // 失焦时高亮层也清掉(选区数据保留在 EditorState,聚焦回来即恢复)。
    _controller.selection =
        _focusNode.hasFocus ? _toDocumentSelection(widget.state.selection) : null;

    final newCaret = _computeLocalCaretRect();
    if (newCaret != _caretInfo.value.$1) {
      _caretInfo.value = (newCaret, widget.state.docRevision);
    }

    final rootBox = _rootKey.currentContext?.findRenderObject();
    if (newCaret != null && rootBox is RenderBox && rootBox.hasSize) {
      _ime.updateEditableGeometry(
        size: rootBox.size,
        transform: rootBox.getTransformTo(null),
        caretRect: newCaret,
      );
    }
  }

  /// 岛是否处于「整选」态(选区恰覆盖该岛 0..1)。
  bool _isIslandSelected(String islandId) {
    final norm = widget.state.normalizedSelection();
    if (norm == null) return false;
    final (from, to) = norm;
    final fi = widget.state.indexOfBlock(from.blockId);
    final ti = widget.state.indexOfBlock(to.blockId);
    final ii = widget.state.indexOfBlock(islandId);
    if (fi < 0 || ti < 0 || ii < 0) return false;
    // 岛在选区块区间内;端点在岛上时按四象限(0=含,1=起于岛后)
    if (ii < fi || ii > ti) return false;
    if (ii == fi && from.blockId == islandId && from.offset >= 1) return false;
    if (ii == ti && to.blockId == islandId && to.offset <= 0) return false;
    return true;
  }

  // -----------------------------------------------------------------
  // 坐标桥接
  // -----------------------------------------------------------------

  SelectableBlockId _renderIdOf(int index) => SelectableBlockId(index);

  DocumentPosition? _toDocumentPosition(
    EditorPosition pos, {
    TextAffinity affinity = TextAffinity.downstream,
  }) {
    final index = widget.state.indexOfBlock(pos.blockId);
    if (index < 0) return null;
    // 岛不注册 RenderParagraph → 无 DocumentPosition(高亮/caret 均由
    // EditorIsland 自绘选中态,不走选区几何)。
    if (widget.state.blocks[index] is IslandBlock) return null;
    final id = _renderIdOf(index);
    final proj = _controller.registry.logicalById(id)?.projection;
    final renderOffset =
        proj?.renderOffsetForContent(pos.offset) ?? pos.offset;
    return DocumentPosition(
      blockId: id,
      renderOffset: renderOffset,
      affinity: affinity,
    );
  }

  /// 跨岛选区的高亮镜像:端点在岛上时收缩到岛外邻文本块(文本部分高亮,
  /// 岛的选中态由 EditorIsland 自绘)。
  DocumentSelection? _toDocumentSelection(EditorSelection? sel) {
    if (sel == null || sel.isCollapsed) return null;
    final norm = widget.state.normalizedSelection();
    if (norm == null) return null;
    var (from, to) = norm;

    final blocks = widget.state.blocks;
    var fi = widget.state.indexOfBlock(from.blockId);
    var ti = widget.state.indexOfBlock(to.blockId);
    if (fi < 0 || ti < 0) return null;

    // from 端在岛上 → 前进到下一个文本块头
    while (fi <= ti && blocks[fi] is IslandBlock) {
      fi++;
      if (fi > ti) return null; // 纯岛选区:无文本高亮
      from = EditorPosition(blockId: blocks[fi].id, offset: 0);
    }
    // to 端在岛上 → 回退到上一个文本块尾
    while (ti >= fi && blocks[ti] is IslandBlock) {
      ti--;
      if (ti < fi) return null;
      to = EditorPosition(
        blockId: blocks[ti].id,
        offset: blocks[ti].selectionLength,
      );
    }

    final base = _toDocumentPosition(from);
    final extent = _toDocumentPosition(to);
    if (base == null || extent == null) return null;
    return DocumentSelection(base: base, extent: extent);
  }

  EditorPosition? _toEditorPosition(DocumentPosition pos) {
    final index = pos.blockId.docOrder;
    final blocks = widget.state.blocks;
    if (index < 0 || index >= blocks.length) return null;
    final proj = _controller.registry.logicalById(pos.blockId)?.projection;
    final offset =
        proj?.contentOffsetForRender(pos.renderOffset) ?? pos.renderOffset;
    return EditorPosition(blockId: blocks[index].id, offset: offset);
  }

  /// 编辑光标固定行高:按**光标所在块的有效样式**取 preferredLineHeight
  /// (heading 块光标更高)。缓存键 = (baseStyle, kind, level)。
  double _caretLineHeight = 16;
  (TextStyle, TextBlockKind, int)? _caretHeightKey;

  void _ensureCaretLineHeight(TextStyle base) {
    final sel = widget.state.selection;
    final block = sel == null
        ? null
        : widget.state.textBlockById(sel.extent.blockId);
    final kind = block?.kind ?? TextBlockKind.paragraph;
    final level = block?.headingLevel ?? 1;
    final key = (base, kind, level);
    if (_caretHeightKey == key) return;
    _caretHeightKey = key;
    final style = kind == TextBlockKind.heading
        ? headingStyleFor(base, level)
        : base;
    final painter = TextPainter(
      text: TextSpan(text: ' ', style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    _caretLineHeight = painter.preferredLineHeight;
    painter.dispose();
  }

  /// 光标位置的软换行归属侧:点击时取命中结果的 affinity(点第一行行末
  /// 就显示在行末,而不是跳到第二行行首);键盘移动/编辑后重置 downstream。
  TextAffinity _caretAffinity = TextAffinity.downstream;

  Rect? _computeLocalCaretRect() {
    final sel = widget.state.selection;
    if (sel == null || !sel.isCollapsed || !_focusNode.hasFocus) return null;
    final docPos = _toDocumentPosition(sel.extent, affinity: _caretAffinity);
    if (docPos == null) return null;
    final globalRect =
        _hitTester.editingCaretRectAt(docPos, lineHeight: _caretLineHeight);
    if (globalRect == null) return null;
    final rootBox = _rootKey.currentContext?.findRenderObject();
    if (rootBox is! RenderBox || !rootBox.attached) return null;
    final topLeft = rootBox.globalToLocal(globalRect.topLeft);
    return topLeft & globalRect.size;
  }

  // -----------------------------------------------------------------
  // 剪贴板
  // -----------------------------------------------------------------

  /// 复制:选区 → markdown 写系统剪贴板(跨 app 通用;粘回自身经
  /// markdownImporter 还原富内容)。
  void _clipboardCopy() {
    final md = widget.state.copySelectionAsMarkdown();
    if (md.isEmpty) return;
    Clipboard.setData(ClipboardData(text: md));
  }

  void _clipboardCut() {
    final md = widget.state.copySelectionAsMarkdown();
    if (md.isEmpty) return;
    Clipboard.setData(ClipboardData(text: md));
    widget.state.deleteSelection();
    _ime.syncFromState(show: false);
  }

  /// 粘贴序号:异步 cook 期间用户再按一次 Cmd+V / 继续打字时,旧结果
  /// 作废(防乱序插入)。
  int _pasteTicket = 0;

  Future<void> _clipboardPaste() async {
    final ticket = ++_pasteTicket;
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) return;
    if (!mounted || ticket != _pasteTicket) return;

    final importer = widget.markdownImporter;
    List<EditorBlock>? fragment;
    if (importer != null) {
      try {
        fragment = await importer(text);
      } catch (_) {
        fragment = null; // 导入失败降级纯文本
      }
      if (!mounted || ticket != _pasteTicket) return;
    }

    if (fragment != null && fragment.isNotEmpty) {
      widget.state.pasteBlocks(fragment);
    } else {
      widget.state.pastePlainText(text);
    }
    _ime.syncFromState(show: false);
  }

  // -----------------------------------------------------------------
  // 垂直光标移动(上下键)
  // -----------------------------------------------------------------

  /// goal column:连续上下移动时记住起始 x,途经短行不丢列位
  /// (所有编辑器的标准行为)。横向移动/点击/编辑时清空。
  double? _verticalGoalX;

  void _moveCaretVertical(int direction, {required bool extend}) {
    final sel = widget.state.selection;
    if (sel == null) return;
    final docPos = _toDocumentPosition(sel.extent);
    if (docPos == null) return;
    final caret =
        _hitTester.editingCaretRectAt(docPos, lineHeight: _caretLineHeight);
    if (caret == null) return;

    final goalX = _verticalGoalX ??= caret.center.dx;
    // 目标点:上一行/下一行的行内(半行高步进;positionAt 有最近块兜底,
    // 文档首尾越界会停在首/末行 —— 此时若位置没变说明到顶/到底)。
    final targetY = direction < 0
        ? caret.top - caret.height / 2
        : caret.bottom + caret.height / 2;
    final hit = _hitTester.positionAt(
      Offset(goalX, targetY),
      hitTestRoot: _rootKey.currentContext?.findRenderObject(),
    );
    if (hit == null) return;
    final next = _toEditorPosition(hit);
    if (next == null) return;

    // 到顶/到底:位置不变 → 跳到段首/文档端点(对齐系统编辑器)。
    if (next == sel.extent) {
      final blocks = widget.state.blocks;
      final idx = widget.state.indexOfBlock(sel.extent.blockId);
      if (idx < 0) return;
      final EditorPosition endpoint = direction < 0
          ? EditorPosition(blockId: blocks.first.id, offset: 0)
          : EditorPosition(
              blockId: blocks.last.id,
              offset: blocks.last.selectionLength,
            );
      if (endpoint == sel.extent) return;
      widget.state.updateSelection(
        extend
            ? EditorSelection(base: sel.base, extent: endpoint)
            : EditorSelection.collapsed(endpoint),
      );
      _ime.syncFromState(show: false);
      return;
    }

    widget.state.updateSelection(
      extend
          ? EditorSelection(base: sel.base, extent: next)
          : EditorSelection.collapsed(next),
    );
    _ime.syncFromState(show: false);
  }

  // -----------------------------------------------------------------
  // 手势
  // -----------------------------------------------------------------

  /// 命中 → 编辑位置;顺带带出命中侧 affinity(软换行行末/行首)。
  (EditorPosition, TextAffinity)? _hitAtGlobal(Offset global) {
    final pos = _hitTester.positionAt(
      global,
      hitTestRoot: _rootKey.currentContext?.findRenderObject(),
    );
    if (pos == null) return null;
    final editor = _toEditorPosition(pos);
    if (editor == null) return null;
    return (editor, pos.affinity);
  }

  EditorPosition? _positionAtGlobal(Offset global) => _hitAtGlobal(global)?.$1;

  void _onTapDown(TapDownDetails details) {
    final hit = _hitAtGlobal(details.globalPosition);
    _focusNode.requestFocus();
    if (hit == null) return;
    _verticalGoalX = null;
    _caretAffinity = hit.$2;
    widget.state.sealHistory();
    widget.state.updateSelection(EditorSelection.collapsed(hit.$1));
    _ime.syncFromState();

    // 可编辑原子(date chip)单击 → 请求编辑(对齐官方:chip 是节点,
    // 点击/工具栏弹 modal 改属性)。命中位置左右各探一格:tap 落点在
    // 原子字符两侧边界都算点中它。
    final onAtomTap = widget.onAtomTap;
    if (onAtomTap == null) return;
    final block = widget.state.textBlockById(hit.$1.blockId);
    if (block == null) return;
    for (final off in [hit.$1.offset, hit.$1.offset - 1]) {
      if (off < 0) continue;
      final atom = block.content.atoms[off];
      if (atom is LocalDateRun) {
        onAtomTap(hit.$1.blockId, off, atom);
        return;
      }
    }
  }

  EditorPosition? _dragBase;

  void _onPanStart(DragStartDetails details) {
    _dragBase = _positionAtGlobal(details.globalPosition);
    _focusNode.requestFocus();
  }

  void _onPanUpdate(DragUpdateDetails details) {
    final base = _dragBase;
    if (base == null) return;
    final extent = _positionAtGlobal(details.globalPosition);
    if (extent == null) return;
    widget.state.updateSelection(
      EditorSelection(base: base, extent: extent),
    );
  }

  void _onPanEnd(DragEndDetails details) {
    _dragBase = null;
    _ime.syncFromState(show: false);
  }

  // -----------------------------------------------------------------
  // build
  // -----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final baseStyle = widget.baseTextStyle ??
        Theme.of(context).textTheme.bodyMedium ??
        const TextStyle(fontSize: 14);
    _ensureCaretLineHeight(baseStyle);

    final composingBlockId =
        state.hasComposing ? state.selection?.extent.blockId : null;

    // 有序列表序号(派生渲染态):连续 listItem run 内扫描,run 首项取
    // listStart;ordered/depth 切换重新起算(同 depth 的 ol 连续编号)。
    final ordinals = List<int>.filled(state.blocks.length, 1);
    final counters = <(bool, int), int>{}; // (ordered,depth) → 下一序号
    for (var i = 0; i < state.blocks.length; i++) {
      final b = state.blocks[i];
      if (b is! TextBlock || !b.isListItem) {
        counters.clear();
        continue;
      }
      final key = (b.ordered, b.depth);
      final next = counters[key] ?? b.listStart;
      ordinals[i] = next;
      counters[key] = next + 1;
      // 更浅层计数不清(嵌套子列表结束回到父层继续编号);更深层清零
      counters.removeWhere((k, _) => k.$2 > b.depth);
    }

    /// 单块 → widget(文本段落/岛)。
    ///
    /// 外层 Padding **必须带 key**:顶层/壳内 Column 的 children 是
    /// keyed(壳)与块混合列表,unkeyed 块会被 updateChildren 按位置
    /// 配对 —— 弹层/插块后旧岛 Padding 与新位置段落 Padding 错配,
    /// child 类型不同导致岛整棵 deactivate 重建(真机 hover/滚动态下
    /// 深层 InheritedElement dependents 清理时序炸 _dependents 断言,
    /// 红屏)。全 keyed 后 diff 恒按身份匹配,块只随真实删除而摘除。
    Widget buildBlock(int i) {
      final block = state.blocks[i];
      // 表格岛 + 宿主接了 onTableEdited:cell 级原位编辑网格
      // (不走 EditorIsland 的 AbsorbPointer 只读壳)
      if (block is IslandBlock &&
          block.node is TableNode &&
          widget.onTableEdited != null) {
        return Padding(
          key: ValueKey('blk_${block.id}'),
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: EditorTableGrid(
            key: ValueKey('table_${block.id}'),
            node: block.node as TableNode,
            onChanged: (md) => widget.onTableEdited!(block, md),
          ),
        );
      }
      return Padding(
        key: ValueKey('blk_${state.blocks[i].id}'),
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: switch (state.blocks[i]) {
          // key 绑块 id:分段/合并时 Element 正确复用/重建
          final TextBlock tb => EditableParagraph(
              key: ValueKey(tb.id),
              block: tb,
              documentOrder: i,
              baseStyle: baseStyle,
              composing: tb.id == composingBlockId
                  ? state.composing
                  : TextRange.empty,
              listMarkerOrdinal: ordinals[i],
            ),
          // 孤岛:NodeFactory 渲染,tap 整选,双击请求编辑,选中态描边
          final IslandBlock ib => EditorIsland(
              key: ValueKey(ib.id),
              node: ib.node,
              nodeFactory: _islandFactory,
              selected: _isIslandSelected(ib.id),
              onTapSelect: () {
                _focusNode.requestFocus();
                widget.state.sealHistory();
                widget.state.updateSelection(EditorSelection(
                  base: EditorPosition(blockId: ib.id, offset: 0),
                  extent: EditorPosition(blockId: ib.id, offset: 1),
                ));
                _ime.syncFromState(show: false);
              },
              onEditRequest: widget.onIslandEditRequest == null
                  ? null
                  : () => widget.onIslandEditRequest!(ib),
            ),
        },
      );
    }

    /// 递归分组(M5-B):`[from, to)` 内容器栈深度 [level] 上的分组渲染。
    /// 相邻块 containers[level] 相等 → 同容器实例,包 EditorContainerShell
    /// 后递归下一层;无该层帧 → 直接渲染块本体。
    List<Widget> buildLevel(int from, int to, int level) {
      final out = <Widget>[];
      var i = from;
      while (i < to) {
        final b = state.blocks[i];
        final frames = b is TextBlock ? b.containers : const <ContainerFrame>[];
        if (frames.length > level) {
          final frame = frames[level];
          final runStart = i;
          while (i < to) {
            final c = state.blocks[i];
            final cf = c is TextBlock ? c.containers : const <ContainerFrame>[];
            if (cf.length > level && cf[level] == frame) {
              i++;
            } else {
              break;
            }
          }
          out.add(Padding(
            // 容器壳自身与外界的间距(块本体的 vertical 4 在壳内)。
            // key 在 Padding 上(children 列表的直接成员必须 keyed,
            // 见 buildBlock 注释)。
            key: ValueKey('shell_${frame.groupId}_$level'),
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: EditorContainerShell(
              frame: frame,
              onTitleTap: widget.onContainerTitleEdit != null &&
                      (frame is DetailsFrame || frame is CalloutFrame)
                  ? () => widget.onContainerTitleEdit!(frame)
                  : null,
              children: buildLevel(runStart, i, level + 1),
            ),
          ));
          continue;
        }
        out.add(buildBlock(i));
        i++;
      }
      return out;
    }

    final children = buildLevel(0, state.blocks.length, 0);

    return Focus(
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      onKeyEvent: (node, event) {
        // 非上下键的任何按键动作都终结 goal column 记忆
        if (event is KeyDownEvent &&
            event.logicalKey != LogicalKeyboardKey.arrowUp &&
            event.logicalKey != LogicalKeyboardKey.arrowDown) {
          _verticalGoalX = null;
        }
        // 键盘操作后光标回 downstream(点击行末的 upstream 只对那次点击有效)
        if (event is KeyDownEvent) {
          _caretAffinity = TextAffinity.downstream;
        }
        return handleEditorKeyEvent(
          state,
          event,
          onEdited: () => _ime.syncFromState(show: false),
          onMoveVertical: _moveCaretVertical,
          onClipboardCopy: _clipboardCopy,
          onClipboardCut: _clipboardCut,
          onClipboardPaste: _clipboardPaste,
        );
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.text,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: _onTapDown,
          onPanStart: _onPanStart,
          onPanUpdate: _onPanUpdate,
          onPanEnd: _onPanEnd,
          child: SelectionScope(
            controller: _controller,
            child: Stack(
              key: _rootKey,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children,
                ),
                ValueListenableBuilder<(Rect?, int)>(
                  valueListenable: _caretInfo,
                  builder: (context, info, _) => EditorCaret(
                    caretRect: info.$1,
                    color: Theme.of(context).colorScheme.primary,
                    alwaysVisible: state.hasComposing,
                    moveGeneration: info.$2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
