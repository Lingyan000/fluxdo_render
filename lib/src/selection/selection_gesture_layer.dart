/// 自研选区手势层 —— 顶层 RawGestureDetector,按设备分流:
/// - 触摸/触控笔:LongPress 起选 + 拖拽扩展(移动端)。
/// - 鼠标:TapAndPan(tap-down 定位 + 双击选词 / 三击选段 + drag 扩展)。
/// - Tap:点空白清除。
///
/// 设计依据 Flutter SDK SelectableRegion(selectable_region.dart):桌面鼠标
/// 用 TapAndPanGestureRecognizer(一个 recognizer 管 tap 连击 + drag),按
/// supportedDevices 与触摸 LongPress 分流;鼠标不进 Scrollable 拖拽竞技场
/// (默认 dragDevices 不含 mouse),零冲突。
library;

import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import 'hit_tester.dart';
import 'selection_data.dart';
import 'selection_exporter.dart';
import 'selection_geometry.dart';
import 'selection_registry.dart';

class SelectionGestureLayer extends StatefulWidget {
  const SelectionGestureLayer({
    super.key,
    required this.controller,
    required this.onSelectionChanged,
    required this.child,
  });

  final SelectionController controller;

  /// 选区稳定(松手)/ 清除时触发,把 SelectionData 交给上层(弹 toolbar 等)。
  final SelectionResultCallback onSelectionChanged;

  final Widget child;

  @override
  State<SelectionGestureLayer> createState() => _SelectionGestureLayerState();
}

class _SelectionGestureLayerState extends State<SelectionGestureLayer> {
  SelectionHitTester get _hit => SelectionHitTester(widget.controller.registry);
  SelectionExporter get _exporter =>
      SelectionExporter(widget.controller.registry);

  void _clear() {
    if (widget.controller.selection != null) {
      widget.controller.clear();
      widget.onSelectionChanged(null);
    }
  }

  // ── 设备无关的核心动作(触摸/鼠标共用)──────────────────────────

  /// 起选:选中所在「词」(￼ 上则整颗 emoji/mention)。返回是否成功起选。
  bool _startWordAt(Offset global) {
    final pos = _hit.positionAt(global);
    if (pos == null) {
      _clear();
      return false;
    }
    final wb = _hit.wordBoundaryAt(pos);
    widget.controller.selection = (wb != null && wb.start < wb.end)
        ? DocumentSelection(
            base: pos.copyWith(renderOffset: wb.start),
            extent: pos.copyWith(renderOffset: wb.end),
          )
        : DocumentSelection.collapsed(pos);
    return true;
  }

  /// 折叠定位(鼠标单击 / drag 起点):光标态,后续 drag 扩展。
  void _collapseAt(Offset global) {
    final pos = _hit.positionAt(global);
    if (pos == null) {
      _clear();
      return;
    }
    widget.controller.selection = DocumentSelection.collapsed(pos);
  }

  /// 整段选中(鼠标三击)。
  void _selectParagraphAt(Offset global) {
    final pos = _hit.positionAt(global);
    if (pos == null) {
      _clear();
      return;
    }
    final len = _hit.renderLengthOf(pos.blockId);
    if (len == null) {
      _startWordAt(global);
      return;
    }
    widget.controller.selection = DocumentSelection(
      base: pos.copyWith(renderOffset: 0),
      extent: pos.copyWith(renderOffset: len),
    );
  }

  /// 扩展 extent(base 锚不动)。
  void _extendTo(Offset global) {
    final current = widget.controller.selection;
    if (current == null) return;
    final pos = _hit.positionAt(global);
    if (pos == null) return;
    widget.controller.selection = current.copyWith(extent: pos);
  }

  /// 松手定选:有实际选区则导出弹 toolbar,否则清除。
  void _finish() {
    final sel = widget.controller.selection;
    if (sel == null || sel.isCollapsed) {
      _clear();
      return;
    }
    widget.onSelectionChanged(_exporter.export(sel));
  }

  // ── 触摸:长按 ──────────────────────────────────────────────
  void _onLongPressStart(LongPressStartDetails d) => _startWordAt(d.globalPosition);
  void _onLongPressMoveUpdate(LongPressMoveUpdateDetails d) =>
      _extendTo(d.globalPosition);
  void _onLongPressEnd(LongPressEndDetails d) => _finish();

  // ── 鼠标:TapAndPan ────────────────────────────────────────
  // tap-down 按连击数分发:1=折叠定位,2=选词,3=选段。drag 起点已由
  // tap-down 定位,drag-update 扩展,drag-end 定选。
  void _onMouseTapDown(TapDragDownDetails d) {
    final count = math.min(d.consecutiveTapCount, 3);
    switch (count) {
      case 1:
        _collapseAt(d.globalPosition);
      case 2:
        _startWordAt(d.globalPosition);
      default:
        _selectParagraphAt(d.globalPosition);
    }
  }

  void _onMouseTapUp(TapDragUpDetails d) {
    // 单击(无 drag)落定:折叠选区无内容 → 清除 + 收 toolbar;
    // 双击/三击已选中内容 → 导出弹 toolbar。
    final count = math.min(d.consecutiveTapCount, 3);
    if (count == 1) {
      _clear();
    } else {
      _finish();
    }
  }

  void _onMouseDragUpdate(TapDragUpdateDetails d) =>
      _extendTo(d.globalPosition);

  void _onMouseDragEnd(TapDragEndDetails d) => _finish();

  // ── 触摸:点空白清除 ───────────────────────────────────────
  void _onTapUp(TapUpDetails d) => _clear();

  @override
  Widget build(BuildContext context) {
    return RawGestureDetector(
      behavior: HitTestBehavior.translucent,
      gestures: {
        // 鼠标:tap 连击 + drag 选区
        TapAndPanGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<TapAndPanGestureRecognizer>(
          () => TapAndPanGestureRecognizer(
            debugOwner: this,
            supportedDevices: const {PointerDeviceKind.mouse},
          ),
          (r) {
            r
              ..onTapDown = _onMouseTapDown
              ..onTapUp = _onMouseTapUp
              ..onDragUpdate = _onMouseDragUpdate
              ..onDragEnd = _onMouseDragEnd
              ..dragStartBehavior = DragStartBehavior.down;
          },
        ),
        // 触摸/触控笔:长按起选 + 拖拽扩展
        LongPressGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
          () => LongPressGestureRecognizer(
            debugOwner: this,
            supportedDevices: const {
              PointerDeviceKind.touch,
              PointerDeviceKind.stylus,
              PointerDeviceKind.invertedStylus,
            },
          ),
          (r) {
            r
              ..onLongPressStart = _onLongPressStart
              ..onLongPressMoveUpdate = _onLongPressMoveUpdate
              ..onLongPressEnd = _onLongPressEnd;
          },
        ),
        // 触摸点空白清除(鼠标走 TapAndPan 的 tap)
        TapGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
          () => TapGestureRecognizer(
            debugOwner: this,
            supportedDevices: const {
              PointerDeviceKind.touch,
              PointerDeviceKind.stylus,
              PointerDeviceKind.invertedStylus,
            },
          ),
          (r) {
            r.onTapUp = _onTapUp;
          },
        ),
      },
      child: widget.child,
    );
  }
}
