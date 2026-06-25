/// 自研选区手势层 —— 顶层 RawGestureDetector,管长按起选 + 拖拽扩展 + 点空白清除。
///
/// 已探针实测(Flutter 3.44):长按 vs tap 天然分流到不同 recognizer,
/// link/mention 短点正常、空白长按起选、image 子树长按子赢 —— 零冲突,无需豁免。
library;

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

  void _onLongPressStart(LongPressStartDetails d) {
    final pos = _hit.positionAt(d.globalPosition);
    if (pos == null) {
      _clear();
      return;
    }
    // 长按起选:选中所在「词」(￼ 上则整颗 emoji/mention)。
    final wb = _hit.wordBoundaryAt(pos);
    final DocumentSelection sel;
    if (wb != null && wb.start < wb.end) {
      sel = DocumentSelection(
        base: pos.copyWith(renderOffset: wb.start),
        extent: pos.copyWith(renderOffset: wb.end),
      );
    } else {
      sel = DocumentSelection.collapsed(pos);
    }
    widget.controller.selection = sel;
    // 起选不立刻弹 toolbar(等松手),避免拖拽中频繁重定位。
  }

  void _onLongPressMoveUpdate(LongPressMoveUpdateDetails d) {
    final current = widget.controller.selection;
    if (current == null) return;
    final pos = _hit.positionAt(d.globalPosition);
    if (pos == null) return;
    // 扩展 extent,base(起选词的锚)不动。
    widget.controller.selection =
        current.copyWith(extent: pos);
  }

  void _onLongPressEnd(LongPressEndDetails d) {
    final sel = widget.controller.selection;
    if (sel == null || sel.isCollapsed) {
      _clear();
      return;
    }
    widget.onSelectionChanged(_exporter.export(sel));
  }

  void _onTapUp(TapUpDetails d) {
    // 点击落在选区外 → 清除。落在选区内 → 保留(让上层 toolbar 处理)。
    _clear();
  }

  @override
  Widget build(BuildContext context) {
    return RawGestureDetector(
      behavior: HitTestBehavior.translucent,
      gestures: {
        LongPressGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
          () => LongPressGestureRecognizer(),
          (r) {
            r
              ..onLongPressStart = _onLongPressStart
              ..onLongPressMoveUpdate = _onLongPressMoveUpdate
              ..onLongPressEnd = _onLongPressEnd;
          },
        ),
        TapGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
          () => TapGestureRecognizer(),
          (r) {
            r.onTapUp = _onTapUp;
          },
        ),
      },
      child: widget.child,
    );
  }
}
