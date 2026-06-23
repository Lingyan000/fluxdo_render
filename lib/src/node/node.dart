/// 渲染节点的根类型族。
///
/// 数据模型设计原则:
/// - sealed class + Dart 3 switch exhaustiveness,新增节点必须改所有 dispatch
/// - 全部 immutable,`==`/`hashCode` 让 widget rebuild diff 廉价
/// - 块级与行内严格分层:`BlockNode` 顶层渲染,行内只在某 `BlockNode` 内
/// - 每个 `BlockNode` 自带稳定 `id` — 为阶段 5 自研选区
///   (`LogicalPosition { blockId, inlineIndex, charOffset }`)铺路
///
/// 阶段 1.1 范围:Paragraph + 行内 Text/Em/Strong/LineBreak
/// 后续阶段会扩展 HeadingNode / ListNode / CodeBlockNode 等。

library;

import 'package:flutter/foundation.dart';

import 'inline_node.dart';

export 'inline_node.dart';

/// 所有块级节点的基类。
///
/// 一份 cooked HTML 解析后产物是 `List<BlockNode>`。每个 BlockNode
/// 自带稳定 [id],由 parser 在解析时分配("b_0", "b_1", ...),同一份
/// HTML 解析两次 id 相同。
///
/// id 仅作"节点身份"用,**不参与 ==/hashCode**(让节点 immutable +
/// 内容比较仍然便宜)。阶段 5 自研选区时 `LogicalPosition` 用 id
/// 寻址,行内通过 (id, inlineIndex, charOffset) 三元组定位。
@immutable
sealed class BlockNode {
  const BlockNode({required this.id});

  final String id;
}

/// 段落 — 一段连续的行内内容。
///
/// 对应 HTML 中的 `<p>...</p>`。
@immutable
class ParagraphNode extends BlockNode {
  const ParagraphNode({required super.id, required this.inlines});

  /// 段落内的行内节点序列。
  final List<InlineNode> inlines;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ParagraphNode &&
          runtimeType == other.runtimeType &&
          listEquals(inlines, other.inlines);

  @override
  int get hashCode => Object.hashAll(inlines);

  @override
  String toString() => 'ParagraphNode($id, ${inlines.length} inlines)';
}

/// 标题 — h1/h2/h3/h4/h5/h6,字号由 [level] 决定。
///
/// 对应 HTML 中的 `<h1>` - `<h6>`。
@immutable
class HeadingNode extends BlockNode {
  const HeadingNode({
    required super.id,
    required this.level,
    required this.inlines,
  }) : assert(level >= 1 && level <= 6, 'heading level must be 1..6');

  /// 标题级别,1-6。
  final int level;

  /// 标题内的行内节点序列。
  final List<InlineNode> inlines;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HeadingNode &&
          runtimeType == other.runtimeType &&
          level == other.level &&
          listEquals(inlines, other.inlines);

  @override
  int get hashCode => Object.hash(level, Object.hashAll(inlines));

  @override
  String toString() => 'HeadingNode($id, h$level, ${inlines.length} inlines)';
}

/// 列表项 — 一行 inline 内容 + 可选嵌套子列表(li 内 ul/ol)。
///
/// 不是 BlockNode,只是 ListNode 内部的数据结构。
@immutable
class ListItem {
  const ListItem({
    required this.inlines,
    this.children,
  });

  /// 列表项的 inline 内容(li 直属 text/em/link/...)。
  final List<InlineNode> inlines;

  /// 嵌套子列表(li 内含 ul/ol),null 表示叶子项。
  final List<ListNode>? children;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ListItem &&
          runtimeType == other.runtimeType &&
          listEquals(inlines, other.inlines) &&
          listEquals(children, other.children);

  @override
  int get hashCode => Object.hash(
        Object.hashAll(inlines),
        children == null ? 0 : Object.hashAll(children!),
      );

  @override
  String toString() => 'ListItem(${inlines.length} inlines'
      '${children == null ? "" : ", ${children!.length} sub-lists"})';
}

/// 列表 — `<ul>` 或 `<ol>`,可嵌套。
///
/// 对应 HTML 中的 `<ul>...</ul>` / `<ol>...</ol>`。深度 [depth] 由 parser
/// 在递归时填(顶层 0,每嵌套一层 +1),renderer 用 depth 决定缩进倍数。
///
/// 视觉对齐 legacy(DiscourseHtmlContentWidget customStylesBuilder):
///   ul/ol: padding-left 20px, margin 8px 上下
///   li:    margin 4px 上下, line-height 1.5
///   有序列表 marker 用等宽数字(FontFeature.tabularFigures)。
@immutable
class ListNode extends BlockNode {
  const ListNode({
    required super.id,
    required this.ordered,
    required this.items,
    this.depth = 0,
  });

  /// true = `<ol>`(有序,marker 是数字),false = `<ul>`(无序,marker 是 ·)
  final bool ordered;

  /// 列表项序列。
  final List<ListItem> items;

  /// 嵌套深度(顶层 = 0)。
  final int depth;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ListNode &&
          runtimeType == other.runtimeType &&
          ordered == other.ordered &&
          depth == other.depth &&
          listEquals(items, other.items);

  @override
  int get hashCode => Object.hash(ordered, depth, Object.hashAll(items));

  @override
  String toString() =>
      'ListNode($id, ${ordered ? "ol" : "ul"}, depth=$depth, ${items.length} items)';
}

/// 引用块 — `<blockquote>`,内部含任意 BlockNode 子节点(支持嵌套)。
///
/// 视觉对齐 legacy(`blockquote_builder.dart` 普通引用分支):
///   margin 上下 8
///   padding L 12 / 上下 8 / R 12
///   背景 colorScheme.surfaceContainerHighest @ 0.3
///   左边 4px outline 竖条
///   右上 / 右下 圆角 4
///   字色 onSurfaceVariant + 行高 1.5
///
/// **Obsidian Callout**(`[!note]` / `[!warning]` 等)是 Discourse 在
/// blockquote 内的特殊语法,渲染为带图标的彩色卡片 —— 那是独立节点
/// (`NodeKind.callout`),阶段 1 不在 scope,parser 暂时把 callout 形态
/// 当普通 blockquote 处理。
@immutable
class BlockquoteNode extends BlockNode {
  const BlockquoteNode({required super.id, required this.children});

  /// 引用块内部的块级子节点(可嵌套 blockquote / paragraph / list)。
  final List<BlockNode> children;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BlockquoteNode &&
          runtimeType == other.runtimeType &&
          listEquals(children, other.children);

  @override
  int get hashCode => Object.hashAll(children);

  @override
  String toString() =>
      'BlockquoteNode($id, ${children.length} children)';
}

/// 分割线 — `<hr>`。无字段。
///
/// 视觉对齐 legacy:`vertical padding 12 + 1px line(outlineVariant @ 0.5)`。
///
/// id 仍存在(BlockNode 协议要求),给阶段 5 自研选区时按 id 寻址用。
@immutable
class HorizontalRuleNode extends BlockNode {
  const HorizontalRuleNode({required super.id});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HorizontalRuleNode && runtimeType == other.runtimeType;

  @override
  int get hashCode => 0;

  @override
  String toString() => 'HorizontalRuleNode($id)';
}

/// 代码块 — `<pre><code>`,可带语言标识。
///
/// 视觉对齐 legacy `code_block_builder.dart`:
///   灰底容器(surfaceContainer)+ 圆角 8
///   顶栏:语言 chip + 复制按钮
///   主体:横向滚动 + monospace + 行号(可选)
///
/// **不含语法高亮**:子包不依赖 highlight.js / mermaid / chart 等
/// 重量级库,通过 [CodeBlockHighlighter] callback 由主项目注入。
/// 不传时纯 monospace 显示。
///
/// [language] 是 cooked HTML 里 `class="lang-xxx"` 提取的语言标识
/// (`'dart'` / `'python'` / `'mermaid'` 等);无则 null。
@immutable
class CodeBlockNode extends BlockNode {
  const CodeBlockNode({
    required super.id,
    required this.code,
    this.language,
  });

  /// 代码原始字面值(parser 已解码 HTML 实体,末尾换行已去掉)。
  final String code;

  /// 语言标识(小写),如 `'dart'` / `'python'` / `'mermaid'`;
  /// 未指定 / 未识别时 null。
  final String? language;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CodeBlockNode &&
          runtimeType == other.runtimeType &&
          code == other.code &&
          language == other.language;

  @override
  int get hashCode => Object.hash(code, language);

  @override
  String toString() =>
      'CodeBlockNode($id, lang=${language ?? "?"}, ${code.length} chars)';
}

/// 回复引用卡 — `<aside class="quote">`,Discourse 最常见的"@回复"形态。
///
/// HTML 形态(简化):
/// ```html
/// <aside class="quote" data-username="alice" data-post="3" data-topic="999">
///   <div class="title">
///     <img class="avatar" src="...">
///     alice:
///     <a href="/t/topic-slug/999/3">原帖标题</a>
///   </div>
///   <blockquote>
///     <p>这是被引用的内容</p>
///   </blockquote>
/// </aside>
/// ```
///
/// 视觉对齐 legacy `quote_card_builder.dart`:
///   margin 上下 8;灰底 + 左 4px 竖条 + 右上右下圆角 4
///   头部:头像 + "username:" + 可选标题(主色)
///   内容:嵌套 BlockNode 递归渲染(走 buildBlockquote 同样的子样式)
///
/// **不持 categoryHtml**:Discourse badge 是独立组件,主项目接入再补。
/// 头像复用主项目 [imageContentBuilder](通过一个 ImageRun adapter),
/// 这样头像也走 discourseImageProvider 缓存池。
@immutable
class QuoteCardNode extends BlockNode {
  const QuoteCardNode({
    required super.id,
    required this.username,
    this.avatarUrl,
    this.titleText,
    this.titleHref,
    this.topicId,
    this.postNumber,
    this.children = const [],
  });

  /// `data-username`,主项目用它构造用户卡跳转(同 MentionRun.username)。
  /// 缺失时空串。
  final String username;

  /// `img.avatar` 的 src(原始 URL,parser 不重写)。
  /// 缺失时 null,渲染走首字母 chip fallback。
  final String? avatarUrl;

  /// 引用标题的文本(legacy 是 html,我们简化为 text)。
  final String? titleText;

  /// 引用标题里的 `<a href>`,主项目用 LinkHandler 跳原帖。
  /// 优先级:有 titleHref → 用它;无则 topicId + postNumber 拼。
  final String? titleHref;

  /// `data-topic`(`int.tryParse` 失败时 null)。
  final int? topicId;

  /// `data-post`(`int.tryParse` 失败时 null)。
  final int? postNumber;

  /// `<blockquote>` 内的递归 BlockNode。
  final List<BlockNode> children;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is QuoteCardNode &&
          runtimeType == other.runtimeType &&
          username == other.username &&
          avatarUrl == other.avatarUrl &&
          titleText == other.titleText &&
          titleHref == other.titleHref &&
          topicId == other.topicId &&
          postNumber == other.postNumber &&
          listEquals(children, other.children);

  @override
  int get hashCode => Object.hash(
        username,
        avatarUrl,
        titleText,
        titleHref,
        topicId,
        postNumber,
        Object.hashAll(children),
      );

  @override
  String toString() =>
      'QuoteCardNode($id, @$username'
      '${topicId == null ? "" : ", t=$topicId/p=$postNumber"}, '
      '${children.length} children)';
}

/// 块级 spoiler — `<div class="spoiler">`,默认遮蔽,点击展开。
///
/// 视觉(子包简化版,无粒子动画):
///   未揭示:灰底框 + "点击显示剧透" 提示
///   揭示后:正常渲染 children
///
/// 状态由 NodeFactory 内的 StatefulWidget 管。阶段 5 自研选区时再
/// 加粒子动画。
@immutable
class SpoilerBlockNode extends BlockNode {
  const SpoilerBlockNode({required super.id, required this.children});

  /// 被遮蔽的块级子节点(可嵌套 paragraph / list / blockquote 等)。
  final List<BlockNode> children;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SpoilerBlockNode &&
          runtimeType == other.runtimeType &&
          listEquals(children, other.children);

  @override
  int get hashCode => Object.hashAll(children);

  @override
  String toString() =>
      'SpoilerBlockNode($id, ${children.length} children)';
}

/// Onebox 类型 —— 跟 legacy `OneboxType` enum 一致(`docs/node_priority.md`
/// 阶段 2 第 1 节点)。
///
/// 子包**只识别归类**,不实现真渲染:
/// - 6 大类(github / video / social / tech / user / default)
/// - 主项目 OneboxBuilder callback 内根据 [kind] dispatch 到具体 builder
///
/// 不细化 GitHub 子类型(repo/blob/issue/pr/commit/...)— 主项目 builder
/// 内基于 url 自己再细分。子包暴露 [OneboxNode.url] 即可。
enum OneboxKind {
  /// `class="user-onebox"` — 用户卡(头像 + 名字 + bio)
  user,

  /// `class="github-onebox" | "onebox-github" | "github*"` —— GitHub 系列
  github,

  /// twitter / reddit / instagram / threads / tiktok
  social,

  /// youtube / vimeo / loom
  video,

  /// stackexchange / hackernews / pastebin / googledocs / pdf / amazon
  tech,

  /// 通用链接预览卡片(无明确类型识别 / `class="onebox"` 兜底)
  defaultKind,
}

/// 链接预览卡片 — `<aside class="onebox">`(Discourse 经典外链卡)。
///
/// HTML 形态:Discourse 后端用 onebox gem 抓取目标 URL 元数据,渲染成
/// 一个 `<aside class="onebox <type>-onebox">` 卡片,典型字段:
/// - `header > a.source` / `.source a` — 来源(站点名)
/// - `img.site-icon` / `img.favicon` — 站点图标
/// - `h3 a` / `h4 a` — 标题
/// - `p` — 描述
/// - `img.thumbnail` / `.aspect-image img` — 缩略图
///
/// 子包只提结构化关键字段 + 保留 [rawHtml] 兜底。主项目 OneboxBuilder
/// callback 拿 [kind] dispatch 到 6 种子 builder(legacy 已有完整实现,
/// 直接调即可,不必移植 4000 行)。
///
/// 不传 OneboxBuilder 时子包用通用卡片样式渲染(对齐 legacy
/// `default_onebox_builder`)。
@immutable
class OneboxNode extends BlockNode {
  const OneboxNode({
    required super.id,
    required this.kind,
    this.url,
    this.title,
    this.description,
    this.faviconUrl,
    this.thumbnailUrl,
    this.sourceName,
    this.rawHtml = '',
  });

  /// Onebox 类型(给主项目 builder dispatch 用)。
  final OneboxKind kind;

  /// 卡片对应的真实 URL(`data-onebox-src` 优先,fallback 到 header a /
  /// h3 a / h4 a 的 href)。null 表示未识别(罕见,容错占位)。
  final String? url;

  /// 标题(典型来自 `h3 a` / `h4 a` 的 text)。
  final String? title;

  /// 描述(典型来自 `p` 的 text)。
  final String? description;

  /// 站点图标(典型来自 `img.site-icon` / `img.favicon` 的 src)。
  final String? faviconUrl;

  /// 缩略图(典型来自 `img.thumbnail` / `.aspect-image img` 的 src)。
  final String? thumbnailUrl;

  /// 站点名(典型来自 `.source a` 的 text)。
  final String? sourceName;

  /// 原始 cooked HTML 片段(`aside.onebox.outerHtml`)。
  ///
  /// 给主项目 builder 兜底用:legacy 的 GitHub/video/social 等
  /// builder 大量依赖 DOM 内部结构(如 `.github-row` / `.author` /
  /// `.body` 等),结构化字段拿不全,需要 rawHtml 重 parse。
  /// 不强制使用,主项目 builder 优先用结构化字段。
  final String rawHtml;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OneboxNode &&
          runtimeType == other.runtimeType &&
          kind == other.kind &&
          url == other.url &&
          title == other.title &&
          description == other.description &&
          faviconUrl == other.faviconUrl &&
          thumbnailUrl == other.thumbnailUrl &&
          sourceName == other.sourceName &&
          rawHtml == other.rawHtml;

  @override
  int get hashCode => Object.hash(
        kind,
        url,
        title,
        description,
        faviconUrl,
        thumbnailUrl,
        sourceName,
        rawHtml,
      );

  @override
  String toString() =>
      'OneboxNode($id, $kind${url == null ? "" : ", $url"})';
}

/// Obsidian Callout 类型 — 对齐 legacy `callout_config.dart::getCalloutConfig`
/// 13 大类。
///
/// Discourse 在 `<blockquote>` 内首段以 `[!type]` 起头表示 callout(Obsidian
/// 语法),渲染成带图标的彩色卡片。子包只识别归类 + 暴露字段;具体颜色 /
/// 图标在 NodeFactory.buildCallout 内按 kind 派发(对齐 legacy)。
///
/// `unknown` = legacy 里走 "未知类型 → 灰色 + 首字母大写" 兜底分支。
enum CalloutKind {
  note,
  summary,
  info,
  todo,
  tip,
  success,
  question,
  warning,
  failure,
  danger,
  bug,
  example,
  quote,
  unknown;

  /// 解析 type 关键字到 enum(对齐 legacy 别名)。
  ///
  /// 未识别返回 [unknown](保留原始 typeRaw,渲染层做首字母大写标题)。
  static CalloutKind fromType(String type) {
    switch (type) {
      case 'note':
        return CalloutKind.note;
      case 'abstract':
      case 'summary':
      case 'tldr':
        return CalloutKind.summary;
      case 'info':
        return CalloutKind.info;
      case 'todo':
        return CalloutKind.todo;
      case 'tip':
      case 'hint':
      case 'important':
        return CalloutKind.tip;
      case 'success':
      case 'check':
      case 'done':
        return CalloutKind.success;
      case 'question':
      case 'help':
      case 'faq':
        return CalloutKind.question;
      case 'warning':
      case 'caution':
      case 'attention':
        return CalloutKind.warning;
      case 'failure':
      case 'fail':
      case 'missing':
        return CalloutKind.failure;
      case 'danger':
      case 'error':
        return CalloutKind.danger;
      case 'bug':
        return CalloutKind.bug;
      case 'example':
        return CalloutKind.example;
      case 'quote':
      case 'cite':
        return CalloutKind.quote;
      default:
        return CalloutKind.unknown;
    }
  }
}

/// Obsidian Callout — `<blockquote><p>[!type](+|-)?\s*title<br>...</p>...</blockquote>`。
///
/// HTML 形态(简化):
/// ```html
/// <blockquote>
///   <p>[!note]+ 提示标题<br>提示正文第一行</p>
///   <p>提示正文第二段</p>
/// </blockquote>
/// ```
///
/// 标记规则:
/// - `[!type]` — 不可折叠(`foldable=null`)
/// - `[!type]+` — 可折叠,默认展开(`foldable=true`)
/// - `[!type]-` — 可折叠,默认折叠(`foldable=false`)
/// - `[!type]` 后空格 + 自定义标题(可空,空时用 kind 默认标题)
///
/// 视觉对齐 legacy `callout_builder.dart`:
///   margin 上下 8;callout 主色背景 @ 10% + 左 4px 主色竖条 + 右上右下圆角 4
///   头部:Row(icon 18px + 标题 + 可折叠箭头)
///   内容:Padding(12, 8, 12, 12) + DefaultTextStyle(onSurfaceVariant + 1.5)
///   可折叠:头部点击切换 + heightFactor 200ms easeInOut + 箭头旋转 0→0.5 turns
///
/// **简化**:
/// - 不持原始 cooked html;首段 callout 标记行在 parser 阶段就被剥掉,
///   children 已是"正文 BlockNode"。
/// - title 只持纯文本(legacy 支持 titleHtml 渲染样式,简化忽略 ——
///   实际几乎所有 callout 标题都是纯文本)。
@immutable
class CalloutNode extends BlockNode {
  const CalloutNode({
    required super.id,
    required this.kind,
    required this.typeRaw,
    this.title,
    this.foldable,
    this.children = const [],
  });

  /// 识别后的类型;[CalloutKind.unknown] 时用 [typeRaw] 做首字母大写默认标题。
  final CalloutKind kind;

  /// 原始 type 字符串(已 lowercase),保留给 [CalloutKind.unknown] 兜底
  /// 显示用("[!xyz]" → typeRaw="xyz",默认标题渲染成 "Xyz")。
  final String typeRaw;

  /// 自定义标题(`[!type] 这里的标题`),空时 NodeFactory 用 kind 默认值。
  final String? title;

  /// 折叠形态:`null` = 不可折叠;`true` = 可折叠 + 默认展开;
  /// `false` = 可折叠 + 默认折叠。
  final bool? foldable;

  /// 正文 BlockNode(parser 已把首段 callout 标记行剥掉)。
  final List<BlockNode> children;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CalloutNode &&
          runtimeType == other.runtimeType &&
          kind == other.kind &&
          typeRaw == other.typeRaw &&
          title == other.title &&
          foldable == other.foldable &&
          listEquals(children, other.children);

  @override
  int get hashCode => Object.hash(
        kind,
        typeRaw,
        title,
        foldable,
        Object.hashAll(children),
      );

  @override
  String toString() =>
      'CalloutNode($id, $kind${title == null ? "" : "/\"$title\""}'
      '${foldable == null ? "" : ", foldable=$foldable"}, '
      '${children.length} children)';
}

/// 折叠块 — `<details><summary>标题</summary>内容</details>`。
///
/// 视觉对齐 legacy `details_builder.dart`:
///   外:margin 上下 8 + outline 边框 + 圆角 8
///   头:可点击灰底 + 旋转箭头 + summary 文字
///   体:折叠时不构建,展开后递归渲染 [children];动画 200ms easeInOut
///
/// `<details open>` 默认展开;无 `open` 默认折叠。
///
/// **简化**:
/// - summary 只持纯文本(legacy 也只用 text,不渲染嵌套样式)
/// - 不做"渐进式分块渲染"(legacy 用 HtmlChunker 切长内容降低首屏卡顿;
///   子包 parser 速度比 legacy 快 10x,无必要分块)
@immutable
class DetailsNode extends BlockNode {
  const DetailsNode({
    required super.id,
    required this.summary,
    required this.children,
    this.initiallyOpen = false,
  });

  /// summary 文本(`<summary>` 子节点的 textContent)。
  /// 空时主项目 / 子包应用本地化兜底标签("详情"/"Details")。
  final String summary;

  /// `<details>` 内除 summary 外的所有块级子节点(递归 parse)。
  final List<BlockNode> children;

  /// `<details open>` 属性,默认 false。
  final bool initiallyOpen;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DetailsNode &&
          runtimeType == other.runtimeType &&
          summary == other.summary &&
          initiallyOpen == other.initiallyOpen &&
          listEquals(children, other.children);

  @override
  int get hashCode => Object.hash(
        summary,
        initiallyOpen,
        Object.hashAll(children),
      );

  @override
  String toString() =>
      'DetailsNode($id, "$summary", ${children.length} children'
      '${initiallyOpen ? ", open" : ""})';
}

/// 数一份 BlockNode 树里所有 [ImageRun] 的总数。
///
/// FluxdoRender 在 parse 完成后调用一次,把结果通过 NodeFactory 传到
/// ImageContentBuilder,主项目用这个数构造 gallery viewer 的 totalCount。
int countImageRuns(List<BlockNode> nodes) {
  var count = 0;
  void scanInlines(List<InlineNode> inlines) {
    for (final n in inlines) {
      switch (n) {
        case ImageRun():
          count++;
        case EmRun(:final children):
          scanInlines(children);
        case StrongRun(:final children):
          scanInlines(children);
        case LinkRun(:final children):
          scanInlines(children);
        case SpoilerRun(:final children):
          scanInlines(children);
        case TextRun():
        case LineBreakRun():
        case InlineCodeRun():
        case EmojiRun():
        case MentionRun():
          // 这些 inline 节点不会含 ImageRun(MentionRun 的 statusEmoji 是
          // EmojiRun 不是 ImageRun)
          break;
      }
    }
  }

  void scanBlock(BlockNode b) {
    switch (b) {
      case ParagraphNode(:final inlines):
        scanInlines(inlines);
      case HeadingNode(:final inlines):
        scanInlines(inlines);
      case ListNode(:final items):
        for (final item in items) {
          scanInlines(item.inlines);
          if (item.children != null) {
            for (final sub in item.children!) {
              scanBlock(sub);
            }
          }
        }
      case BlockquoteNode(:final children):
        for (final c in children) {
          scanBlock(c);
        }
      case QuoteCardNode(:final children):
        for (final c in children) {
          scanBlock(c);
        }
      case SpoilerBlockNode(:final children):
        for (final c in children) {
          scanBlock(c);
        }
      case HorizontalRuleNode():
        break;
      case CodeBlockNode():
        break;
      case OneboxNode():
        // onebox 内部图片(thumbnail / favicon)不计入 ImageRun gallery
        break;
      case DetailsNode(:final children):
        for (final c in children) {
          scanBlock(c);
        }
      case CalloutNode(:final children):
        for (final c in children) {
          scanBlock(c);
        }
    }
  }

  for (final b in nodes) {
    scanBlock(b);
  }
  return count;
}
