/// 行内节点 sealed family。
///
/// 阶段 1 范围:Text / Em / Strong / LineBreak / Link / InlineCode / Emoji /
/// Mention / Image
/// 后续会扩展更多行内节点(spoiler 等)。

library;

import 'package:flutter/foundation.dart';

/// 所有行内节点的基类。
@immutable
sealed class InlineNode {
  const InlineNode();
}

/// 纯文本片段。
@immutable
class TextRun extends InlineNode {
  const TextRun(this.text);

  final String text;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TextRun &&
          runtimeType == other.runtimeType &&
          text == other.text;

  @override
  int get hashCode => text.hashCode;

  @override
  String toString() => 'TextRun(${text.length} chars)';
}

/// `<em>` / `<i>` 斜体,可包含嵌套行内子节点。
@immutable
class EmRun extends InlineNode {
  const EmRun({required this.children});

  final List<InlineNode> children;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EmRun &&
          runtimeType == other.runtimeType &&
          listEquals(children, other.children);

  @override
  int get hashCode => Object.hashAll(children);

  @override
  String toString() => 'EmRun(${children.length} children)';
}

/// `<strong>` / `<b>` 粗体,可包含嵌套行内子节点。
@immutable
class StrongRun extends InlineNode {
  const StrongRun({required this.children});

  final List<InlineNode> children;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StrongRun &&
          runtimeType == other.runtimeType &&
          listEquals(children, other.children);

  @override
  int get hashCode => Object.hashAll(children);

  @override
  String toString() => 'StrongRun(${children.length} children)';
}

/// `<br>` 强制换行。
@immutable
class LineBreakRun extends InlineNode {
  const LineBreakRun();

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is LineBreakRun;

  @override
  int get hashCode => 0;

  @override
  String toString() => 'LineBreakRun()';
}

/// `<a href="...">` 链接,可嵌套行内子节点。
///
/// 点击行为不由子包决定 —— 渲染时通过 [NodeFactory.linkHandler] 注入,
/// 主项目负责 URL 路由(launchUrl / 内部话题跳转 / 用户卡跳转 等)。
///
/// 阶段 1 暂不带 click_count 注入(那是 post.linkCounts 数据,跟主项目
/// model 强耦合),留到阶段 2 link 体系细化时再加。
@immutable
class LinkRun extends InlineNode {
  const LinkRun({required this.href, required this.children});

  /// 已解析的链接 URL(parser 阶段不做 CDN 重写,显示给 LinkHandler)。
  final String href;

  /// 链接显示内容,可嵌套样式(em/strong)。
  final List<InlineNode> children;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LinkRun &&
          runtimeType == other.runtimeType &&
          href == other.href &&
          listEquals(children, other.children);

  @override
  int get hashCode => Object.hash(href, Object.hashAll(children));

  @override
  String toString() => 'LinkRun($href, ${children.length} children)';
}

/// `<code>` 行内代码片段。
///
/// 设计上**只持纯文本**,不再嵌套样式(跟浏览器 `<code>` 实际行为一致 ——
/// `<code>` 内的 `<strong>` 在 Discourse cooked 里会被保留,但视觉上
/// monospace 已盖住样式;且 inline code 主要意图是展示原始字面值,
/// 嵌套样式只会带来视觉噪音)。parser 收到嵌套样式时把所有 textContent
/// 拼成一段。
@immutable
class InlineCodeRun extends InlineNode {
  const InlineCodeRun(this.text);

  final String text;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InlineCodeRun &&
          runtimeType == other.runtimeType &&
          text == other.text;

  @override
  int get hashCode => text.hashCode;

  @override
  String toString() => 'InlineCodeRun(${text.length} chars)';
}

/// `<img class="emoji">` 行内表情图。
///
/// Discourse cooked 形态:
/// ```html
/// <img src="https://.../images/emoji/twitter/heart.png" alt=":heart:"
///      class="emoji" title=":heart:">
/// <img src="..." class="emoji only-emoji">  <!-- 整段独立大表情 -->
/// ```
///
/// 子包**不实际加载图片**:渲染时通过 [NodeFactory.emojiImageBuilder]
/// callback 由主项目注入(主项目用 emojiImageProvider + 独立缓存池)。
/// 子包默认 fallback 是 `Image.network`,便于 example gallery 演示。
///
/// **尺寸约定**:
/// - 普通 emoji:1em(跟随父字号,h1 里比 p 里大)
/// - only-emoji:32dp(对齐 Discourse `img.emoji.only-emoji { 32px }`)
@immutable
class EmojiRun extends InlineNode {
  const EmojiRun({
    required this.name,
    required this.url,
    this.isOnlyEmoji = false,
  });

  /// emoji 短名,如 'heart' / ':heart:' 去掉冒号,主要给可访问性 + 选区文本用。
  /// 可能为空串(alt/title 缺失时)。
  final String name;

  /// 完整图片 URL(parser 直接从 src 提取,**不做 CDN 重写**;
  /// CDN 重写由主项目在 emojiImageBuilder 内处理)。
  final String url;

  /// `class="only-emoji"` —— 整段仅含 emoji 的大表情,显示 32dp。
  final bool isOnlyEmoji;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EmojiRun &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          url == other.url &&
          isOnlyEmoji == other.isOnlyEmoji;

  @override
  int get hashCode => Object.hash(name, url, isOnlyEmoji);

  @override
  String toString() =>
      'EmojiRun($name${isOnlyEmoji ? ", only" : ""}, $url)';
}

/// `<a class="mention" href="/u/username">@username</a>` 用户提及。
///
/// 跟 LinkRun 是**平级 sibling**(parser 看到 a.mention 时优先产 MentionRun,
/// 不产 LinkRun)—— 因为 mention 的视觉/交互完全独立于普通链接:
/// chip 样式(灰底圆角)+ 跳用户卡(不是 launchUrl)。
///
/// 状态 emoji([statusEmoji])是 Discourse 注入到 mention link 内的
/// `<img class="emoji mention-status">`(显示用户在线/状态),parser
/// 把它从 a 子树里挑出来填到这个字段。**渲染时 emoji 在 username 右侧**。
///
/// tap 路由由主项目通过 [MentionTapHandler] 注入。
@immutable
class MentionRun extends InlineNode {
  const MentionRun({
    required this.username,
    required this.href,
    this.statusEmoji,
  });

  /// 去掉 `@` 前缀的纯用户名,如 `alice`。
  final String username;

  /// a 标签的 href 原值,如 `/u/alice`(parser 不做 URL 重写)。
  final String href;

  /// 用户状态 emoji(可选)。
  final EmojiRun? statusEmoji;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MentionRun &&
          runtimeType == other.runtimeType &&
          username == other.username &&
          href == other.href &&
          statusEmoji == other.statusEmoji;

  @override
  int get hashCode => Object.hash(username, href, statusEmoji);

  @override
  String toString() =>
      'MentionRun(@$username, $href${statusEmoji == null ? "" : ", emoji"})';
}

/// `<img>` 行内图片(不含 `class="emoji"` 的那种,emoji 走 [EmojiRun])。
///
/// Discourse cooked 形态:
/// ```html
/// <img src="https://.../upload/..." alt="screenshot" width="600" height="400">
/// <img src="https://example.com/foo.png">
/// ```
///
/// 子包**不实际加载图片 / 不做 gallery / 不做 lightbox**(主项目有 Hero
/// + 长按菜单 + upload:// 短链解析 + emojiImageProvider 等复杂逻辑),
/// 渲染时通过 [ImageContentBuilder] callback 由主项目注入。子包默认
/// fallback 是 `Image.network` + broken-image icon。
///
/// **不持 ImageProvider**:子包不依赖任何具体 image loading 实现,
/// 只把 raw src 字符串原值暴露给 builder,主项目自己解析 + 重写 CDN。
///
/// [indexInPost]:parser 在一次 parse 内按 image 出现顺序自增分配
/// (0, 1, 2, ...),给主项目算 Hero tag / gallery index 用。同一个
/// `<img src>` 在不同 post 内的 indexInPost 不同;**节点 == 比较时
/// 也参与**(防止重排时主项目误以为是同一张图)。
@immutable
class ImageRun extends InlineNode {
  const ImageRun({
    required this.src,
    this.alt = '',
    this.width,
    this.height,
    this.indexInPost = 0,
  });

  /// 完整图片 URL(parser 不做任何重写;含 upload:// 短链时由主项目解析)。
  final String src;

  /// alt 文本,a11y + 加载失败时占位。
  final String alt;

  /// HTML attribute 里的 width(px),null 表示由 builder 决定。
  final double? width;

  /// HTML attribute 里的 height(px),null 表示由 builder 决定。
  final double? height;

  /// 在当前 post 内的 0-based 顺序索引。parser 分配。
  ///
  /// 主项目接入示意:
  /// ```dart
  /// final heroTag = 'post_${post.id}_img_${image.indexInPost}';
  /// ```
  final int indexInPost;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ImageRun &&
          runtimeType == other.runtimeType &&
          src == other.src &&
          alt == other.alt &&
          width == other.width &&
          height == other.height &&
          indexInPost == other.indexInPost;

  @override
  int get hashCode => Object.hash(src, alt, width, height, indexInPost);

  @override
  String toString() =>
      'ImageRun(#$indexInPost $src'
      '${width == null ? "" : ", ${width}x$height"})';
}
