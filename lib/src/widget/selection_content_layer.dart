/// 选区内容层 —— 把手势层 + toolbar 组合,挂在 FluxdoRender 顶层。
///
/// 手势层产出 SelectionData(松手/清除时);本层据此弹/收子包自带 toolbar,
/// 并把「引用」回调透传给主项目、「复制」在 toolbar 内走 Clipboard。
library;

import 'package:flutter/widgets.dart';

import '../selection/selection_data.dart';
import '../selection/selection_exporter.dart';
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

  /// 祖先 Scrollable 的滚动位置(监听它驱动 toolbar 跟随)。
  ScrollPosition? _scrollPosition;

  SelectionExporter get _exporter =>
      SelectionExporter(widget.controller.registry);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 监听**祖先** Scrollable —— 不能用 NotificationListener(实测:祖先
    // Scrollable 的 ScrollNotification 不冒泡到后代,收不到)。改用
    // Scrollable.of(context).position(Listenable),滚动时直接 notify。
    final pos = Scrollable.maybeOf(context)?.position;
    if (pos != _scrollPosition) {
      _scrollPosition?.removeListener(_onScroll);
      _scrollPosition = pos;
      _scrollPosition?.addListener(_onScroll);
    }
  }

  void _onSelectionChanged(SelectionData? data) {
    _toolbar?.hide();
    _toolbar = null;
    if (data == null) return;
    _toolbar = SelectionToolbar(
      context: context,
      topBoundaryGlobal: _viewportTopGlobal,
      onQuote: (plainText) {
        widget.onQuoteRequest?.call(plainText);
        widget.controller.clear();
      },
      onCopied: widget.onCopyToast,
    );
    _toolbar!.show(data);
  }

  /// 滚动时:toolbar 在屏 → 用当前选区重算几何并重定位(滚出视口自动隐藏)。
  void _onScroll() {
    final toolbar = _toolbar;
    if (toolbar == null) return;
    final sel = widget.controller.selection;
    if (sel == null) return;
    toolbar.reposition(_exporter.export(sel));
  }

  @override
  void dispose() {
    _scrollPosition?.removeListener(_onScroll);
    _toolbar?.hide();
    super.dispose();
  }

  /// 祖先 Scrollable 视口的全局上边缘 —— 给 toolbar 当顶部安全线
  /// (视口本就在 AppBar 下方,toolbar 越过它即会遮挡 AppBar → 翻到下方)。
  double? _viewportTopGlobal() {
    final scrollable = Scrollable.maybeOf(context);
    final box = scrollable?.context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero).dy;
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
