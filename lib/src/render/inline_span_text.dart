/// 渲染一段含 LinkRun 等需要 GestureRecognizer 的行内内容。
///
/// 纯文字产物经 [FlattenCache] 跨挂载复用；带交互或内嵌组件的产物
/// 由当前 State 独占，回调变化时更新，卸载时释放。

library;

import 'package:material_ui/material_ui.dart';

import '../flatten/flatten_cache.dart';
import '../flatten/inline_flattener.dart';
import '../node/inline_node.dart';
import '../selection/projection.dart';
import 'cached_paragraph_text.dart';
import 'emoji_handler.dart';
import 'footnote_handler.dart';
import 'image_handler.dart';
import 'link_handler.dart';
import 'local_date_handler.dart';
import 'math_handler.dart';
import 'mention_handler.dart';
import 'paragraph_warmup.dart';
import 'selectable_text_box.dart';

class InlineSpanText extends StatefulWidget {
  /// 测试钩子:强制走 RichText 路径(生成双路径对照基线用)。
  /// golden 流程:开着它 + 确定性 emoji builder 重锁基线(基线 =
  /// RichText 形态)→ 关掉跑 golden = 直绘 vs RichText 的像素级对照。
  @visibleForTesting
  static bool debugForceRichText = false;

  const InlineSpanText({
    super.key,
    required this.inlines,
    required this.baseStyle,
    this.documentOrder = 0,
    this.chunkIndex = 0,
    this.flattener = const InlineFlattener(),
    this.linkHandler,
    this.emojiImageBuilder,
    this.mentionTapHandler,
    this.imageContentBuilder,
    this.footnoteTapHandler,
    this.localDateBuilder,
    this.mathInlineBuilder,
    this.onDownloadAttachment,
    this.totalImagesInPost = 0,
    this.textAlign,
    this.maxLines,
    this.overflow = TextOverflow.clip,
  });

  final List<InlineNode> inlines;
  final TextStyle baseStyle;

  /// 块在 chunk 内的文档序(见 SelectableBlockId / document_order.dart)。
  final int documentOrder;

  /// 所属 chunk 的文档序号(整帖渲染时 0)。
  final int chunkIndex;

  final InlineFlattener flattener;
  final LinkActionHandler? linkHandler;
  final EmojiImageBuilder? emojiImageBuilder;
  final MentionTapHandler? mentionTapHandler;
  final ImageContentBuilder? imageContentBuilder;
  final FootnoteTapHandler? footnoteTapHandler;
  final LocalDateBuilder? localDateBuilder;
  final MathInlineBuilder? mathInlineBuilder;
  /// 附件下载回调(主项目注入)。null 时附件 tap 降级到 linkHandler。
  final AttachmentDownloadHandler? onDownloadAttachment;
  final int totalImagesInPost;
  final TextAlign? textAlign;

  /// 最大行数(null=不限)。引用卡标题传 1 做单行省略。
  final int? maxLines;

  /// 文本溢出处理(默认 clip;引用卡标题传 ellipsis)。
  final TextOverflow overflow;

  @override
  State<InlineSpanText> createState() => _InlineSpanTextState();
}

class _InlineSpanTextState extends State<InlineSpanText> {
  /// 当前持有的 flatten 产物，统一通过 acquire/release 管理。
  /// 纯文字可共享；包含回调或内嵌组件时仅在本 State 内复用。
  FlattenResult? _result;

  // ---- acquire key 快照(判断是否需要换引用) ----
  List<InlineNode>? _keyInlines;
  TextStyle? _keyBaseStyle;
  ThemeData? _keyThemeRaw;
  FlattenThemeKey? _keyTheme;
  InlineFlattener? _keyFlattener;
  int _keyTotalImages = -1;

  /// 当前选区映射表(供 SelectableTextBox 读取),与 span 同源。
  RenderTextProjection get _projection =>
      _result?.projection ?? RenderTextProjection.empty;

  // 点击代理跟随 State 存活，调用时读取当前 widget。只换回调不销毁
  // recognizer，避免 pointer down 到 up 之间的父级重建吞掉这次点击。
  void _handleLink(BuildContext context, String href) =>
      (widget.linkHandler ?? defaultLinkHandler)(context, href);

  void _handleMention(BuildContext context, String username, String href) =>
      (widget.mentionTapHandler ?? defaultMentionTapHandler)(
        context, username, href,
      );

  void _handleFootnote(BuildContext context, String id, String? html) =>
      (widget.footnoteTapHandler ?? defaultFootnoteTapHandler)(context, id, html);

  void _handleAttachment(BuildContext context, String href, String filename) {
    final handler = widget.onDownloadAttachment;
    if (handler != null) {
      handler(context, href, filename);
    } else {
      _handleLink(context, href);
    }
  }

  @override
  void dispose() {
    _releaseResult();
    super.dispose();
  }

  @override
  void reassemble() {
    // hot reload:全局缓存整体失效(在用条目延迟释放),本 State 重新
    // acquire,渲染代码改动立即可见。布局缓存(ui.Paragraph)同步清。
    _releaseResult();
    FlattenCache.evictAll();
    ParagraphLayoutCache.evictAll();
    super.reassemble();
  }

  void _releaseResult() {
    final r = _result;
    if (r == null) return;
    r.mount.detach(context);
    FlattenCache.release(r);
    _result = null;
  }

  bool _cacheValid(ThemeData theme) {
    if (_result == null ||
        !identical(_keyInlines, widget.inlines) ||
        _keyBaseStyle != widget.baseStyle ||
        !identical(_keyFlattener, widget.flattener) ||
        _keyTotalImages != widget.totalImagesInPost) {
      return false;
    }
    if (identical(_keyThemeRaw, theme)) return true;
    final themeKey = FlattenThemeKey.fromTheme(theme);
    if (_keyTheme == themeKey) {
      _keyThemeRaw = theme;
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    // 无条件读 Theme:注册依赖,主题切换时本 widget 被标脏 → key 变 →
    // 换缓存条目(flatten 同步读色共 3 处:link/inline-code/mention)。
    final theme = Theme.of(context);
    if (!_cacheValid(theme)) {
      _releaseResult();
      _result = FlattenCache.acquire(
        inlines: widget.inlines,
        baseStyle: widget.baseStyle,
        theme: theme,
        totalImagesInPost: widget.totalImagesInPost,
        flattener: widget.flattener,
        create: () => widget.flattener.flatten(
          widget.inlines,
          widget.baseStyle,
          linkHandler: _handleLink,
          emojiImageBuilder: _InlineBuilders.buildEmoji,
          mentionTapHandler: _handleMention,
          imageContentBuilder: _InlineBuilders.buildImage,
          footnoteTapHandler: _handleFootnote,
          localDateBuilder: _InlineBuilders.buildLocalDate,
          mathInlineBuilder: _InlineBuilders.buildMath,
          onDownloadAttachment: _handleAttachment,
          totalImagesInPost: widget.totalImagesInPost,
          context: context,
        ),
      );
      _keyInlines = widget.inlines;
      _keyBaseStyle = widget.baseStyle;
      _keyThemeRaw = theme;
      _keyTheme = FlattenThemeKey.fromTheme(theme);
      _keyFlattener = widget.flattener;
      _keyTotalImages = widget.totalImagesInPost;
    }
    final result = _result!;
    // 带手势的产物由本 State 独占，登记的 context 就是实际点击所在区域。
    // 全局共享的纯文字不需要 context，也不应保留页面引用。
    if (!result.canShare) result.mount.attach(context);

    // ---- 分路:直绘缓存 vs RichText ----
    //
    // 直绘(CachedParagraphText,缓存 ui.Paragraph drawParagraph):
    // sliver 回收重进零排版零测量 —— 笔3 收益主体。判据(全部满足):
    // - 能提取纯排版数据：文字或尺寸已知的占位，不缓存页面回调/组件;
    // - 无行内代码/TextSpan-mention(灰底 InlineCodeBackgroundPainter
    //   仍直读 RenderParagraph,首期不动它);
    // - 无 maxLines/overflow 定制(引用卡标题单行省略语义走 TextPainter
    //   的 ellipsis,直绘层未实现 —— 这类块量少,留 RichText)。
    // 其余段落(交互原子/富装饰)走原 RichText 路径,行为不变。
    final projection = result.projection;
    final useDirectPaint = !InlineSpanText.debugForceRichText &&
        result.layoutData != null &&
        !projection.hasInlineCode &&
        !projection.hasSpanMention &&
        widget.maxLines == null &&
        widget.overflow == TextOverflow.clip;

    final warmupStyle = useDirectPaint
        ? ParagraphWarmupStyle(
            baseStyle: widget.baseStyle,
            theme: theme,
            flattener: widget.flattener,
          )
        : null;

    // 选区注册 + 高亮统一由 SelectableTextBox 封装(无 SelectionScope 时退化
    // 为裸文本,零成本)。直绘块经 BlockTextGeometry 接入同一套选区。
    final text = SelectableTextBox(
      projectionGetter: () => _projection,
      documentOrder: widget.documentOrder,
      chunkIndex: widget.chunkIndex,
      debugLabel: 'inlineText',
      child: useDirectPaint
          ? CachedParagraphText(
              result: result,
              textAlign: widget.textAlign,
              warmupStyle: warmupStyle,
            )
          : Text.rich(
              result.span,
              // 纯标签行缺少正文文字来撑行，仍应使用所在段落的最小行高。
              strutStyle: projection.entries.any(
                (entry) => entry.kind == ProjectionKind.hashtag,
              )
                  ? StrutStyle.fromTextStyle(
                      DefaultTextStyle.of(context).style.merge(widget.baseStyle),
                    )
                  : null,
              textAlign: widget.textAlign,
              maxLines: widget.maxLines,
              overflow: widget.overflow,
            ),
    );
    return result.hasPlaceholders
        ? _InlineBuilders(configuration: widget, child: text)
        : text;
  }
}

/// 内嵌组件在实际挂载处读取最新 builder。依赖变化只重建组件，不销毁
/// 文字手势；相同占位尺寸继续命中原布局。此作用域仅属于当前显示实例。
class _InlineBuilders extends InheritedWidget {
  const _InlineBuilders({required this.configuration, required super.child});

  final InlineSpanText configuration;

  static InlineSpanText _of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_InlineBuilders>()!
      .configuration;

  static Widget buildEmoji(BuildContext context, EmojiRun node, double size) =>
      (_of(context).emojiImageBuilder ?? defaultEmojiImageBuilder)(
        context, node, size,
      );

  static Widget buildImage(BuildContext context, ImageRun node, int total) =>
      (_of(context).imageContentBuilder ?? defaultImageContentBuilder)(
        context, node, total,
      );

  static Widget? buildLocalDate(BuildContext context, LocalDateRun node) =>
      _of(context).localDateBuilder?.call(context, node);

  static Widget? buildMath(BuildContext context, MathInlineRun node) =>
      _of(context).mathInlineBuilder?.call(context, node);

  @override
  bool updateShouldNotify(_InlineBuilders oldWidget) {
    final old = oldWidget.configuration;
    return !identical(old.emojiImageBuilder, configuration.emojiImageBuilder) ||
        !identical(old.imageContentBuilder, configuration.imageContentBuilder) ||
        !identical(old.localDateBuilder, configuration.localDateBuilder) ||
        !identical(old.mathInlineBuilder, configuration.mathInlineBuilder);
  }
}
