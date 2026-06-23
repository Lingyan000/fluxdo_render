/// 渲染引擎灰度开关数据模型。
///
/// 用法:
/// ```dart
/// // 子包内只定义数据 + 序列化,不持久化
/// final config = RenderConfig.defaults().copyWith(
///   overrides: {NodeKind.paragraph: RenderEngine.newImpl},
/// );
/// final json = config.toJson();
///
/// // 主项目里有个 RenderConfigStore 实现把 json 存到 SharedPreferences
/// ```
library;

import 'dart:convert';

import '../dual/dual_render_widget.dart';

/// 节点类型。**必须与 test/fixtures/ 目录名 + golden 目录名一一对应**。
///
/// 这是项目内"节点"的唯一权威定义。新增节点时:
/// 1. 在这里加 enum 值
/// 2. 在 test/fixtures/ 下加同名目录
/// 3. 在 NodeFactory 里实现对应 buildXxx
enum NodeKind {
  paragraph,
  heading,
  list,
  codeBlock,
  quoteCard,
  spoiler,
  details,
  onebox,
  table,
  poll,
  math,
  iframe,
  imageGrid,
  lazyVideo,
  footnote,
  mention,
  emoji,
  lightbox,
  inlineCode,
  blockquote,
  callout,
  chatTranscript,
  localDate,
  policy,
  horizontalRule,
  image;

  /// 与 fixture 目录名一致的字符串(snake_case)。
  String get dirName => switch (this) {
        NodeKind.paragraph => 'paragraph',
        NodeKind.heading => 'heading',
        NodeKind.list => 'list',
        NodeKind.codeBlock => 'code_block',
        NodeKind.quoteCard => 'quote_card',
        NodeKind.spoiler => 'spoiler',
        NodeKind.details => 'details',
        NodeKind.onebox => 'onebox',
        NodeKind.table => 'table',
        NodeKind.poll => 'poll',
        NodeKind.math => 'math',
        NodeKind.iframe => 'iframe',
        NodeKind.imageGrid => 'image_grid',
        NodeKind.lazyVideo => 'lazy_video',
        NodeKind.footnote => 'footnote',
        NodeKind.mention => 'mention',
        NodeKind.emoji => 'emoji',
        NodeKind.lightbox => 'lightbox',
        NodeKind.inlineCode => 'inline_code',
        NodeKind.blockquote => 'blockquote',
        NodeKind.callout => 'callout',
        NodeKind.chatTranscript => 'chat_transcript',
        NodeKind.localDate => 'local_date',
        NodeKind.policy => 'policy',
        NodeKind.horizontalRule => 'horizontal_rule',
        NodeKind.image => 'image',
      };

  /// 节点的英文显示名,作为 fallback 显示。
  ///
  /// 调用方(主项目)需要做本地化时,**不要直接用这个字段**,而是
  /// 用 `NodeKind.name`(如 `'paragraph'`)作为 l10n key 查表。
  /// 子包不应承载用户面文本。
  String get label => switch (this) {
        NodeKind.paragraph => 'Paragraph',
        NodeKind.heading => 'Heading',
        NodeKind.list => 'List',
        NodeKind.codeBlock => 'Code block',
        NodeKind.quoteCard => 'Quote card',
        NodeKind.spoiler => 'Spoiler',
        NodeKind.details => 'Details',
        NodeKind.onebox => 'Onebox',
        NodeKind.table => 'Table',
        NodeKind.poll => 'Poll',
        NodeKind.math => 'Math',
        NodeKind.iframe => 'Iframe',
        NodeKind.imageGrid => 'Image grid',
        NodeKind.lazyVideo => 'Lazy video',
        NodeKind.footnote => 'Footnote',
        NodeKind.mention => 'Mention',
        NodeKind.emoji => 'Emoji',
        NodeKind.lightbox => 'Lightbox',
        NodeKind.inlineCode => 'Inline code',
        NodeKind.blockquote => 'Blockquote',
        NodeKind.callout => 'Callout',
        NodeKind.chatTranscript => 'Chat transcript',
        NodeKind.localDate => 'Local date',
        NodeKind.policy => 'Policy',
        NodeKind.horizontalRule => 'Horizontal rule',
        NodeKind.image => 'Image',
      };

  /// 根据 dirName 反查。未知值返回 null。
  static NodeKind? fromDirName(String dir) {
    for (final k in NodeKind.values) {
      if (k.dirName == dir) return k;
    }
    return null;
  }
}

/// 单个节点的渲染引擎选择。
enum RenderEngine {
  /// 用旧引擎(flutter_widget_from_html)渲染。所有节点的默认值。
  legacy,

  /// 用新引擎(fluxdo_render)渲染。
  newImpl,

  /// 两边都渲染,叠加显示对比(对应 DualRenderMode.overlay)。
  /// dogfood 期使用,production 不应出现。
  both;

  /// 引擎的英文显示名,作为 fallback。
  ///
  /// 同 [NodeKind.label]:调用方做本地化时应用 `RenderEngine.name`
  /// 作为 l10n key 查表。
  String get label => switch (this) {
        RenderEngine.legacy => 'Legacy',
        RenderEngine.newImpl => 'New',
        RenderEngine.both => 'Both (overlay)',
      };

  /// 把 RenderEngine 映射到 DualRenderMode。
  /// 调用方在主项目里接线时,用这个直接喂给 DualRenderWidget。
  DualRenderMode get dualMode => switch (this) {
        RenderEngine.legacy => DualRenderMode.legacy,
        RenderEngine.newImpl => DualRenderMode.newOnly,
        RenderEngine.both => DualRenderMode.overlay,
      };
}

/// 整个渲染引擎的灰度配置 = 全局默认 + 节点级覆盖。
///
/// 查询某节点的引擎选择:`config.engineFor(NodeKind.paragraph)`
///   - 如果 overrides 里有,返回覆盖值
///   - 否则返回 defaultEngine
class RenderConfig {
  const RenderConfig({
    required this.defaultEngine,
    required this.overrides,
  });

  /// 所有节点的兜底引擎(未在 overrides 里指定的节点用这个)。
  final RenderEngine defaultEngine;

  /// 节点级覆盖。
  final Map<NodeKind, RenderEngine> overrides;

  /// 阶段 0 - 阶段 5 期间的默认配置:所有节点都走 legacy。
  ///
  /// 每个节点完成 PR + dogfood 一周后,把对应节点的默认改成 newImpl
  /// (但 RenderConfig.defaults() 默认值保持 legacy,实际生效在主项目
  /// 的"已完成节点清单"里)。
  factory RenderConfig.defaults() {
    return const RenderConfig(
      defaultEngine: RenderEngine.legacy,
      overrides: {},
    );
  }

  /// 节点 → 引擎查询。
  RenderEngine engineFor(NodeKind kind) {
    return overrides[kind] ?? defaultEngine;
  }

  RenderConfig copyWith({
    RenderEngine? defaultEngine,
    Map<NodeKind, RenderEngine>? overrides,
  }) {
    return RenderConfig(
      defaultEngine: defaultEngine ?? this.defaultEngine,
      overrides: overrides ?? this.overrides,
    );
  }

  /// 设置某节点的覆盖(返回新 RenderConfig)。
  /// 把 engine 设为 null 等于移除覆盖(回归 defaultEngine)。
  RenderConfig withOverride(NodeKind kind, RenderEngine? engine) {
    final next = Map<NodeKind, RenderEngine>.from(overrides);
    if (engine == null) {
      next.remove(kind);
    } else {
      next[kind] = engine;
    }
    return copyWith(overrides: next);
  }

  /// JSON 序列化(给 Store 实现持久化用)。
  /// 形态:
  /// ```json
  /// {"default": "legacy", "overrides": {"paragraph": "newImpl"}}
  /// ```
  Map<String, dynamic> toJson() {
    return {
      'default': defaultEngine.name,
      'overrides': {
        for (final e in overrides.entries) e.key.dirName: e.value.name,
      },
    };
  }

  /// JSON 反序列化。容错:未识别的 enum 值忽略,落回默认。
  factory RenderConfig.fromJson(Map<String, dynamic> json) {
    final defaultName = json['default'] as String?;
    final defaultEngine = RenderEngine.values.firstWhere(
      (e) => e.name == defaultName,
      orElse: () => RenderEngine.legacy,
    );

    final overridesRaw = json['overrides'] as Map<String, dynamic>? ?? const {};
    final overrides = <NodeKind, RenderEngine>{};
    for (final entry in overridesRaw.entries) {
      final kind = NodeKind.fromDirName(entry.key);
      if (kind == null) continue;
      final engine = RenderEngine.values
          .where((e) => e.name == entry.value as String?)
          .firstOrNull;
      if (engine == null) continue;
      overrides[kind] = engine;
    }
    return RenderConfig(defaultEngine: defaultEngine, overrides: overrides);
  }

  /// 字符串序列化(便利方法)。
  String toJsonString() => jsonEncode(toJson());

  /// 字符串反序列化(便利方法)。
  static RenderConfig fromJsonString(String s) =>
      RenderConfig.fromJson(jsonDecode(s) as Map<String, dynamic>);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! RenderConfig) return false;
    if (defaultEngine != other.defaultEngine) return false;
    if (overrides.length != other.overrides.length) return false;
    for (final entry in overrides.entries) {
      if (other.overrides[entry.key] != entry.value) return false;
    }
    return true;
  }

  @override
  int get hashCode {
    var hash = defaultEngine.hashCode;
    for (final entry in overrides.entries) {
      hash ^= entry.key.hashCode ^ entry.value.hashCode;
    }
    return hash;
  }
}

/// Store 抽象:子包不直接依赖 SharedPreferences,主项目实现。
///
/// 主项目示例(基于 riverpod + SharedPreferences):
/// ```dart
/// class PrefsRenderConfigStore implements RenderConfigStore {
///   final SharedPreferences prefs;
///   PrefsRenderConfigStore(this.prefs);
///
///   @override
///   RenderConfig load() {
///     final s = prefs.getString('renderConfig');
///     return s == null ? RenderConfig.defaults() : RenderConfig.fromJsonString(s);
///   }
///
///   @override
///   Future<void> save(RenderConfig config) =>
///       prefs.setString('renderConfig', config.toJsonString());
/// }
/// ```
abstract class RenderConfigStore {
  RenderConfig load();
  Future<void> save(RenderConfig config);
}
