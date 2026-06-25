/// 移动端选区拖拽手柄 —— 选区两端的把手,可拖动调整选区范围;拖动时联动放大镜。
///
/// 架构(借鉴 super_editor,简化):单一数据源 [SelectionController];手柄位置永远
/// 由「当前选区端点全局锚点」(SelectionExporter.endpointAnchors)派生,不另存坐标。
/// 复用 Flutter 系统的 buildHandle/getHandleAnchor/getHandleSize(纯绘制函数,
/// 可脱离 SelectableRegion 单独用),定位+拖动用 Positioned + GestureDetector 自管。
///
/// 拖动:命中文本得新 DocumentPosition → 固定另一端、动被拖端;越过另一端时
/// base/extent 自然交换(由 orderedEndpoints 视觉序归一化吸收)。
library;

import 'package:flutter/cupertino.dart' show cupertinoTextSelectionControls;
import 'package:flutter/material.dart';

import 'hit_tester.dart';
import 'selection_exporter.dart';
import 'selection_geometry.dart';
import 'selection_magnifier.dart';
import 'selection_registry.dart';

class SelectionHandlesController {
  SelectionHandlesController({
    required this.context,
    required this.controller,
  })  : _hit = SelectionHitTester(controller.registry),
        _exporter = SelectionExporter(controller.registry),
        _magnifier = SelectionMagnifier(context);

  final BuildContext context;
  final SelectionController controller;
  final SelectionHitTester _hit;
  final SelectionExporter _exporter;
  final SelectionMagnifier _magnifier;

  OverlayEntry? _entry;
  // 拖动中:被拖的是哪个端(视觉 start / end),拖动期间固定另一端。
  _DragSide? _dragging;

  bool get isShowing => _entry != null;

  /// 显示手柄(选区存在时)。重复调 = 刷新位置。
  void show() {
    if (controller.selection == null) return;
    if (_entry != null) {
      _entry!.markNeedsBuild();
      return;
    }
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;
    _entry = OverlayEntry(builder: _build);
    overlay.insert(_entry!);
  }

  /// 选区变了 / 滚动了 → 刷新手柄位置。
  void update() => _entry?.markNeedsBuild();

  void hide() {
    _magnifier.hide();
    _entry?.remove();
    _entry = null;
    _dragging = null;
  }

  Widget _build(BuildContext ctx) {
    final sel = controller.selection;
    if (sel == null || sel.isCollapsed) return const SizedBox.shrink();
    final anchors = _exporter.endpointAnchors(sel);
    if (anchors == null) return const SizedBox.shrink();

    final controls = Theme.of(context).platform == TargetPlatform.iOS
        ? cupertinoTextSelectionControls
        : materialTextSelectionControls;

    return Stack(
      children: [
        _handle(ctx, controls, _DragSide.start, anchors.start,
            anchors.startLineHeight),
        _handle(ctx, controls, _DragSide.end, anchors.end,
            anchors.endLineHeight),
      ],
    );
  }

  Widget _handle(
    BuildContext ctx,
    TextSelectionControls controls,
    _DragSide side,
    Offset anchorGlobal,
    double lineHeight,
  ) {
    // start 手柄用 left 类型(把手在文字左下),end 用 right。
    final type = side == _DragSide.start
        ? TextSelectionHandleType.left
        : TextSelectionHandleType.right;
    final handleAnchor = controls.getHandleAnchor(type, lineHeight);
    final size = controls.getHandleSize(lineHeight);

    // overlay 局部坐标(overlay 通常铺满屏 → 全局即局部)。
    final overlayBox =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    final local = overlayBox == null
        ? anchorGlobal
        : overlayBox.globalToLocal(anchorGlobal);

    // 命中区放大到 ≥44px(手指友好),手柄绘制居中其中。
    const touch = 44.0;
    final left = local.dx - handleAnchor.dx - (touch - size.width) / 2;
    final top = local.dy - handleAnchor.dy - (touch - size.height) / 2;

    return Positioned(
      left: left,
      top: top,
      width: touch.clamp(size.width, double.infinity),
      height: touch.clamp(size.height, double.infinity),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onPanStart: (d) => _onDragStart(side, d.globalPosition),
        onPanUpdate: (d) => _onDragUpdate(d.globalPosition),
        onPanEnd: (_) => _onDragEnd(),
        child: Center(
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: controls.buildHandle(
              ctx,
              type,
              lineHeight,
              null,
            ),
          ),
        ),
      ),
    );
  }

  void _onDragStart(_DragSide side, Offset global) {
    _dragging = side;
    _magnifier.show(global);
  }

  void _onDragUpdate(Offset global) {
    final sel = controller.selection;
    final side = _dragging;
    if (sel == null || side == null) return;
    final pos = _hit.positionAt(global);
    if (pos == null) return;

    // 视觉序固定另一端:拖 start → 固定 visualEnd 作 base、pos 作 extent;
    // 拖 end → 固定 visualStart 作 base、pos 作 extent。越过另一端时视觉序
    // 自然反转(下次 build 的 orderedEndpoints 会重新归一)。
    final ends = _exporter.orderedEndpoints(sel);
    if (ends == null) return;
    final fixed =
        side == _DragSide.start ? ends.visualEnd : ends.visualStart;
    controller.selection = DocumentSelection(base: fixed, extent: pos);
    _magnifier.show(global);
    _entry?.markNeedsBuild();
  }

  void _onDragEnd() {
    _dragging = null;
    _magnifier.hide();
    _entry?.markNeedsBuild();
  }
}

enum _DragSide { start, end }
