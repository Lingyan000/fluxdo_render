/// 子包自带的选区 toolbar —— 选区稳定后在选区上方弹「复制 / 复制引用 / 引用」浮层。
///
/// - 复制:子包内 Clipboard.setData(代码块带 ```lang)。
/// - 复制引用:回调交主项目,主项目拼 [quote=...] BBCode 进剪贴板(需 post 元数据)。
/// - 引用:回调交主项目,打开回复框插入引用。
/// 用 OverlayEntry 浮在内容上方,避免被滚动裁剪。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'selection_data.dart';

class SelectionToolbar {
  SelectionToolbar({
    required this.context,
    required this.onQuote,
    required this.onCopied,
    this.onCopyQuote,
    this.tapRegionGroupId,
    this.copyLabel = '复制',
    this.copyQuoteLabel = '复制引用',
    this.quoteLabel = '引用',
  });

  final BuildContext context;
  final void Function(String plainText) onQuote;
  final VoidCallback? onCopied;

  /// 「复制引用」回调 —— 把选区纯文本交回主项目拼 BBCode 进剪贴板。
  /// null = 不显示该按钮(主项目未接入时)。
  final void Function(String plainText)? onCopyQuote;

  /// 与内容层同一 TapRegion groupId —— 点 toolbar 不触发内容的 onTapOutside。
  final Object? tapRegionGroupId;

  final String copyLabel;
  final String copyQuoteLabel;
  final String quoteLabel;

  // toolbar 估算高度(Material vertical padding 10×2 + 文本 ~20)+ 选区间距。
  static const double _toolbarHeight = 40;
  static const double _gap = 8;
  // 估算宽度(复制|复制引用|引用 三按钮:各 h16 padding + 文本 + 分隔线)。
  // 仅用于水平 shift 夹边的近似;Positioned 不限宽,真实宽由内容撑。
  static const double _estimatedWidth = 240;
  // 视口左右安全边距(对齐 fk-d-menu 的 padding.left/right = 10)。
  static const double _edgePadding = 10;

  OverlayEntry? _entry;

  /// 当前选区数据(可变)—— 滚动时由 [reposition] 更新,builder 内读最新值
  /// 实时算坐标,markNeedsBuild 即重定位。
  SelectionData? _data;

  /// 竖直滞后补偿(本帧 scroll delta)——滚动时 export 几何滞后一帧,_build 把
  /// 竖直坐标减去它 → 与内容同帧对齐,消抖。show(松手)时归零。
  double _yComp = 0;

  /// 冻结的水平位置 —— 竖直滚动不改选区水平,故 left 只在 show 时算一次缓存,
  /// 滚动 reposition 复用,避免「首个可见块切换」导致的左右抖。
  double? _cachedLeft;

  /// 在选区上方显示 toolbar。
  void show(SelectionData data) {
    _data = data;
    _yComp = 0;
    _cachedLeft = null;
    if (_entry != null) {
      _entry!.markNeedsBuild();
      return;
    }
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;

    _entry = OverlayEntry(builder: _build);
    overlay.insert(_entry!);
  }

  /// 滚动时调:更新选区几何并重定位。[yCompensation] = 本帧 scroll delta,
  /// 用于抵消 export 几何的一帧滞后(消抖,见 SelectionContentLayer._onScroll)。
  void reposition(SelectionData? data, {double yCompensation = 0}) {
    if (_entry == null) return;
    if (data == null) {
      hide();
      return;
    }
    _data = data;
    _yComp = yCompensation;
    _entry!.markNeedsBuild();
  }

  Widget _build(BuildContext ctx) {
    final data = _data;
    if (data == null) return const SizedBox.shrink();
    // 选区完全滚出视口(无可见块 → 无几何)→ 不显示(滚回视口再现),
    // 避免工具栏空浮在视口顶与可见内容脱节。
    if (data.globalRects.isEmpty) return const SizedBox.shrink();
    final overlay = Overlay.maybeOf(context);
    final overlayBox =
        overlay?.context.findRenderObject() as RenderBox?;
    if (overlayBox == null) return const SizedBox.shrink();

    // 选区外接框转 overlay 局部坐标(实时,跟随滚动)。
    final bounds = data.globalBounds;
    final tl = overlayBox.globalToLocal(bounds.topLeft);

    // 减 _yComp:抵消滚动时 export 几何的一帧滞后 → 与内容同帧对齐(消抖)。
    final selTop = tl.dy - _yComp;
    final selBottom = tl.dy + bounds.height - _yComp;

    // 顶部安全线(overlay 局部坐标):状态栏 + 一个标准 AppBar 高度。
    // overlay 通常铺满屏幕,其局部 0 == 屏幕顶,故直接用 padding.top +
    // kToolbarHeight 作局部 y 安全线;底部安全线 = 屏幕高 - 底部安全区。
    final mq = MediaQuery.maybeOf(ctx);
    final screenH = mq?.size.height ?? overlayBox.size.height;
    final minTop = (mq?.viewPadding.top ?? 0) + kToolbarHeight;
    final maxTop = screenH - (mq?.viewPadding.bottom ?? 0) - _toolbarHeight - _gap;

    // 垂直定位(对齐 Discourse fk-d-menu 的 flip + shift,**始终保持在视口内**):
    // ① 贴可见选区上方(top-start);② 上方放不下(选区顶出视口)→ 贴下方
    // (bottom-start);③ 上下都放不下(选区比视口还高、视口只显示选区中段)→
    // 夹到视口内,保证工具栏**始终可见**(之前会跑到屏幕外 → 看不见)。
    final aboveTop = selTop - _toolbarHeight - _gap;
    final belowTop = selBottom + _gap;
    double top;
    if (aboveTop >= minTop) {
      top = aboveTop;
    } else if (belowTop <= maxTop) {
      top = belowTop;
    } else {
      top = minTop; // 选区跨满视口:夹到视口顶,始终可见
    }
    if (maxTop >= minTop) top = top.clamp(minTop, maxTop);

    // 水平:左对齐**选区外接框左缘**(对齐 Discourse top-start = reference rect
    // 的 start),再 shift 夹回视口内(留 [_edgePadding] 边距)。
    //
    // **冻结水平 x 消左右抖**:竖直滚动不改变选区的水平位置,故 [left] 只在
    // show(选区定/变)时算一次并缓存;滚动 reposition 只动竖直、复用缓存。
    // (之前用 globalRects.first 的左缘 → 滚动时「首个可见块」切换导致 x 跳变
    //  → 工具栏左右抖;现改外接框左缘 + 冻结,彻底消除。)
    final screenW = mq?.size.width ?? overlayBox.size.width;
    final maxLeft = screenW - _estimatedWidth - _edgePadding;
    final left = _cachedLeft ??= (maxLeft <= _edgePadding
        ? _edgePadding // 屏幕比 toolbar 还窄的极端情况
        : tl.dx.clamp(_edgePadding, maxLeft));

    return Positioned(
      left: left,
      top: top,
      child: TapRegion(
        groupId: tapRegionGroupId,
        child: _ToolbarBody(
          copyLabel: copyLabel,
          copyQuoteLabel: copyQuoteLabel,
          quoteLabel: quoteLabel,
          onCopy: () {
            _copy(data);
            hide();
          },
          onCopyQuote: onCopyQuote == null
              ? null
              : () {
                  onCopyQuote!(data.plainText);
                  hide();
                },
          onQuote: () {
            onQuote(data.plainText);
            hide();
          },
        ),
      ),
    );
  }

  void hide() {
    _entry?.remove();
    _entry = null;
    _data = null;
    _cachedLeft = null;
  }

  void _copy(SelectionData data) {
    final code = data.code;
    final text = code != null
        ? '```${code.language ?? ''}\n${data.plainText}\n```'
        : data.plainText;
    Clipboard.setData(ClipboardData(text: text));
    onCopied?.call();
  }
}

class _ToolbarBody extends StatelessWidget {
  const _ToolbarBody({
    required this.copyLabel,
    required this.copyQuoteLabel,
    required this.quoteLabel,
    required this.onCopy,
    required this.onCopyQuote,
    required this.onQuote,
  });

  final String copyLabel;
  final String copyQuoteLabel;
  final String quoteLabel;
  final VoidCallback onCopy;
  final VoidCallback? onCopyQuote;
  final VoidCallback onQuote;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const radius = Radius.circular(8);
    const leftR = BorderRadius.only(topLeft: radius, bottomLeft: radius);
    const rightR = BorderRadius.only(topRight: radius, bottomRight: radius);

    Widget divider() => Container(
          width: 0.5,
          height: 24,
          color: scheme.onPrimaryContainer.withValues(alpha: 0.3),
        );

    final hasCopyQuote = onCopyQuote != null;
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(8),
      // 跟主题色挂钩:primaryContainer 底 + onPrimaryContainer 字(M3 推荐,
      // 有主题色倾向又不刺眼)。随明暗主题 + 自定义 seed 自动适配。
      color: scheme.primaryContainer,
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _btn(context, copyLabel, onCopy, scheme, leftR),
          divider(),
          if (hasCopyQuote) ...[
            _btn(context, copyQuoteLabel, onCopyQuote!, scheme, BorderRadius.zero),
            divider(),
          ],
          _btn(context, quoteLabel, onQuote, scheme, rightR),
        ],
      ),
    );
  }

  Widget _btn(
    BuildContext context,
    String label,
    VoidCallback onTap,
    ColorScheme scheme,
    BorderRadius radius,
  ) {
    // primaryContainer 背景上用 onPrimaryContainer 派生半透明做 hover/pressed,
    // 对比度足够且跟随主题。
    final fg = scheme.onPrimaryContainer;
    return InkWell(
      onTap: onTap,
      borderRadius: radius,
      hoverColor: fg.withValues(alpha: 0.08),
      highlightColor: fg.withValues(alpha: 0.12),
      splashColor: fg.withValues(alpha: 0.16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Text(
          label,
          style: TextStyle(color: fg, fontSize: 14),
        ),
      ),
    );
  }
}
