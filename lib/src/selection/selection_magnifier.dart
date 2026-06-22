/// 选区放大镜 —— 拖拽手柄/选区时显示放大预览,看清手指下的字。
///
/// 用 Flutter SDK 的 [RawMagnifier](不引入 TextMagnifier 那套系统选区耦合):
/// RawMagnifier 用 BackdropFilter 矩阵变换放大「它下方已绘制的内容」,放在
/// 顶层 Overlay 即放大整页。关键(已查 SDK magnifier.dart):
///   focalPointOffset = 手指全局坐标 - 镜子全局中心(相对镜子自身中心,非全局)。
///
/// 平台适配:iOS 圆角椭圆 loupe(1.0x 习惯,但只读放大用 1.25 更实用),
/// Android 圆角矩形(1.25x)。两者都用圆角矩形近似,尺寸略调。
library;

import 'package:flutter/material.dart';

class SelectionMagnifier {
  SelectionMagnifier(this.context);

  final BuildContext context;

  OverlayEntry? _entry;
  Offset? _focal; // 当前聚焦的全局坐标(手指/拖动点)

  bool get isShowing => _entry != null;

  /// 显示/更新放大镜,聚焦到 [global](手指全局坐标)。
  void show(Offset global) {
    _focal = global;
    if (_entry != null) {
      _entry!.markNeedsBuild();
      return;
    }
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;
    _entry = OverlayEntry(builder: _build);
    overlay.insert(_entry!);
  }

  void hide() {
    _entry?.remove();
    _entry = null;
    _focal = null;
  }

  Widget _build(BuildContext ctx) {
    final focal = _focal;
    if (focal == null) return const SizedBox.shrink();

    final isIOS = Theme.of(context).platform == TargetPlatform.iOS;
    final size = isIOS ? const Size(80, 48) : const Size(88, 44);
    const scale = 1.4;
    // 镜子中心放在手指**上方**(避免被手指遮挡),夹在屏内。
    final screen = MediaQuery.of(ctx).size;
    final centerX = focal.dx.clamp(size.width / 2, screen.width - size.width / 2);
    final centerY =
        (focal.dy - 72).clamp(size.height / 2, screen.height - size.height / 2);
    final center = Offset(centerX, centerY);

    return Positioned(
      left: center.dx - size.width / 2,
      top: center.dy - size.height / 2,
      child: IgnorePointer(
        child: RawMagnifier(
          size: size,
          magnificationScale: scale,
          // 关键:相对镜子自身中心的偏移 = 手指全局 - 镜子全局中心。
          focalPointOffset: focal - center,
          decoration: MagnifierDecoration(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(isIOS ? 40 : 12),
              side: BorderSide(
                color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.4),
                width: 0.5,
              ),
            ),
            shadows: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 6,
                offset: Offset(0, 2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
