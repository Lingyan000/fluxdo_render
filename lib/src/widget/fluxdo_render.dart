import 'package:flutter/material.dart';

/// 帖子渲染入口 widget(阶段 0 占位实现)。
///
/// 当前仅渲染一个 placeholder,标志包骨架可被主项目 import + 实例化。
/// 实际节点渲染逻辑会在阶段 1 起逐步填充。
class FluxdoRender extends StatelessWidget {
  const FluxdoRender({
    super.key,
    required this.cookedHtml,
  });

  /// Discourse cooked HTML 内容(后续解析后渲染为 Node tree)。
  final String cookedHtml;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.3),
          style: BorderStyle.solid,
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        'FluxdoRender placeholder · ${cookedHtml.length} chars',
        style: theme.textTheme.bodySmall,
      ),
    );
  }
}
