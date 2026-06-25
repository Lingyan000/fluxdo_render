/// 可选文本块的通用包装器 —— 把「注册 handle + 选区高亮」封装一处,
/// 供 InlineSpanText(段落/标题/列表/表格 cell)和代码块共用,避免重复。
///
/// 用法:包住一个内部含 RichText/RenderParagraph 的 child,提供该块的
/// [projectionGetter](渲染偏移↔逻辑投影映射表)。wrapper 自己:
/// - initState 领 seq 注册到 registry;dispose 注销;
/// - paragraph getter 实时从 child 子树找第一个 RenderParagraph(虚拟化安全);
/// - 在 child 底下叠选区高亮层。
///
/// [codeLanguage] 非 null 时,handle 额外实现 CodeBlockHandleInfo,
/// 导出选区时带出 language(代码块复制 ```lang)。
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../selection/projection.dart';
import '../selection/selectable_block_handle.dart';
import '../selection/selection_exporter.dart';
import '../selection/selection_geometry.dart';
import '../selection/selection_highlight_painter.dart';
import '../selection/selection_registry.dart';
import '../selection/selection_scope.dart';

class SelectableTextBox extends StatefulWidget {
  const SelectableTextBox({
    super.key,
    required this.projectionGetter,
    required this.child,
    this.codeLanguage,
    this.clipBoundsKey,
    this.debugLabel,
  });

  /// 取当前块的映射表(InlineSpanText 每次 flatten 变;代码块静态)。
  final RenderTextProjection Function() projectionGetter;

  /// 内部含 RichText 的 child(Text.rich / highlighter 输出)。
  final Widget child;

  /// 非 null = 代码块,导出选区带此 language。
  final String? codeLanguage;

  /// 可视区裁剪边界的 GlobalKey(代码块传其限高 SizedBox 的 key)。块内有独立
  /// 滚动时,RenderParagraph.size 是完整内容尺寸 → 命中框溢出;用此 key 的
  /// RenderBox 全局矩形把命中框裁到可视区。null = 不裁剪(普通段落)。
  final GlobalKey? clipBoundsKey;

  final String? debugLabel;

  @override
  State<SelectableTextBox> createState() => _SelectableTextBoxState();
}

class _SelectableTextBoxState extends State<SelectableTextBox> {
  final GlobalKey _childKey = GlobalKey();
  SelectableBlockHandle? _handle;
  SelectionController? _controller;

  /// 从 child 子树向下找第一个 RenderParagraph(代码块 highlighter 输出嵌套深)。
  RenderParagraph? _findParagraph() {
    final ctx = _childKey.currentContext;
    if (ctx == null) return null;
    final ro = ctx.findRenderObject();
    if (ro == null) return null;
    return _firstParagraph(ro);
  }

  RenderParagraph? _firstParagraph(RenderObject node) {
    if (node is RenderParagraph) return node;
    RenderParagraph? found;
    node.visitChildren((child) {
      found ??= _firstParagraph(child);
    });
    return found;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = SelectionScope.maybeOfNoDepend(context);
    if (controller == _controller) return;
    _unregister();
    _controller = controller;
    _register();
  }

  /// 可视区裁剪矩形(代码块用 clipBoundsKey 指向的限高 SizedBox 的全局框)。
  Rect? _clipBounds() {
    final key = widget.clipBoundsKey;
    if (key == null) return null;
    final ro = key.currentContext?.findRenderObject();
    if (ro is! RenderBox || !ro.attached || !ro.hasSize) return null;
    return ro.localToGlobal(Offset.zero) & ro.size;
  }

  void _register() {
    final controller = _controller;
    if (controller == null) return;
    final seq = controller.registry.allocSeq();
    final id = SelectableBlockId(seq, debugLabel: widget.debugLabel);
    final clipGetter = widget.clipBoundsKey != null ? _clipBounds : null;
    _handle = widget.codeLanguage != null
        ? _CodeBlockHandle(
            id: id,
            paragraphGetter: _findParagraph,
            projectionGetter: widget.projectionGetter,
            clipBoundsGetter: clipGetter,
            language: widget.codeLanguage,
          )
        : CallbackBlockHandle(
            id: id,
            paragraphGetter: _findParagraph,
            projectionGetter: widget.projectionGetter,
            clipBoundsGetter: clipGetter,
          );
    controller.registry.register(_handle!);
  }

  void _unregister() {
    final controller = _controller;
    final handle = _handle;
    if (controller != null && handle != null) {
      controller.registry.unregister(handle.id.seq);
    }
    _handle = null;
  }

  @override
  void dispose() {
    _unregister();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final keyedChild = KeyedSubtree(key: _childKey, child: widget.child);
    final controller = _controller;
    if (controller == null) return keyedChild;
    // 高亮画在内容**上层**(盖 emoji/图片),必须用低透明度主题色,不能用
    // DefaultSelectionStyle.selectionColor —— 后者透明度不可控(某些主题接近
    // 不透明),画上层会糊住文字。统一用 primary @0.3,可控且文字/占位符透出。
    final highlightColor =
        Theme.of(context).colorScheme.primary.withValues(alpha: 0.3);
    return SelectionHighlight(
      controller: controller,
      blockHandleGetter: () => _handle,
      color: highlightColor,
      child: keyedChild,
    );
  }
}

/// 代码块句柄:带 language,导出时复制 ```lang。
class _CodeBlockHandle extends CallbackBlockHandle implements CodeBlockHandleInfo {
  _CodeBlockHandle({
    required super.id,
    required super.paragraphGetter,
    required super.projectionGetter,
    super.clipBoundsGetter,
    required this.language,
  });

  @override
  final String? language;
}
