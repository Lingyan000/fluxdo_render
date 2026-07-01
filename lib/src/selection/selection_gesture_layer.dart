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
import 'package:flutter/services.dart' show HapticFeedback;
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

class _SelectionGestureLayerState extends State<SelectionGestureLayer>
    with AutomaticKeepAliveClientMixin {
  SelectionHitTester get _hit => SelectionHitTester(widget.controller.registry);
  SelectionExporter get _exporter =>
      SelectionExporter(widget.controller.registry);

  /// 本次选区是否由触摸/长按产生(决定上层是否显示移动端拖拽手柄)。
  bool _lastInputWasTouch = false;

  /// 拖拽进行中(drag/longPress 起→止)。期间:① 保活本 chunk(滚出视口也不
  /// 被回收,recognizer 不死);② 滚动时按钉住的指针位置 re-extend。
  bool _isDragging = false;

  /// 最后一次指针全局坐标(滚轮滚动时用它在新内容上重算 extent)。
  Offset? _lastDragGlobal;

  /// 祖先 Scrollable 的滚动位置(订阅它驱动滚轮扩选)。
  ScrollPosition? _scrollPosition;

  /// 祖先 Scrollable + 边缘自动滚动器(拖到视口上/下边缘自动滚动)。
  /// 移动端无滚轮,跨视口拖选全靠它;桌面拖到边缘也可(滚轮之外的另一路径)。
  ScrollableState? _scrollable;
  EdgeDraggingAutoScroller? _autoScroller;

  @override
  bool get wantKeepAlive => _isDragging;

  /// 起拖:记坐标 + 保活(鼠标 onDragStart / 触摸 onLongPressStart 调)。
  void _beginDrag(Offset global) {
    _lastDragGlobal = global;
    if (!_isDragging) {
      _isDragging = true;
      updateKeepAlive();
    }
  }

  /// 止拖:停保活(松手后,若无选区则本 chunk 可回收)+ 停自动滚动。
  void _endDrag() {
    _autoScroller?.stopAutoScroll();
    if (_isDragging) {
      _isDragging = false;
      updateKeepAlive();
    }
    _lastDragGlobal = null;
  }

  /// 拖拽中:指针靠近视口上/下边缘则自动滚动(配合 [_onScroll] 让 extent 跟随)。
  /// height 60 → 距边缘约 30px 即触发(比 1px 命中边缘更跟手)。
  void _maybeAutoScroll(Offset global) {
    _autoScroller?.startAutoScrollIfNecessary(
      Rect.fromCenter(center: global, width: 1, height: 60),
    );
  }

  /// 滚动中(滚轮 / 自动滚动)且正在拖拽:鼠标钉在原位、内容在底下滚,用钉住的
  /// 全局坐标重跑 _extendTo → 命中新滚入内容 → extent 跟着扩(= 滚动扩选)。
  /// 对齐 Flutter _ScrollableSelectionContainerDelegate「滚动按指针重算端点」。
  void _onScroll() {
    final g = _lastDragGlobal;
    if (_isDragging && g != null) _extendTo(g);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 订阅**祖先** Scrollable(同 SelectionContentLayer:祖先 ScrollNotification
    // 不冒泡到后代,改用 position 这个 Listenable)。
    final scrollable = Scrollable.maybeOf(context);
    final pos = scrollable?.position;
    if (pos != _scrollPosition) {
      _scrollPosition?.removeListener(_onScroll);
      _scrollPosition = pos;
      _scrollPosition?.addListener(_onScroll);
    }
    if (scrollable != _scrollable) {
      _scrollable = scrollable;
      _autoScroller = scrollable == null
          ? null
          : EdgeDraggingAutoScroller(scrollable, velocityScalar: 30);
    }
  }

  @override
  void dispose() {
    _autoScroller?.stopAutoScroll();
    _scrollPosition?.removeListener(_onScroll);
    super.dispose();
  }

  void _clear() {
    if (widget.controller.selection != null) {
      widget.controller.clear();
      widget.onSelectionChanged(null, fromTouch: _lastInputWasTouch);
    }
  }

  // ── 设备无关的核心动作(触摸/鼠标共用)──────────────────────────

  /// 起选:选中所在「词」(￼ 上则整颗 emoji/mention)。返回是否成功起选。
  bool _startWordAt(Offset global) {
    final pos = _hit.positionAt(global, hitTestRoot: context.findRenderObject());
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
    final pos = _hit.positionAt(global, hitTestRoot: context.findRenderObject());
    if (pos == null) {
      _clear();
      return;
    }
    widget.controller.selection = DocumentSelection.collapsed(pos);
  }

  /// 整段选中(鼠标三击)。
  void _selectParagraphAt(Offset global) {
    final pos = _hit.positionAt(global, hitTestRoot: context.findRenderObject());
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
    final pos = _hit.positionAt(global, hitTestRoot: context.findRenderObject());
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
    widget.onSelectionChanged(_exporter.export(sel), fromTouch: _lastInputWasTouch);
  }

  // ── 触摸:长按 ──────────────────────────────────────────────
  void _onLongPressStart(LongPressStartDetails d) {
    _lastInputWasTouch = true;
    _beginDrag(d.globalPosition);
    // 长按起选震动(对齐系统文本选区)。
    if (_startWordAt(d.globalPosition)) {
      HapticFeedback.selectionClick();
    }
  }

  void _onLongPressMoveUpdate(LongPressMoveUpdateDetails d) {
    _lastDragGlobal = d.globalPosition;
    final before = widget.controller.selection?.extent;
    _extendTo(d.globalPosition);
    // 拖动跨到新位置才震动(不每帧震)。
    if (widget.controller.selection?.extent != before) {
      HapticFeedback.selectionClick();
    }
    _maybeAutoScroll(d.globalPosition);
  }

  void _onLongPressEnd(LongPressEndDetails d) {
    _finish();
    _endDrag();
  }

  // ── 鼠标:TapAndPan ────────────────────────────────────────
  // tap-down 按连击数分发:1=折叠定位,2=选词,3=选段。drag 起点已由
  // tap-down 定位,drag-update 扩展,drag-end 定选。
  void _onMouseTapDown(TapDragDownDetails d) {
    _lastInputWasTouch = false;
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

  void _onMouseDragStart(TapDragStartDetails d) {
    // 拖拽必须从拖拽起点重新锚定 base —— 否则上一次点击残留的连击计数
    // (consecutiveTapCount=2/3,触控板/快速点击极易累积)会让 tapDown 先
    // 选了词/整段,drag 再 extend 就变成「从段首拖 = 整段」。collapse 到起点
    // 保证拖拽永远是 [起点 → 当前] 的干净子区间。
    _beginDrag(d.globalPosition);
    _collapseAt(d.globalPosition);
  }

  void _onMouseDragUpdate(TapDragUpdateDetails d) {
    _lastDragGlobal = d.globalPosition;
    _extendTo(d.globalPosition);
    _maybeAutoScroll(d.globalPosition);
  }

  void _onMouseDragEnd(TapDragEndDetails d) {
    _finish();
    _endDrag();
  }

  // ── 触摸:点空白清除 ───────────────────────────────────────
  void _onTapUp(TapUpDetails d) => _clear();

  @override
  Widget build(BuildContext context) {
    super.build(context); // AutomaticKeepAliveClientMixin:拖拽期间保活本 chunk
    return RawGestureDetector(
      behavior: HitTestBehavior.translucent,
      gestures: {
        // 鼠标 / 触控板:tap 连击 + drag 选区
        TapAndPanGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<TapAndPanGestureRecognizer>(
          () => TapAndPanGestureRecognizer(
            debugOwner: this,
            supportedDevices: const {
              PointerDeviceKind.mouse,
              PointerDeviceKind.trackpad,
            },
          ),
          (r) {
            r
              ..onTapDown = _onMouseTapDown
              ..onTapUp = _onMouseTapUp
              ..onDragStart = _onMouseDragStart
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
