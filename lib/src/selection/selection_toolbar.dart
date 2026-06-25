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

  OverlayEntry? _entry;

  /// 在选区上方显示 toolbar。
  void show(SelectionData data) {
    hide();
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;

    final bounds = data.globalBounds;
    // 转成 overlay 局部坐标。
    final overlayBox = overlay.context.findRenderObject() as RenderBox?;
    if (overlayBox == null) return;
    final topLeft = overlayBox.globalToLocal(bounds.topLeft);
    final anchorCenterX = topLeft.dx + bounds.width / 2;
    final anchorTopY = topLeft.dy;

    _entry = OverlayEntry(
      builder: (ctx) {
        return Positioned(
          // 居中于选区上方,稍微抬起。
          left: anchorCenterX - 80,
          top: (anchorTopY - 48).clamp(0.0, double.infinity),
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
      },
    );
    overlay.insert(_entry!);
  }

  void hide() {
    _entry?.remove();
    _entry = null;
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
