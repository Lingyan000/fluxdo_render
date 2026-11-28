/// 纯文字 flatten 产物的全局 LRU 缓存。
///
/// ## 为什么要全局
///
/// flatten 产物此前缓存在 InlineSpanText 的 State 里,sliver 回收(滚出
/// cacheExtent)即销毁,来回滚动反复重 flatten;正文布局缓存/idle 预热
/// 都需要一个"State 死了产物还在"的家 —— 与 RenderParseCache(解析层)
/// 同构,这里是 flatten 层。
///
/// ## 共享边界
///
/// [FlattenResult.canShare] 根据实际 span、手势和占位组件决定能否共享。
/// 带交互或内嵌组件的产物只交给当前调用方，不写入 LRU；调用方 release
/// 时立即释放手势。这样预热不会冻结默认回调，同文多处显示也不会串 context。
///
/// key = (inlines 身份, baseStyle, theme 色值, totalImagesInPost,
/// flattener 身份)。共享产物不含宿主行为，因此不需要把 handlers 放进 key。
///
/// ## 生命周期
///
/// - [acquire] refs+1,State dispose 时 [release] refs-1;
/// - 独占产物不进入 LRU，最后一个 release 立即释放;
/// - 共享产物被逐出后，仍被挂载引用的条目延迟到最后一个 release 释放;
/// - [evictAll](hot reload / 主题级失效)同规则。
///
/// 编辑器路径(EditableParagraph)不走本缓存(内容逐击键变化,缓存无意义),
/// 仍直接 flatten 并自持 recognizers —— [release] 对非缓存产物安全 no-op。
library;

import 'dart:collection';

import 'package:material_ui/material_ui.dart';

import '../node/inline_node.dart';
import 'inline_flattener.dart';

class FlattenCache {
  FlattenCache._();

  /// 条目上限。单条 ≈ 一个段落的 span 树 + projection(数 KB 级),
  /// 1024 条覆盖若干长帖的全部段落,量级几 MB。
  static const int _cap = 1024;

  static final LinkedHashMap<_FlattenKey, _FlattenEntry> _entries =
      LinkedHashMap();

  /// result → entry 反查(release 用)。dead 且未释放完的条目也在,
  /// 随最后一次 release 移除,有界于活跃挂载数。
  static final Map<FlattenResult, _FlattenEntry> _byResult = {};

  /// 命中统计(诊断用)。
  static int hits = 0;
  static int misses = 0;
  static int get length => _entries.length;

  /// miss 时的 flatten 计时上报钩子(主项目接 FrameJankMonitor.noteSpan;
  /// 不设则零成本)。
  static void Function(int micros)? profileHook;

  /// 取(或建)flatten 产物,refs+1。调用方(挂载 State)必须在 dispose
  /// 时 [release] 同一个 result。
  static FlattenResult acquire({
    required List<InlineNode> inlines,
    required TextStyle baseStyle,
    required ThemeData theme,
    required int totalImagesInPost,
    required InlineFlattener flattener,
    required FlattenResult Function() create,
  }) {
    final key = _FlattenKey(
      inlines,
      baseStyle,
      theme,
      totalImagesInPost,
      flattener,
    );
    final existing = _entries.remove(key);
    if (existing != null) {
      _entries[key] = existing; // LRU touch:重插到尾部
      existing.refs++;
      hits++;
      return existing.result;
    }
    misses++;
    final hook = profileHook;
    final sw = hook == null ? null : (Stopwatch()..start());
    final result = create();
    if (sw != null && hook != null) {
      sw.stop();
      hook(sw.elapsedMicroseconds);
    }
    final entry = _FlattenEntry(result)..refs = 1;
    _byResult[result] = entry;
    if (!result.canShare) {
      // 独占产物也沿用 acquire/release，避免调用方遗漏手势资源的释放。
      entry.dead = true;
      return result;
    }
    _entries[key] = entry;
    _evictOverflow();
    return result;
  }

  /// 归还引用。非本缓存的产物(编辑器直接 flatten 的)安全 no-op。
  static void release(FlattenResult result) {
    final entry = _byResult[result];
    if (entry == null) return;
    entry.refs--;
    if (entry.refs <= 0 && entry.dead) {
      _disposeEntry(entry);
    }
  }

  /// 全清(hot reload / 环境级失效):空闲条目立即释放,在用条目标记
  /// dead 待最后一次 release 释放。
  static void evictAll() {
    for (final entry in _entries.values) {
      if (entry.refs <= 0) {
        _disposeEntry(entry);
      } else {
        entry.dead = true;
      }
    }
    _entries.clear();
  }

  static void _evictOverflow() {
    while (_entries.length > _cap) {
      final oldestKey = _entries.keys.first;
      final entry = _entries.remove(oldestKey)!;
      if (entry.refs <= 0) {
        _disposeEntry(entry);
      } else {
        // 仍被挂载引用:延迟到最后一个 release 再 dispose,
        // 保证在屏 span 的 recognizer 始终可用。
        entry.dead = true;
      }
    }
  }

  static void _disposeEntry(_FlattenEntry entry) {
    for (final rec in entry.result.recognizers) {
      rec.dispose();
    }
    _byResult.remove(entry.result);
  }
}

class _FlattenEntry {
  _FlattenEntry(this.result);
  final FlattenResult result;
  int refs = 0;

  /// 已被逐出但仍有引用:最后一个 release 负责 dispose。
  bool dead = false;
}

/// flatten 期间同步读取的主题色摘要(值语义)。
///
/// 不能用 `identical(oldTheme, theme)` 做缓存 key:`Theme.of(context)`
/// 内部只缓存少量本地化结果,局部 `Theme(data: theme.copyWith(...))`
/// 即可把根主题挤出缓存,之后返回的 `ThemeData` 值完全一致但对象身份不同,
/// 会触发全应用文字缓存集体失效。
@immutable
class FlattenThemeKey {
  const FlattenThemeKey({
    required this.primary,
    required this.onSurfaceVariant,
  });

  factory FlattenThemeKey.fromTheme(ThemeData theme) {
    final scheme = theme.colorScheme;
    return FlattenThemeKey(
      primary: scheme.primary,
      onSurfaceVariant: scheme.onSurfaceVariant,
    );
  }

  final Color primary;
  final Color onSurfaceVariant;

  @override
  bool operator ==(Object other) =>
      other is FlattenThemeKey &&
      other.primary == primary &&
      other.onSurfaceVariant == onSurfaceVariant;

  @override
  int get hashCode => Object.hash(primary, onSurfaceVariant);
}

class _FlattenKey {
  _FlattenKey(
    this.inlines,
    this.baseStyle,
    ThemeData theme,
    this.totalImagesInPost,
    this.flattener,
  ) : themeKey = FlattenThemeKey.fromTheme(theme);

  final List<InlineNode> inlines;
  final TextStyle baseStyle;
  final FlattenThemeKey themeKey;
  final int totalImagesInPost;
  final InlineFlattener flattener;

  @override
  bool operator ==(Object other) =>
      other is _FlattenKey &&
      identical(other.inlines, inlines) &&
      other.baseStyle == baseStyle &&
      other.themeKey == themeKey &&
      other.totalImagesInPost == totalImagesInPost &&
      identical(other.flattener, flattener);

  @override
  int get hashCode => Object.hash(
        identityHashCode(inlines),
        baseStyle,
        themeKey,
        totalImagesInPost,
        identityHashCode(flattener),
      );
}
