/// 表格岛的编辑态渲染(M5):cell 单击原位编辑 + 行列悬浮操作。
///
/// 替换通用 EditorIsland 的 AbsorbPointer 只读渲染 —— 表格是"结构化
/// 数据",cell 级直改比源码/对话框顺手一个量级:
/// - 自绘轻量表格(边框/表头底色对齐阅读端 table_builder 视觉);
/// - 单击 cell → cell 原位变 TextField(markdown 源码口径,富格式保留);
/// - 提交(回车/失焦)→ 回调宿主重建 markdown → replaceIsland;
/// - 尾部 [+行][+列] 按钮,行/列头 hover 显删除。
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
  /// 当前网格(markdown cell 文本);null = 未在编辑,直接展示 node。
  late List<List<String>> _cells;
  late bool _hasHeader;

  /// 正在编辑的 cell(row, col);null = 无。
  (int, int)? _editing;
  final TextEditingController _cellController = TextEditingController();
  final FocusNode _cellFocus = FocusNode();

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
    // 帧后请求焦点(TextField 刚挂载)
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

  void _addRow() {
    _commitCell();
    _cells.add(List.filled(_cols, ''));
    _emit();
  }

  void _addCol() {
    _commitCell();
    for (final row in _cells) {
      row.add('');
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

  bool _hoverGrid = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textStyle = Theme.of(context).textTheme.bodyMedium;
    final borderColor = scheme.outlineVariant.withValues(alpha: 0.6);

    final table = Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: widget.selected ? scheme.primary : borderColor,
          width: widget.selected ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(8),
        color: widget.selected
            ? scheme.primary.withValues(alpha: 0.06)
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var r = 0; r < _rows; r++)
              _buildRow(r, scheme, textStyle, borderColor),
          ],
        ),
      ),
    );

    // MetaData 标记自管区:编辑器 tap/pan 命中本子树时让路(焦点/光标
    // 由 cell TextField 自管,见 kEditorSelfManagedRegion)。
    // 选择柄不在标记内 —— 点它走编辑器整选。
    return MouseRegion(
      onEnter: (_) => setState(() => _hoverGrid = true),
      onExit: (_) => setState(() => _hoverGrid = false),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Padding(
            // 给左上角选择柄留出悬挂空间
            padding: const EdgeInsets.only(top: 6),
            child: MetaData(
              metaData: kEditorSelfManagedRegion,
              behavior: HitTestBehavior.opaque,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  table,
                  // 底部操作条:加行/加列(常显小按钮;删除挂行列 hover)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Row(children: [
                      _MiniAction(
                          icon: Icons.add, label: '行', onTap: _addRow),
                      const SizedBox(width: 8),
                      _MiniAction(
                          icon: Icons.add, label: '列', onTap: _addCol),
                    ]),
                  ),
                ],
              ),
            ),
          ),
          // 左上角选择柄(hover 表格或已选中时显示;在 MetaData 外 ——
          // 点击走编辑器整选,选中后退格删整表)
          if (widget.onSelectRequest != null &&
              (_hoverGrid || widget.selected))
            Positioned(
              left: -4,
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
    return _HoverRow(
      trailing: _rows > 1
          ? _MiniAction(
              icon: Icons.remove,
              tooltip: '删除此行',
              onTap: () => _removeRow(r),
            )
          : null,
      child: Container(
        decoration: BoxDecoration(
          color: isHeader
              ? scheme.surfaceContainerHighest.withValues(alpha: 0.55)
              : null,
          border: r > 0
              ? Border(top: BorderSide(color: borderColor))
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var c = 0; c < _cols; c++)
              Container(
                decoration: c > 0
                    ? BoxDecoration(
                        border:
                            Border(left: BorderSide(color: borderColor)),
                      )
                    : null,
                child: _buildCell(r, c, isHeader, textStyle, scheme),
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
    const cellWidth = 132.0;

    if (_editing == (r, c)) {
      return SizedBox(
        width: cellWidth,
        child: TextField(
          controller: _cellController,
          focusNode: _cellFocus,
          style: style,
          decoration: InputDecoration(
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            border: InputBorder.none,
            filled: true,
            fillColor: scheme.primary.withValues(alpha: 0.06),
          ),
          onSubmitted: (_) => _commitCell(),
        ),
      );
    }

    final text = _cells[r][c];
    Widget cell = InkWell(
      onTap: () => _startEdit(r, c),
      child: Container(
        width: cellWidth,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
        child: Text(
          text.isEmpty ? ' ' : text,
          style: text.isEmpty
              ? style.copyWith(
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.4))
              : style,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
    // 首行 cell hover:右上角显删列按钮
    if (r == 0 && _cols > 1) {
      cell = _HoverStackAction(
        action: _MiniAction(
          icon: Icons.remove,
          tooltip: '删除此列',
          onTap: () => _removeCol(c),
        ),
        child: cell,
      );
    }
    return cell;
  }
}

/// 行容器:hover 时行尾显操作按钮(删除行)。
class _HoverRow extends StatefulWidget {
  const _HoverRow({required this.child, this.trailing});

  final Widget child;
  final Widget? trailing;

  @override
  State<_HoverRow> createState() => _HoverRowState();
}

class _HoverRowState extends State<_HoverRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          widget.child,
          if (widget.trailing != null)
            Opacity(
              opacity: _hover ? 1 : 0,
              child: widget.trailing,
            ),
        ],
      ),
    );
  }
}

/// cell hover 时右上角叠一个小操作(删列)。
class _HoverStackAction extends StatefulWidget {
  const _HoverStackAction({required this.child, required this.action});

  final Widget child;
  final Widget action;

  @override
  State<_HoverStackAction> createState() => _HoverStackActionState();
}

class _HoverStackActionState extends State<_HoverStackAction> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          widget.child,
          if (_hover)
            Positioned(top: -2, right: -2, child: widget.action),
        ],
      ),
    );
  }
}

/// 小操作按钮(加行/加列/删除)。
class _MiniAction extends StatelessWidget {
  const _MiniAction({
    required this.icon,
    this.label,
    this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String? label;
  final String? tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget child = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: scheme.onSurfaceVariant),
            if (label != null) ...[
              const SizedBox(width: 2),
              Text(label!,
                  style: TextStyle(
                      fontSize: 11, color: scheme.onSurfaceVariant)),
            ],
          ],
        ),
      ),
    );
    if (tooltip != null) {
      child = Tooltip(message: tooltip!, child: child);
    }
    return Material(type: MaterialType.transparency, child: child);
  }
}
