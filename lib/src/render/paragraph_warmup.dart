/// 段落渲染预热 —— 把「首见段落」也变成缓存命中。
///
/// ## 背景
///
/// FlattenCache + ParagraphLayoutCache 落地后,纯文字段落**回滚**已是
/// 零排版;但**首次滚进视口**仍要在滚动帧里付 flatten + 排版。本模块
/// 提供 idle 预热原语:滚动停止后,宿主(TopicPostList)在空闲帧对
/// 即将滚到的楼层逐段预 flatten + 预排版。纯文字可复用两层缓存；
/// 含链接或确定尺寸占位的段落复用排版，挂载时单独创建交互和组件。
///
/// ## key 同源(探针,预热命中率的命门)
///
/// 缓存 key 含 theme 色值与 env(挂载处 DefaultTextStyle
/// 派生)。预热侧手工重建这条链必然漂移(值等而实例不等、或构造逻辑
/// 复制后 drift),预热就全部白做。因此用**探针登记**:真实挂载的直绘
/// 块把自己 acquire/obtain 时用的 (baseStyle, theme, flattener) 与
/// (env, 宽度) 登记进 [ParagraphWarmupProbe](按出现次数计数,取众数
/// ——正文段落数量碾压 heading 等偏格,收敛快且自适应主题/字号切换)。
/// 首屏挂载几段后探针就绪,预热用探针快照构 key,与挂载 100% 同源。
///
/// 若探针登记的 theme 与预热 flatten 读色的 context 不一致(理论罕见),
/// 后果只是缓存 miss 重做,不会串色 —— 挂载路径永远自建正确产物。
library;

import 'package:material_ui/material_ui.dart';

import '../flatten/flatten_cache.dart';
import '../flatten/inline_flattener.dart';
import '../node/node.dart';
import 'cached_paragraph_text.dart';
import 'emoji_handler.dart';
import 'footnote_handler.dart';
import 'glyph_prebaker.dart';
import 'image_handler.dart';
import 'link_handler.dart';
import 'local_date_handler.dart';
import 'math_handler.dart';
import 'mention_handler.dart';

/// 直绘段落的样式快照(由 InlineSpanText 传给 CachedParagraphText 原子登记)。
@immutable
class ParagraphWarmupStyle {
  ParagraphWarmupStyle({
    required this.baseStyle,
    required this.theme,
    required this.flattener,
  }) : themeKey = FlattenThemeKey.fromTheme(theme);

  final TextStyle baseStyle;
  final ThemeData theme;
  final FlattenThemeKey themeKey;
  final InlineFlattener flattener;

  @override
  bool operator ==(Object other) =>
      other is ParagraphWarmupStyle &&
      other.baseStyle == baseStyle &&
      other.themeKey == themeKey &&
      identical(other.flattener, flattener);

  @override
  int get hashCode =>
      Object.hash(baseStyle, themeKey, identityHashCode(flattener));
}

/// 直绘段落的挂载环境快照(探针产物)。
class WarmupContext {
  const WarmupContext({
    required this.baseStyle,
    required this.theme,
    required this.flattener,
    required this.env,
    required this.minWidth,
    required this.maxWidth,
  });

  final TextStyle baseStyle;
  final ThemeData theme;
  final InlineFlattener flattener;
  final ParagraphEnv env;
  final double minWidth;
  final double maxWidth;

  /// 值语义环境指纹:用于宿主判断宽度/主题/字号是否已变更，从而重置预热游标。
  Object get environmentKey => (
        baseStyle,
        FlattenThemeKey.fromTheme(theme),
        identityHashCode(flattener),
        env,
        minWidth,
        maxWidth,
      );
}

/// 单个页面/列表作用域的活跃段落环境追踪器。
///
/// 按**当前已挂载的 RenderCachedParagraph 实例**实时维护环境样本:
/// - 宽度变化(如 280→360)、主题或字号变化时，已挂载段落会在 performLayout
///   里原地覆写自己的样本，旧宽度/旧样式立即消失，不会被历史计数压住；
/// - 段落卸载时从活跃表移除，保留最近一次有效快照供全量回收后继续预热；
/// - 不同页面各自持有独立 [ParagraphWarmupTracker]（经 [ParagraphWarmupScope]
///   注入），彻底避免上一页宽度或样式污染当前页预热。
class ParagraphWarmupTracker {
  final Map<Object, WarmupContext> _live = {};
  WarmupContext? _lastSnapshot;

  void put(Object owner, WarmupContext ctx) {
    _live.remove(owner); // 重插到尾部，保留最新顺序用于平票决胜
    _live[owner] = ctx;
    _lastSnapshot = null;
  }

  void remove(Object owner) {
    if (!_live.containsKey(owner)) return;
    if (_live.length == 1) {
      _lastSnapshot = _live[owner];
    }
    _live.remove(owner);
  }

  /// 当前作用域的最佳预热环境快照。
  ///
  /// 有活跃挂载段落时严格只从活跃样本里取众数（同票取更宽、更新的样本，
  /// 正文段落宽度大于引用/列表缩进）；全部卸载时退回最后一次有效快照。
  WarmupContext? snapshot() {
    if (_live.isEmpty) return _lastSnapshot;

    final counts = <_WarmupBucketKey, int>{};
    final latestByBucket = <_WarmupBucketKey, WarmupContext>{};
    final orderByBucket = <_WarmupBucketKey, int>{};
    var order = 0;
    for (final ctx in _live.values) {
      final bucket = _WarmupBucketKey.fromContext(ctx);
      counts[bucket] = (counts[bucket] ?? 0) + 1;
      latestByBucket[bucket] = ctx;
      orderByBucket[bucket] = order++;
    }

    _WarmupBucketKey? bestBucket;
    var bestCount = 0;
    var bestWidth = -1.0;
    var bestOrder = -1;
    counts.forEach((bucket, count) {
      final ctx = latestByBucket[bucket]!;
      final bucketOrder = orderByBucket[bucket]!;
      final better = count > bestCount ||
          (count == bestCount && ctx.maxWidth > bestWidth) ||
          (count == bestCount &&
              ctx.maxWidth == bestWidth &&
              bucketOrder > bestOrder);
      if (better) {
        bestBucket = bucket;
        bestCount = count;
        bestWidth = ctx.maxWidth;
        bestOrder = bucketOrder;
      }
    });

    final result = bestBucket == null ? null : latestByBucket[bestBucket!];
    if (result != null) {
      _lastSnapshot = result;
    }
    return result;
  }

  void reset() {
    _live.clear();
    _lastSnapshot = null;
  }
}

/// 为当前页面/列表子树隔离段落预热探针的轻量作用域。
class ParagraphWarmupScope extends InheritedWidget {
  const ParagraphWarmupScope({
    super.key,
    required this.tracker,
    required super.child,
  });

  final ParagraphWarmupTracker tracker;

  /// 只读查询(不注册 rebuild 依赖):tracker 本身是可变容器。
  static ParagraphWarmupTracker? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ParagraphWarmupScope>()?.tracker;

  @override
  bool updateShouldNotify(ParagraphWarmupScope oldWidget) =>
      !identical(tracker, oldWidget.tracker);
}

/// 挂载环境探针(默认全局入口，兼容未包裹 [ParagraphWarmupScope] 的场景)。
class ParagraphWarmupProbe {
  ParagraphWarmupProbe._();

  static final ParagraphWarmupTracker globalTracker = ParagraphWarmupTracker();

  static _StyleKey? _legacyLatestStyle;
  static _EnvKey? _legacyLatestEnv;

  /// 兼容接口:手动登记样式(独立调用时取最近一次样本)。
  static void noteStyle(
      TextStyle baseStyle, ThemeData theme, InlineFlattener flattener) {
    _legacyLatestStyle = _StyleKey(baseStyle, theme, flattener);
  }

  /// 兼容接口:手动登记布局环境(独立调用时取最近一次样本)。
  static void noteEnv(ParagraphEnv env, double minWidth, double maxWidth) {
    _legacyLatestEnv = _EnvKey(env, minWidth, maxWidth);
  }

  /// 当前全局探针快照:优先使用活跃实例追踪器，无活跃记录时退回手动登记。
  static WarmupContext? snapshot() {
    final tracked = globalTracker.snapshot();
    if (tracked != null) return tracked;
    final style = _legacyLatestStyle;
    final env = _legacyLatestEnv;
    if (style == null || env == null) return null;
    return WarmupContext(
      baseStyle: style.baseStyle,
      theme: style.theme,
      flattener: style.flattener,
      env: env.env,
      minWidth: env.minWidth,
      maxWidth: env.maxWidth,
    );
  }

  /// 清空全局探针(主题/字号切换或测试清理时调用)。
  static void reset() {
    globalTracker.reset();
    _legacyLatestStyle = null;
    _legacyLatestEnv = null;
  }
}

class _WarmupBucketKey {
  _WarmupBucketKey({
    required this.baseStyle,
    required this.themeKey,
    required this.flattener,
    required this.env,
    required this.minWidth,
    required this.maxWidth,
  });

  factory _WarmupBucketKey.fromContext(WarmupContext ctx) => _WarmupBucketKey(
        baseStyle: ctx.baseStyle,
        themeKey: FlattenThemeKey.fromTheme(ctx.theme),
        flattener: ctx.flattener,
        env: ctx.env,
        minWidth: ctx.minWidth,
        maxWidth: ctx.maxWidth,
      );

  final TextStyle baseStyle;
  final FlattenThemeKey themeKey;
  final InlineFlattener flattener;
  final ParagraphEnv env;
  final double minWidth;
  final double maxWidth;

  @override
  bool operator ==(Object other) =>
      other is _WarmupBucketKey &&
      other.baseStyle == baseStyle &&
      other.themeKey == themeKey &&
      identical(other.flattener, flattener) &&
      other.env == env &&
      other.minWidth == minWidth &&
      other.maxWidth == maxWidth;

  @override
  int get hashCode => Object.hash(
        baseStyle,
        themeKey,
        identityHashCode(flattener),
        env,
        minWidth,
        maxWidth,
      );
}

class _StyleKey {
  _StyleKey(this.baseStyle, this.theme, this.flattener)
      : themeKey = FlattenThemeKey.fromTheme(theme);

  final TextStyle baseStyle;
  final ThemeData theme;
  final FlattenThemeKey themeKey;
  final InlineFlattener flattener;

  @override
  bool operator ==(Object other) =>
      other is _StyleKey &&
      other.baseStyle == baseStyle &&
      other.themeKey == themeKey &&
      identical(other.flattener, flattener);

  @override
  int get hashCode =>
      Object.hash(baseStyle, themeKey, identityHashCode(flattener));
}

class _EnvKey {
  _EnvKey(this.env, this.minWidth, this.maxWidth);
  final ParagraphEnv env;
  final double minWidth;
  final double maxWidth;

  @override
  bool operator ==(Object other) =>
      other is _EnvKey &&
      other.env == env &&
      other.minWidth == minWidth &&
      other.maxWidth == maxWidth;

  @override
  int get hashCode => Object.hash(env, minWidth, maxWidth);
}

/// 段落预热器:对一个 post 的顶层段落逐个 flatten + 排版进全局缓存。
class ParagraphWarmup {
  ParagraphWarmup._();

  /// 预热统计(诊断)。
  static int warmedParagraphs = 0;

  /// 对 [nodes] 的顶层 ParagraphNode 从 [startIndex] 起逐段预热,
  /// 超 [budgetMicros] 即停。返回下一个待处理下标;全部完成返回 -1。
  ///
  /// - flatten:仅纯文字产物进入 FlattenCache，立即 release 后按 LRU
  ///   存活。带交互或内嵌组件的产物提取排版数据后立即释放;
  /// - 排版:尺寸已知且无行内代码/mention 的段落可预排版，只把文字、
  ///   样式和占位尺寸写入 ParagraphLayoutCache，挂载时独立创建交互;
  /// - [context] 仅供 flatten 同步读主题色;recognizer 点击走 mount 桥,
  ///   与预热时的 context 无关。
  static int warmParagraphs({
    required List<BlockNode> nodes,
    required WarmupContext ctx,
    required BuildContext context,
    required int totalImagesInPost,
    LinkActionHandler? linkHandler,
    EmojiImageBuilder? emojiImageBuilder,
    MentionTapHandler? mentionTapHandler,
    ImageContentBuilder? imageContentBuilder,
    FootnoteTapHandler? footnoteTapHandler,
    LocalDateBuilder? localDateBuilder,
    MathInlineBuilder? mathInlineBuilder,
    AttachmentDownloadHandler? onDownloadAttachment,
    GlyphPrebaker? glyphBaker,
    double? devicePixelRatio,
    int startIndex = 0,
    int budgetMicros = 4000,
  }) {
    final sw = Stopwatch()..start();
    final newlyLaidOut =
        glyphBaker == null ? null : <ParagraphLayoutEntry>[];
    var nextIndex = -1;
    for (var i = startIndex; i < nodes.length; i++) {
      if (sw.elapsedMicroseconds > budgetMicros) {
        nextIndex = i;
        break;
      }
      final node = nodes[i];
      if (node is! ParagraphNode) continue;
      final flat = FlattenCache.acquire(
        inlines: node.inlines,
        baseStyle: ctx.baseStyle,
        theme: ctx.theme,
        totalImagesInPost: totalImagesInPost,
        flattener: ctx.flattener,
        create: () => ctx.flattener.flatten(
          node.inlines,
          ctx.baseStyle,
          linkHandler: linkHandler,
          emojiImageBuilder: emojiImageBuilder,
          mentionTapHandler: mentionTapHandler,
          imageContentBuilder: imageContentBuilder,
          footnoteTapHandler: footnoteTapHandler,
          localDateBuilder: localDateBuilder,
          mathInlineBuilder: mathInlineBuilder,
          onDownloadAttachment: onDownloadAttachment,
          totalImagesInPost: totalImagesInPost,
          context: context,
        ),
      );
      // 直绘判据同 InlineSpanText；缓存 key 绝不能保留临时 flatten 产物。
      final projection = flat.projection;
      final data = flat.layoutData;
      if (data != null &&
          !projection.hasInlineCode && !projection.hasSpanMention) {
        final missesBefore = ParagraphLayoutCache.misses;
        final entry = ParagraphLayoutCache.obtain(
          data,
          ctx.env,
          ctx.minWidth,
          ctx.maxWidth,
        );
        if (newlyLaidOut != null && ParagraphLayoutCache.misses > missesBefore) {
          newlyLaidOut.add(entry);
        }
        warmedParagraphs++;
      }
      FlattenCache.release(flat); // 交互产物立即释放；纯文字留 LRU 待复用。
    }
    if (glyphBaker != null &&
        newlyLaidOut != null &&
        newlyLaidOut.isNotEmpty) {
      glyphBaker.enqueueEntries(
        newlyLaidOut,
        devicePixelRatio: devicePixelRatio ?? 1.0,
      );
    }
    return nextIndex;
  }
}
