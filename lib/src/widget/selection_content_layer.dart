/// 选区内容层 —— 把手势层 + toolbar 组合,挂在 FluxdoRender 顶层。
///
/// 手势层产出 SelectionData(松手/清除时);本层据此弹/收子包自带 toolbar,
/// 并把「引用」回调透传给主项目、「复制」在 toolbar 内走 Clipboard。
library;

import 'package:flutter/widgets.dart';

import '../selection/selection_data.dart';
import '../selection/selection_exporter.dart';
import '../selection/selection_gesture_layer.dart';
import '../selection/selection_handles.dart';
import '../selection/selection_registry.dart';
import '../selection/selection_toolbar.dart';

class SelectionContentLayer extends StatefulWidget {
  const SelectionContentLayer({
    super.key,
    required this.controller,
    required this.onQuoteRequest,
    required this.onCopyQuoteRequest,
    required this.onCopyToast,
    required this.child,
  });

  final SelectionController controller;
  final QuoteRequestCallback? onQuoteRequest;
  final QuoteRequestCallback? onCopyQuoteRequest;
  final CopyToastCallback? onCopyToast;
  final Widget child;

  @override
  State<SelectionContentLayer> createState() => _SelectionContentLayerState();
}

class _SelectionContentLayerState extends State<SelectionContentLayer> {
  SelectionToolbar? _toolbar;
  SelectionHandlesController? _handles;

  /// 祖先 Scrollable 的滚动位置(监听它驱动 toolbar 跟随)。
  ScrollPosition? _scrollPosition;

  SelectionExporter get _exporter =>
      SelectionExporter(widget.controller.registry);

  @override
  void initState() {
    super.initState();
    // 监听 controller:被全局协调器(其他帖起选)外部清空时,收掉本帖 toolbar
    // + 手柄;手柄拖动改选区时刷新手柄/toolbar 位置。
    widget.controller.addListener(_onControllerChanged);
  }

  void _onControllerChanged() {
    if (widget.controller.selection == null) {
      _toolbar?.hide();
      _toolbar = null;
      _handles?.hide();
    } else {
      // 选区变(含手柄拖动):刷新手柄位置。
      _handles?.update();
    }
  }

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

  void _onSelectionChanged(SelectionData? data, {bool fromTouch = false}) {
    _toolbar?.hide();
    _toolbar = null;
    if (data == null) {
      _handles?.hide();
      return;
    }
    _toolbar = _buildToolbar();
    _toolbar!.show(data);

    // 移动端(触摸选区)显示拖拽手柄;鼠标/触控板选区不显示。
    if (fromTouch) {
      (_handles ??= SelectionHandlesController(
        context: context,
        controller: widget.controller,
        // 拖手柄时隐藏 toolbar(不挡视线/放大镜),松手后按新选区重定位重显。
        onDragStart: () => _toolbar?.hide(),
        onDragEnd: _reshowToolbarForCurrentSelection,
      )).show();
    } else {
      _handles?.hide();
    }
  }

  /// 构建 toolbar(复制 / 复制引用 / 引用)。两处显示共用,避免回调漂移。
  SelectionToolbar _buildToolbar() {
    return SelectionToolbar(
      context: context,
      // 与内容同 groupId:点 toolbar 不触发 onTapOutside 清除。
      tapRegionGroupId: widget.controller,
      onQuote: (plainText) {
        widget.onQuoteRequest?.call(plainText);
        widget.controller.clear();
      },
      onCopyQuote: widget.onCopyQuoteRequest == null
          ? null
          : (plainText) {
              widget.onCopyQuoteRequest!.call(plainText);
              widget.controller.clear();
            },
      onCopied: widget.onCopyToast,
    );
  }

  /// 按当前选区重新构建并显示 toolbar(手柄拖动松手后用)。
  void _reshowToolbarForCurrentSelection() {
    final sel = widget.controller.selection;
    final data = sel == null ? null : _exporter.export(sel);
    if (data == null) return;
    _toolbar?.hide();
    _toolbar = _buildToolbar();
    _toolbar!.show(data);
  }

  /// 滚动时:toolbar + 手柄按当前选区重算几何并重定位(滚出视口自动隐藏)。
  void _onScroll() {
    final sel = widget.controller.selection;
    if (sel == null) return;
    _toolbar?.reposition(_exporter.export(sel));
    _handles?.update();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _scrollPosition?.removeListener(_onScroll);
    _toolbar?.hide();
    _handles?.hide();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // TapRegion:点选区/toolbar(同 groupId)**之外**的任意处 → 清除选区。
    // groupId 用本 controller 实例,各 post 独立组;toolbar 的 OverlayEntry 也
    // 用同 groupId(见 SelectionToolbar),故点 toolbar 不算 outside。
    return TapRegion(
      groupId: widget.controller,
      onTapOutside: (_) {
        if (widget.controller.selection != null) {
          widget.controller.clear();
        }
      },
      child: SelectionGestureLayer(
        controller: widget.controller,
        onSelectionChanged: _onSelectionChanged,
        child: widget.child,
      ),
    );
  }
}
