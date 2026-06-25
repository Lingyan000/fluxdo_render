/// 选区内容层 —— 把手势层 + toolbar 组合,挂在 FluxdoRender 顶层。
///
/// 手势层产出 SelectionData(松手/清除时);本层据此弹/收子包自带 toolbar,
/// 并把「引用」回调透传给主项目、「复制」在 toolbar 内走 Clipboard。
library;

import 'package:flutter/widgets.dart';

import '../selection/selection_data.dart';
import '../selection/selection_gesture_layer.dart';
import '../selection/selection_registry.dart';
import '../selection/selection_toolbar.dart';

class SelectionContentLayer extends StatefulWidget {
  const SelectionContentLayer({
    super.key,
    required this.controller,
    required this.onQuoteRequest,
    required this.onCopyToast,
    required this.child,
  });

  final SelectionController controller;
  final QuoteRequestCallback? onQuoteRequest;
  final CopyToastCallback? onCopyToast;
  final Widget child;

  @override
  State<SelectionContentLayer> createState() => _SelectionContentLayerState();
}

class _SelectionContentLayerState extends State<SelectionContentLayer> {
  SelectionToolbar? _toolbar;

  void _onSelectionChanged(SelectionData? data) {
    _toolbar?.hide();
    _toolbar = null;
    if (data == null) return;
    _toolbar = SelectionToolbar(
      context: context,
      onQuote: (plainText) {
        widget.onQuoteRequest?.call(plainText);
        widget.controller.clear();
      },
      onCopied: widget.onCopyToast,
    );
    _toolbar!.show(data);
  }

  @override
  void dispose() {
    _toolbar?.hide();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SelectionGestureLayer(
      controller: widget.controller,
      onSelectionChanged: _onSelectionChanged,
      child: widget.child,
    );
  }
}
