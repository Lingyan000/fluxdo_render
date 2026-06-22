/// Spoiler 粒子系统 —— 移植自 legacy
/// `lib/widgets/.../builders/spoiler_particles.dart`,并做性能优化(参考
/// Telegram 的粒子做法:批量绘制 + 不每帧重建 widget):
///
/// - 系统是 [ChangeNotifier],`update()` 推进后 `notifyListeners()`;
///   `CustomPaint(painter: …, repaint: system)` → **只重绘 CustomPaint,不
///   setState 重建 widget 子树**(原 legacy 每帧 setState 是主要开销)。
/// - 绘制用 `canvas.drawRawPoints`,按 3 档透明度分组**批量画点**(替代逐粒子
///   `drawCircle`,N 次 → 3 次 draw)。
/// - 死亡粒子用 `removeWhere`(O(n),替代原 O(n²) 逐个 remove)。
/// - 密度降低(面积/6,clamp 120~900),背景已不透明遮盖,粒子仅作纹理。
///
/// 未揭示时一团粒子云 + 不透明背景**完全遮盖**内容,点击后停动画露出。
library;

import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' show PointMode;

import 'package:flutter/material.dart';

/// 单个粒子。
class SpoilerParticle {
  SpoilerParticle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.life,
    required this.maxLife,
    required this.alphaType,
    this.boundingRect,
  });

  double x, y, vx, vy;
  double life, maxLife;
  int alphaType; // 0=0.3, 1=0.6, 2=1.0
  Rect? boundingRect;
}

/// 粒子系统(生成 / 更新);本身是 repaint Listenable。
class SpoilerParticleSystem extends ChangeNotifier {
  final List<SpoilerParticle> particles = [];
  final Random _random = Random();
  int _maxParticles = 200;
  List<Rect> _rects = [];

  /// 按区域初始化(密度 = 面积/6,clamp 120~900)。
  void initForRects(List<Rect> rects) {
    _rects = rects;
    if (rects.isEmpty) return;
    double totalArea = 0;
    for (final rect in rects) {
      totalArea += rect.width * rect.height;
    }
    _maxParticles = (totalArea / 6).clamp(120, 900).toInt();
    particles.clear();
    for (var i = 0; i < _maxParticles; i++) {
      _spawnParticle();
    }
    notifyListeners();
  }

  /// 按尺寸初始化(块级/行内单区域)。
  void initForSize(Size size) {
    initForRects([Rect.fromLTWH(0, 0, size.width, size.height)]);
  }

  void _spawnParticle() {
    if (_rects.isEmpty) return;
    double totalArea = 0;
    for (final rect in _rects) {
      totalArea += rect.width * rect.height;
    }
    var r = _random.nextDouble() * totalArea;
    Rect? selectedRect;
    for (final rect in _rects) {
      r -= rect.width * rect.height;
      if (r <= 0) {
        selectedRect = rect;
        break;
      }
    }
    selectedRect ??= _rects.last;

    final angle = _random.nextDouble() * 2 * pi;
    final velocity = 4 + _random.nextDouble() * 6;
    particles.add(SpoilerParticle(
      x: selectedRect.left + _random.nextDouble() * selectedRect.width,
      y: selectedRect.top + _random.nextDouble() * selectedRect.height,
      vx: cos(angle) * velocity,
      vy: sin(angle) * velocity,
      life: 1.0,
      maxLife: 1.0 + _random.nextDouble() * 2.0,
      alphaType: _random.nextInt(3),
      boundingRect: selectedRect,
    ));
  }

  /// 推进一帧(dtMs 毫秒)→ 通知重绘。
  void update(double dtMs) {
    if (_rects.isEmpty) return;
    final dtFactor = dtMs / 500.0;
    final lifeDt = dtMs / 1000.0;
    for (final p in particles) {
      p.x += p.vx * dtFactor;
      p.y += p.vy * dtFactor;
      p.life -= lifeDt / p.maxLife;
    }
    // O(n) 移除死亡/出界粒子。
    particles.removeWhere((p) {
      final bound = p.boundingRect ?? _rects.first;
      return p.life <= 0 ||
          p.x < bound.left - 5 ||
          p.x > bound.right + 5 ||
          p.y < bound.top - 5 ||
          p.y > bound.bottom + 5;
    });
    while (particles.length < _maxParticles) {
      _spawnParticle();
    }
    notifyListeners();
  }

  void clear() {
    particles.clear();
    _rects = [];
  }
}

/// 粒子绘制器:不透明背景填满 + 按 3 档透明度批量画点(drawRawPoints)。
class SpoilerParticlePainter extends CustomPainter {
  SpoilerParticlePainter({
    required this.system,
    required this.isDark,
    required this.backgroundColor,
    this.borderRadius = 4.0,
  }) : super(repaint: system);

  final SpoilerParticleSystem system;
  final bool isDark;
  final Color backgroundColor;
  final double borderRadius;

  // 3 档透明度对应的点直径(原 radius 0.7/0.6 → 直径)。
  static const _alphaLevels = [0.3, 0.6, 1.0];
  static const _diameters = [1.4, 1.2, 1.2];

  @override
  void paint(Canvas canvas, Size size) {
    final baseColor = isDark ? Colors.white : Colors.grey.shade800;
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(borderRadius));

    canvas.save();
    canvas.clipRRect(rrect);
    // 不透明背景完全遮盖内容(含 code 背景等)。
    canvas.drawRRect(rrect, Paint()..color = backgroundColor);

    // 按 alphaType 分 3 组,各组一次 drawRawPoints(替代逐粒子 drawCircle)。
    final buckets = [<double>[], <double>[], <double>[]];
    for (final p in system.particles) {
      final b = buckets[p.alphaType];
      b
        ..add(p.x)
        ..add(p.y);
    }
    for (var t = 0; t < 3; t++) {
      if (buckets[t].isEmpty) continue;
      final paint = Paint()
        ..color = baseColor.withValues(alpha: _alphaLevels[t])
        ..strokeCap = StrokeCap.round
        ..strokeWidth = _diameters[t];
      canvas.drawRawPoints(
        PointMode.points,
        Float32List.fromList(buckets[t]),
        paint,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(SpoilerParticlePainter old) =>
      old.isDark != isDark ||
      old.backgroundColor != backgroundColor ||
      old.system != system;
}
