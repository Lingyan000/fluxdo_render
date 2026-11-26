/// 离屏字形预烤器：在空闲帧将新排版的 [ui.Paragraph] 按真实设备像素比
/// （`devicePixelRatio`）离屏光栅化一次，提前把字形写入引擎 Glyph Atlas。
library;

import 'dart:collection';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/painting.dart' show Canvas, Offset;

import 'cached_paragraph_text.dart';

/// 带 DPR 缩放与全局串行背压的离屏字形预烤器。
///
/// 关键约束：
/// - **按物理像素比例烤**：用 `canvas.scale(dpr)` 并以物理像素尺寸调用
///   `picture.toImage`，确保高分屏（2x/3x）烤入图集的字形尺寸与真屏绘制一致；
/// - **全局串行背压**：同一时刻最多只允许一张离屏 `toImage` 在光栅线程
///   在途，避免连续空闲步把光栅队列塞满；
/// - **引用计数安全**：对来自 [ParagraphLayoutCache] 的条目，入队时
///   `retain()`、录制进 [ui.Picture] 后或取消时立即 `release()`，避免等待
///   期间 LRU 淘汰导致原生 Paragraph 悬空释放；
/// - **滚动即时取消**：滚动开始或页面卸载调用 [clear] / [dispose]，立即丢弃
///   未录制的队列并释放引用。
class GlyphPrebaker {
  GlyphPrebaker({this.shouldDefer});

  /// 返回 true 时暂停启动新的离屏光栅批次（例如用户开始拖动或滚动）。
  final bool Function()? shouldDefer;

  static const int _maxQueuedItems = 48;
  static const int _maxBatchItems = 16;
  static const int _maxTextureDim = 2048;

  static bool _globalInFlight = false;
  static final List<GlyphPrebaker> _waitingBakers = [];

  /// 诊断 / 测试统计。
  static int bakedBatches = 0;
  static int bakedParagraphs = 0;
  static double? lastBakedDpr;

  /// 测试钩子：捕获每次实际录制的 (段落数, 物理像素宽, 物理像素高, dpr)。
  @visibleForTesting
  static void Function(int count, int width, int height, double dpr)?
      debugOnBake;

  /// 测试钩子：替换底层 `picture.toImage` 执行器，便于稳定验证异步背压。
  @visibleForTesting
  static Future<void> Function(ui.Picture picture, int width, int height)?
      debugImageRunner;

  final Queue<_BakeItem> _queue = Queue();
  bool _disposed = false;

  int get pendingCount => _queue.length;

  /// 入队一批原生 [ui.Paragraph]（适用于不走手动 dispose 的段落，如话题卡）。
  void enqueueParagraphs(
    Iterable<ui.Paragraph> paragraphs, {
    required double devicePixelRatio,
  }) {
    if (_disposed) return;
    final dpr = devicePixelRatio.clamp(1.0, 4.0);
    for (final p in paragraphs) {
      _push(_BakeItem.paragraph(p, dpr));
    }
    _pump();
  }

  /// 入队一批 [ParagraphLayoutEntry]（自动 retain/release，防 LRU 淘汰悬空）。
  void enqueueEntries(
    Iterable<ParagraphLayoutEntry> entries, {
    required double devicePixelRatio,
  }) {
    if (_disposed) return;
    final dpr = devicePixelRatio.clamp(1.0, 4.0);
    for (final entry in entries) {
      if (entry.isDisposed) continue;
      entry.retain();
      _push(_BakeItem.entry(entry, dpr));
    }
    _pump();
  }

  void _push(_BakeItem item) {
    while (_queue.length >= _maxQueuedItems) {
      _queue.removeFirst().release();
    }
    _queue.addLast(item);
  }

  /// 清空尚未录制的队列（滚动开始时调用），释放所有持有的缓存引用。
  void clear() {
    while (_queue.isNotEmpty) {
      _queue.removeFirst().release();
    }
    _waitingBakers.remove(this);
  }

  /// 页面/组件销毁时调用。
  void dispose() {
    _disposed = true;
    clear();
  }

  void _pump() {
    if (_disposed || _queue.isEmpty) return;
    if (shouldDefer?.call() ?? false) {
      // 拖动/滚动中放弃待烤队列，等停稳后由预热重新驱动。
      clear();
      return;
    }
    if (_globalInFlight) {
      if (!_waitingBakers.contains(this)) {
        _waitingBakers.add(this);
      }
      return;
    }

    // 同一批只合并相同 dpr 的段落（绝大多数情况全局 dpr 恒定）。
    final batch = <_BakeItem>[];
    final targetDpr = _queue.first.dpr;
    while (_queue.isNotEmpty &&
        batch.length < _maxBatchItems &&
        (_queue.first.dpr - targetDpr).abs() < 0.01) {
      batch.add(_queue.removeFirst());
    }
    if (batch.isEmpty) return;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(targetDpr);
    var logicalW = 1.0;
    var logicalH = 1.0;
    var drawn = 0;

    for (final item in batch) {
      final p = item.paragraph;
      if (p != null) {
        canvas.drawParagraph(p, Offset.zero);
        if (p.longestLine > logicalW) logicalW = p.longestLine;
        if (p.height > logicalH) logicalH = p.height;
        drawn++;
      }
      // 录制进 Picture 后立即归还 entry 引用，Picture 独立持有绘制指令。
      item.release();
    }

    final picture = recorder.endRecording();
    if (drawn == 0) {
      picture.dispose();
      _pump();
      return;
    }

    final physW = (logicalW * targetDpr).ceil().clamp(1, _maxTextureDim);
    final physH = (logicalH * targetDpr).ceil().clamp(1, _maxTextureDim);

    bakedBatches++;
    bakedParagraphs += drawn;
    lastBakedDpr = targetDpr;
    debugOnBake?.call(drawn, physW, physH, targetDpr);

    _globalInFlight = true;
    if (_queue.isNotEmpty && !_waitingBakers.contains(this)) {
      _waitingBakers.add(this);
    }
    final runner = debugImageRunner ?? _defaultRunToImage;
    runner(picture, physW, physH).catchError((_) {}).whenComplete(() {
      picture.dispose();
      _globalInFlight = false;
      _drainWaiting();
    });
  }

  static Future<void> _defaultRunToImage(
    ui.Picture picture,
    int width,
    int height,
  ) async {
    final img = await picture.toImage(width, height);
    img.dispose();
  }

  static void _drainWaiting() {
    while (!_globalInFlight && _waitingBakers.isNotEmpty) {
      final next = _waitingBakers.removeAt(0);
      next._pump();
    }
  }

  @visibleForTesting
  static void resetStatsForTesting() {
    bakedBatches = 0;
    bakedParagraphs = 0;
    lastBakedDpr = null;
    debugOnBake = null;
    debugImageRunner = null;
    _globalInFlight = false;
    _waitingBakers.clear();
  }
}

class _BakeItem {
  _BakeItem.paragraph(ui.Paragraph paragraph, this.dpr)
      : _paragraph = paragraph,
        _entry = null;

  _BakeItem.entry(ParagraphLayoutEntry entry, this.dpr)
      : _paragraph = null,
        _entry = entry;

  final ui.Paragraph? _paragraph;
  final ParagraphLayoutEntry? _entry;
  final double dpr;
  bool _released = false;

  ui.Paragraph? get paragraph {
    final entry = _entry;
    if (entry != null) {
      return entry.isDisposed ? null : entry.paragraph;
    }
    return _paragraph;
  }

  void release() {
    if (_released) return;
    _released = true;
    _entry?.release();
  }
}
