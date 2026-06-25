/// 子包自带的选区 toolbar —— 选区稳定后在选区上方弹「复制 / 引用」浮层。
///
/// 复制:子包内 Clipboard.setData(代码块带 ```lang);引用:回调交主项目。
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
    this.copyLabel = '复制',
    this.quoteLabel = '引用',
  });

  final BuildContext context;
  final void Function(String plainText) onQuote;
  final VoidCallback? onCopied;

  final String copyLabel;
  final String quoteLabel;

  // toolbar 估算高度(Material vertical padding 10×2 + 文本 ~20)+ 选区间距。
  static const double _toolbarHeight = 40;
  static const double _gap = 8;

  OverlayEntry? _entry;

  /// 当前选区数据(可变)—— 滚动时由 [reposition] 更新,builder 内读最新值
  /// 实时算坐标,markNeedsBuild 即重定位。
  SelectionData? _data;

  /// 在选区上方显示 toolbar。
  void show(SelectionData data) {
    _data = data;
    if (_entry != null) {
      _entry!.markNeedsBuild();
      return;
    }
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;

    _entry = OverlayEntry(builder: _build);
    overlay.insert(_entry!);
  }

  /// 滚动时调:更新选区几何并重定位(滚出视口则隐藏内容但保留 entry)。
  void reposition(SelectionData? data) {
    if (_entry == null) return;
    if (data == null) {
      hide();
      return;
    }
    _data = data;
    _entry!.markNeedsBuild();
  }

  Widget _build(BuildContext ctx) {
    final data = _data;
    if (data == null) return const SizedBox.shrink();
    final overlay = Overlay.maybeOf(context);
    final overlayBox =
        overlay?.context.findRenderObject() as RenderBox?;
    if (overlayBox == null) return const SizedBox.shrink();

    // 选区外接框转 overlay 局部坐标(实时,跟随滚动)。
    final bounds = data.globalBounds;
    final tl = overlayBox.globalToLocal(bounds.topLeft);
    final selRectLocal = tl & bounds.size;
    // 选区完全滚出 overlay 可视区 → 隐藏(对齐系统视口隐藏行为)。
    if (!overlayBox.paintBounds.overlaps(selRectLocal)) {
      return const SizedBox.shrink();
    }
    final anchorCenterX = tl.dx + bounds.width / 2;
    final selTop = tl.dy;
    final selBottom = tl.dy + bounds.height;

    // 顶部安全线(overlay 局部坐标):状态栏 + 一个标准 AppBar 高度。
    // 用 MediaQuery,不猜具体 AppBar/标题位置 —— 上方放不下(toolbar 会越过
    // 这条线)就翻到选区下方。overlay 通常铺满屏幕,其局部 0 == 屏幕顶,故
    // 直接用 padding.top + kToolbarHeight 作局部 y 安全线。
    final mq = MediaQuery.maybeOf(ctx);
    final topInset =
        (mq?.viewPadding.top ?? 0) + kToolbarHeight;

    // 默认放选区上方;上方放不下则翻到选区下方(对齐系统 toolbar flip)。
    final aboveTop = selTop - _toolbarHeight - _gap;
    final top = aboveTop >= topInset ? aboveTop : selBottom + _gap;

    return Positioned(
      left: anchorCenterX - 80,
      top: top,
      child: _ToolbarBody(
        copyLabel: copyLabel,
        quoteLabel: quoteLabel,
        onCopy: () {
          _copy(data);
          hide();
        },
        onQuote: () {
          onQuote(data.plainText);
          hide();
        },
      ),
    );
  }

  void hide() {
    _entry?.remove();
    _entry = null;
    _data = null;
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
    required this.quoteLabel,
    required this.onCopy,
    required this.onQuote,
  });

  final String copyLabel;
  final String quoteLabel;
  final VoidCallback onCopy;
  final VoidCallback onQuote;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(8),
      color: scheme.inverseSurface,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _btn(context, copyLabel, onCopy, scheme),
          Container(width: 0.5, height: 24, color: scheme.onInverseSurface.withValues(alpha: 0.3)),
          _btn(context, quoteLabel, onQuote, scheme),
        ],
      ),
    );
  }

  Widget _btn(
    BuildContext context,
    String label,
    VoidCallback onTap,
    ColorScheme scheme,
  ) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Text(
          label,
          style: TextStyle(color: scheme.onInverseSurface, fontSize: 14),
        ),
      ),
    );
  }
}
