/// 表格岛的编辑态渲染(M5):cell 单击原位编辑 + Notion 式行列操作。
///
/// 替换通用 EditorIsland 的 AbsorbPointer 只读渲染 —— 表格是"结构化
/// 数据",cell 级直改比源码/对话框顺手一个量级:
/// - 自绘轻量表格(边框/表头底色对齐阅读端 table_builder 视觉);
/// - 单击 cell → cell 原位变 TextField(markdown 源码口径,富格式保留),
///   编辑态 primary 描边高亮;非编辑 cell hover 淡底提示可点;
/// - 行列操作(Notion 式):hover 行 → 左缘行柄,hover 列 → 顶缘列柄,
///   点柄弹菜单(前/后插入、删除);表格右缘/下缘 hover 出 [+] 加条;
/// - 提交(回车/失焦)→ 回调宿主重建 markdown → replaceIsland。
///
/// cell 内容口径 = tableCellToMarkdown(单行 markdown 文本;`**粗**`
/// 等富格式以源码显示,cook 后还原 —— 不丢格式)。
library;

import 'package:flutter/material.dart';

import '../../node/node.dart';
import '../model/markdown_serializer.dart';

/// 编辑器自管交互区的命中标记(MetaData.metaData):FluxdoEditor 的
/// tap/pan 手势命中带此标记的子树时完全让路 —— 区域内的焦点/光标/
/// 输入由子组件(表格 cell TextField)自己管,编辑器不抢焦点、不设
/// 选区、不弹 IME(否则双光标)。
const Object kEditorSelfManagedRegion = _SelfManagedRegionTag();

class _SelfManagedRegionTag {
  const _SelfManagedRegionTag();
}

/// 单 cell 宽度(整表统一;编辑态同宽防跳动)。
const double _kCellWidth = 132.0;

/// 行柄/列柄的厚度。
const double _kHandleThickness = 14.0;

/// 表格编辑网格。所有结构变更(改 cell/增删行列/表头开关)统一走
/// [onChanged](完整 markdown 表格文本)—— 宿主经 cook 链路替换岛。
class EditorTableGrid extends StatefulWidget {
  const EditorTableGrid({
    super.key,
    required this.node,
    required this.onChanged,
    this.selected = false,
    this.onSelectRequest,
  });

  final TableNode node;

  /// 变更后的 markdown 表格文本(cook → replaceIsland 由宿主做)。
  final ValueChanged<String> onChanged;

  /// 整选态(编辑器选区恰覆盖本表格块):primary 描边。
  final bool selected;

  /// 左上角选择柄点击 → 编辑器整选本表格块(选中后退格/Delete 删整表;
  /// cell 区自管让路后这是块级选择的唯一入口)。
  final VoidCallback? onSelectRequest;

  @override
  State<EditorTableGrid> createState() => _EditorTableGridState();
}

class _EditorTableGridState extends State<EditorTableGrid> {
  late List<List<String>> _cells;
  late bool _hasHeader;

  /// 正在编辑的 cell(row, col);null = 无。
  (int, int)? _editing;
  final TextEditingController _cellController = TextEditingController();
  final FocusNode _cellFocus = FocusNode();

  bool _hoverGrid = false;

  /// 当前 hover 的行/列(边缘柄显隐)。
  int? _hoverRow;
  int? _hoverCol;

  @override
  void initState() {
    super.initState();
    _syncFromNode();
    _cellFocus.addListener(() {
      if (!_cellFocus.hasFocus) _commitCell();
    });
  }

  @override
  void didUpdateWidget(covariant EditorTableGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.node != widget.node) {
      _editing = null;
      _syncFromNode();
    }
  }

  void _syncFromNode() {
    final n = widget.node;
    _hasHeader = n.hasHeader;
    _cells = [
      for (final row in n.rows)
        [
          for (var c = 0; c < n.columnCount; c++)
            c < row.length ? tableCellToMarkdown(row[c]) : '',
        ],
    ];
    if (_cells.isEmpty) _cells = [['']];
  }

  @override
  void dispose() {
    _cellController.dispose();
    _cellFocus.dispose();
    super.dispose();
  }

  int get _rows => _cells.length;
  int get _cols => _cells.isEmpty ? 0 : _cells.first.length;

  void _emit() => widget.onChanged(
        tableGridToMarkdown(_cells, hasHeader: _hasHeader),
      );

  // -----------------------------------------------------------------
  // cell 编辑
  // -----------------------------------------------------------------

  void _startEdit(int r, int c) {
    _commitCell();
    setState(() {
      _editing = (r, c);
      _cellController.text = _cells[r][c];
      _cellController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _cellController.text.length,
      );
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _editing != null) _cellFocus.requestFocus();
    });
  }

  void _commitCell() {
    final e = _editing;
    if (e == null) return;
    final (r, c) = e;
    final next = _cellController.text;
    _editing = null;
    if (r < _rows && c < _cols && _cells[r][c] != next) {
      _cells[r][c] = next;
      _emit();
    } else if (mounted) {
      setState(() {});
    }
  }

  // -----------------------------------------------------------------
  // 行列结构操作
  // -----------------------------------------------------------------

  void _insertRow(int at) {
    _commitCell();
    _cells.insert(at.clamp(0, _rows), List.filled(_cols, ''));
    _emit();
  }

  void _insertCol(int at) {
    _commitCell();
    final i = at.clamp(0, _cols);
    for (final row in _cells) {
      row.insert(i, '');
    }
    _emit();
  }

  void _removeRow(int r) {
    if (_rows <= 1) return;
    _commitCell();
    _cells.removeAt(r);
    _emit();
  }

  void _removeCol(int c) {
    if (_cols <= 1) return;
    _commitCell();
    for (final row in _cells) {
      row.removeAt(c);
    }
    _emit();
  }

  /// 行柄菜单。
  Future<void> _showRowMenu(int r, Offset globalPos) async {
    final action = await _showHandleMenu(globalPos, [
      (Icons.arrow_upward_rounded, '上方插入行', 'above'),
      (Icons.arrow_downward_rounded, '下方插入行', 'below'),
      if (_rows > 1) (Icons.delete_outline_rounded, '删除此行', 'delete'),
    ]);
    switch (action) {
      case 'above':
        _insertRow(r);
      case 'below':
        _insertRow(r + 1);
      case 'delete':
        _removeRow(r);
    }
  }

  /// 列柄菜单。
  Future<void> _showColMenu(int c, Offset globalPos) async {
    final action = await _showHandleMenu(globalPos, [
      (Icons.arrow_back_rounded, '左侧插入列', 'left'),
      (Icons.arrow_forward_rounded, '右侧插入列', 'right'),
      if (_cols > 1) (Icons.delete_outline_rounded, '删除此列', 'delete'),
    ]);
    switch (action) {
      case 'left':
        _insertCol(c);
      case 'right':
        _insertCol(c + 1);
      case 'delete':
        _removeCol(c);
    }
  }

  Future<String?> _showHandleMenu(
    Offset globalPos,
    List<(IconData, String, String)> items,
  ) {
    return showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPos.dx,
        globalPos.dy,
        globalPos.dx + 1,
        globalPos.dy + 1,
      ),
      items: [
        for (final (icon, label, value) in items)
          PopupMenuItem<String>(
            value: value,
            height: 36,
            child: Row(children: [
              Icon(icon, size: 16),
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(fontSize: 13)),
            ]),
          ),
      ],
    );
  }

  // -----------------------------------------------------------------
  // build
  // -----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textStyle = Theme.of(context).textTheme.bodyMedium;
    final borderColor = scheme.outlineVariant.withValues(alpha: 0.6);

    final table = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var r = 0; r < _rows; r++)
          _buildRow(r, scheme, textStyle, borderColor),
      ],
    );

    // 主体 = 列柄条(顶) + [行柄嵌行左缘的表格 + 右加列条] + 下加行条。
    // 行柄放进每一行内部(而非平行 Column)—— 高度天然随行,无对齐/
    // 无限高问题。全部在 MetaData 自管区内;块级选择柄单独在区外。
    final body = MetaData(
      metaData: kEditorSelfManagedRegion,
      behavior: HitTestBehavior.opaque,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // 顶部列柄条(hover 该列时亮起)
            Padding(
              padding: const EdgeInsets.only(left: _kHandleThickness + 2),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                for (var c = 0; c < _cols; c++)
                  _ColHandle(
                    visible: _hoverGrid && _hoverCol == c,
                    width: _kCellWidth + (c > 0 ? 1 : 0),
                    onTapDown: (pos) => _showColMenu(c, pos),
                    onHover: (h) =>
                        setState(() => _hoverCol = h ? c : null),
                  ),
              ]),
            ),
            // IntrinsicHeight:stretch 的右缘加列条随表格高(Column 的
            // 无界高约束下 stretch 会要求无限高 → 布局崩)
            IntrinsicHeight(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  table,
                  // 右缘加列条
                  _EdgeAddBar(
                    axis: Axis.vertical,
                    visible: _hoverGrid,
                    tooltip: '添加列',
                    onTap: () => _insertCol(_cols),
                  ),
                ],
              ),
            ),
            // 下缘加行条
            Padding(
              padding: const EdgeInsets.only(left: _kHandleThickness + 2),
              child: _EdgeAddBar(
                axis: Axis.horizontal,
                visible: _hoverGrid,
                tooltip: '添加行',
                length: _cols * _kCellWidth + (_cols - 1),
                onTap: () => _insertRow(_rows),
              ),
            ),
          ],
        ),
      ),
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _hoverGrid = true),
      onExit: (_) => setState(() {
        _hoverGrid = false;
        _hoverRow = null;
        _hoverCol = null;
      }),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: body,
          ),
          // 左上角块级选择柄(hover 或已选中显示;在 MetaData 外 ——
          // 点击走编辑器整选,选中后退格删整表)
          if (widget.onSelectRequest != null &&
              (_hoverGrid || widget.selected))
            Positioned(
              left: -2,
              top: -6,
              child: Material(
                type: MaterialType.transparency,
                child: Tooltip(
                  message: '选中表格(选中后退格删除)',
                  child: InkWell(
                    onTap: widget.onSelectRequest,
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: widget.selected
                            ? scheme.primary
                            : scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: widget.selected
                              ? scheme.primary
                              : scheme.outlineVariant,
                        ),
                      ),
                      child: Icon(
                        Icons.drag_indicator,
                        size: 12,
                        color: widget.selected
                            ? scheme.onPrimary
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRow(
    int r,
    ColorScheme scheme,
    TextStyle? textStyle,
    Color borderColor,
  ) {
    final isHeader = _hasHeader && r == 0;
    final selectedBorder = widget.selected ? scheme.primary : borderColor;
    // 行 = 左缘行柄 + cells(IntrinsicHeight 让行柄随行高;首末行圆角
    // 由外层边框视觉近似 —— cell 区贴边框内侧)。
    return MouseRegion(
      onEnter: (_) => setState(() => _hoverRow = r),
      child: IntrinsicHeight(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _RowHandle(
              visible: _hoverGrid && _hoverRow == r,
              onTapDown: (pos) => _showRowMenu(r, pos),
              onHover: (h) => setState(() => _hoverRow = h ? r : null),
            ),
            const SizedBox(width: 2),
            Container(
              decoration: BoxDecoration(
                color: isHeader
                    ? scheme.surfaceContainerHighest.withValues(alpha: 0.55)
                    : (widget.selected
                        ? scheme.primary.withValues(alpha: 0.06)
                        : null),
                border: Border(
                  left: BorderSide(
                      color: selectedBorder,
                      width: widget.selected ? 2 : 1),
                  right: BorderSide(
                      color: selectedBorder,
                      width: widget.selected ? 2 : 1),
                  top: r == 0
                      ? BorderSide(
                          color: selectedBorder,
                          width: widget.selected ? 2 : 1)
                      : BorderSide(color: borderColor),
                  bottom: r == _rows - 1
                      ? BorderSide(
                          color: selectedBorder,
                          width: widget.selected ? 2 : 1)
                      : BorderSide.none,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var c = 0; c < _cols; c++)
                    Container(
                      decoration: c > 0
                          ? BoxDecoration(
                              border: Border(
                                  left: BorderSide(color: borderColor)),
                            )
                          : null,
                      child: _buildCell(r, c, isHeader, textStyle, scheme),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCell(
    int r,
    int c,
    bool isHeader,
    TextStyle? textStyle,
    ColorScheme scheme,
  ) {
    final style = (textStyle ?? const TextStyle()).copyWith(
      fontSize: 13,
      fontWeight: isHeader ? FontWeight.w600 : FontWeight.w400,
    );

    if (_editing == (r, c)) {
      // 编辑态:primary 描边框住整个 cell,焦点一目了然
      return Container(
        width: _kCellWidth,
        decoration: BoxDecoration(
          border: Border.all(color: scheme.primary, width: 1.5),
          color: scheme.primaryContainer.withValues(alpha: 0.15),
        ),
        child: TextField(
          controller: _cellController,
          focusNode: _cellFocus,
          style: style,
          cursorHeight: 15,
          decoration: const InputDecoration(
            isDense: true,
            contentPadding:
                EdgeInsets.symmetric(horizontal: 7, vertical: 7),
            border: InputBorder.none,
          ),
          onSubmitted: (_) => _commitCell(),
        ),
      );
    }

    final text = _cells[r][c];
    return MouseRegion(
      onEnter: (_) => setState(() => _hoverCol = c),
      child: InkWell(
        onTap: () => _startEdit(r, c),
        hoverColor: scheme.primary.withValues(alpha: 0.05),
        child: Container(
          width: _kCellWidth,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
          child: Text(
            text.isEmpty ? ' ' : text,
            style: text.isEmpty
                ? style.copyWith(
                    color:
                        scheme.onSurfaceVariant.withValues(alpha: 0.4))
                : style,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}

/// 顶部列柄:hover 该列时亮起的胶囊小条,点击弹列菜单。
class _ColHandle extends StatelessWidget {
  const _ColHandle({
    required this.visible,
    required this.width,
    required this.onTapDown,
    required this.onHover,
  });

  final bool visible;
  final double width;
  final void Function(Offset globalPos) onTapDown;
  final ValueChanged<bool> onHover;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return MouseRegion(
      onEnter: (_) => onHover(true),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) => onTapDown(d.globalPosition),
        child: SizedBox(
          width: width,
          height: _kHandleThickness,
          child: Center(
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 120),
              opacity: visible ? 1 : 0,
              child: Container(
                width: 28,
                height: 5,
                decoration: BoxDecoration(
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 左侧行柄:hover 该行时亮起的胶囊小条,点击弹行菜单。
class _RowHandle extends StatelessWidget {
  const _RowHandle({
    required this.visible,
    required this.onTapDown,
    required this.onHover,
  });

  final bool visible;
  final void Function(Offset globalPos) onTapDown;
  final ValueChanged<bool> onHover;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return MouseRegion(
      onEnter: (_) => onHover(true),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) => onTapDown(d.globalPosition),
        child: SizedBox(
          width: _kHandleThickness,
          child: Center(
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 120),
              opacity: visible ? 1 : 0,
              child: Container(
                width: 5,
                height: 22,
                decoration: BoxDecoration(
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 表格边缘的加行/加列条(hover 表格时浮现,+ 号居中)。
class _EdgeAddBar extends StatefulWidget {
  const _EdgeAddBar({
    required this.axis,
    required this.visible,
    required this.tooltip,
    required this.onTap,
    this.length,
  });

  final Axis axis;
  final bool visible;
  final String tooltip;
  final VoidCallback onTap;

  /// 水平条的长度(列数 × cell 宽);垂直条随表格高度伸展。
  final double? length;

  @override
  State<_EdgeAddBar> createState() => _EdgeAddBarState();
}

class _EdgeAddBarState extends State<_EdgeAddBar> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final horizontal = widget.axis == Axis.horizontal;
    final bar = AnimatedOpacity(
      duration: const Duration(milliseconds: 120),
      opacity: widget.visible ? (_hover ? 1 : 0.55) : 0,
      child: Container(
        width: horizontal ? widget.length : 12,
        height: horizontal ? 12 : null,
        margin: horizontal
            ? const EdgeInsets.only(top: 2)
            : const EdgeInsets.only(left: 2),
        decoration: BoxDecoration(
          color: _hover
              ? scheme.primary.withValues(alpha: 0.15)
              : scheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(
          Icons.add,
          size: 11,
          color:
              _hover ? scheme.primary : scheme.onSurfaceVariant,
        ),
      ),
    );
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: Tooltip(
        message: widget.tooltip,
        waitDuration: const Duration(milliseconds: 600),
        child: GestureDetector(onTap: widget.onTap, child: bar),
      ),
    );
  }
}
