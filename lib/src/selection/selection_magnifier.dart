/// 选区放大镜 —— 拖拽手柄/选区时显示放大预览,看清手指下的字。
///
/// 用 Flutter SDK 的 [RawMagnifier](不引入 TextMagnifier 那套系统选区耦合):
/// RawMagnifier 用 BackdropFilter 矩阵变换放大「它下方已绘制的内容」,放在
/// 顶层 Overlay 即放大整页。关键(已查 SDK magnifier.dart):
///   focalPointOffset = 焦点全局坐标 - 镜子全局中心(相对镜子自身中心,非全局)。
///
/// 定位对齐 SDK TextMagnifier(material/magnifier.dart)/ CupertinoTextMagnifier:
/// - **焦点指文字,不指手指**:X 跟手势、Y 锁 caretRect.center.dy(被拖端所在
///   行的行中心)。手指在手柄上、低于文本一整行,若焦点跟手指,镜里放大的是
///   手指/手柄而非要选的字。
/// - 镜子放在行上方 [_kVerticalFocalPointShift],夹屏内;夹移后焦点补偿回行中心。
library;

import 'package:flutter/material.dart';

class SelectionMagnifier {
  SelectionMagnifier(this.context);

  final BuildContext context;

  OverlayEntry? _entry;
  Offset? _gesture; // 手势全局坐标(定镜子 X)
  Rect? _caretRect; // 被拖端 caret 全局矩形(定焦点/镜子 Y = 行中心)

  bool get isShowing => _entry != null;

  /// 显示/更新放大镜。[gestureGlobal] 手势全局坐标(镜子跟它水平移动);
  /// [caretRect] 被拖端点的 caret 全局矩形(焦点锁定其行中心,对齐 SDK
  /// MagnifierInfo.caretRect)。
  void show({required Offset gestureGlobal, required Rect caretRect}) {
    _gesture = gestureGlobal;
    _caretRect = caretRect;
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
    _gesture = null;
    _caretRect = null;
  }

  /// 镜子中心相对焦点(行中心)的上移量(对齐 Material
  /// kStandardVerticalFocalPointShift≈22 + 半镜高的观感,取手柄之上不遮挡)。
  static const double _kVerticalFocalPointShift = 48;

  Widget _build(BuildContext ctx) {
    final gesture = _gesture;
    final caret = _caretRect;
    if (gesture == null || caret == null) return const SizedBox.shrink();

    final isIOS = Theme.of(context).platform == TargetPlatform.iOS;
    final size = isIOS ? const Size(80, 48) : const Size(88, 44);
    const scale = 1.4;

    // 焦点 = (手势 X, 行中心 Y) —— 镜里永远是被拖那一行的文字。
    final focal = Offset(gesture.dx, caret.center.dy);

    // 镜子中心放在**行**上方(不是手指上方),夹在屏内。
    final screen = MediaQuery.of(ctx).size;
    final centerX = focal.dx.clamp(size.width / 2, screen.width - size.width / 2);
    final centerY = (focal.dy - _kVerticalFocalPointShift)
        .clamp(size.height / 2, screen.height - size.height / 2);
    final center = Offset(centerX, centerY);

    return Positioned(
      left: center.dx - size.width / 2,
      top: center.dy - size.height / 2,
      child: IgnorePointer(
        child: RawMagnifier(
          size: size,
          magnificationScale: scale,
          // 关键:相对镜子自身中心的偏移 = 焦点全局 - 镜子全局中心。
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
