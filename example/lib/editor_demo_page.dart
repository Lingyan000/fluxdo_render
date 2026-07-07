/// 编辑内核 M1 demo 页 —— 验证光标/中文 IME/分段合并/undo。
library;

import 'package:flutter/material.dart';
import 'package:fluxdo_render/editor.dart';

class EditorDemoPage extends StatefulWidget {
  const EditorDemoPage({super.key});

  @override
  State<EditorDemoPage> createState() => _EditorDemoPageState();
}

class _EditorDemoPageState extends State<EditorDemoPage> {
  late final EditorState _state;

  // 工具栏按钮不抢编辑器焦点(编辑器工具栏惯例:canRequestFocus=false,
  // 否则点 undo 会让光标消失)
  final FocusNode _undoFocus =
      FocusNode(canRequestFocus: false, skipTraversal: true);
  final FocusNode _redoFocus =
      FocusNode(canRequestFocus: false, skipTraversal: true);

  @override
  void initState() {
    super.initState();
    // demo 页开 IME 通道日志(flutter run 控制台可见,定位真机 IME 行为)
    EditorImeClient.debugLogging = true;
    _state = EditorState.fromTexts(const [
      '这是第一段。点击任意位置定位光标,直接开始输入。',
      'The second paragraph mixes English and 中文混排文字,'
          ' try typing with a Chinese IME here.',
      '第三段:回车分段、段首退格合并、拖选跨段删除、Cmd+Z 撤销。',
    ]);
  }

  @override
  void dispose() {
    _undoFocus.dispose();
    _redoFocus.dispose();
    _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('编辑内核 M1 demo'),
        actions: [
          ListenableBuilder(
            listenable: _state,
            builder: (context, _) => Row(
              children: [
                IconButton(
                  tooltip: 'Undo',
                  focusNode: _undoFocus,
                  icon: const Icon(Icons.undo),
                  onPressed: _state.canUndo ? _state.undo : null,
                ),
                IconButton(
                  tooltip: 'Redo',
                  focusNode: _redoFocus,
                  icon: const Icon(Icons.redo),
                  onPressed: _state.canRedo ? _state.redo : null,
                ),
              ],
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FluxdoEditor(
                  state: _state,
                  autofocus: true,
                  baseTextStyle: Theme.of(context)
                      .textTheme
                      .bodyLarge
                      ?.copyWith(height: 1.6),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // 调试面板:实时观察选区/composing/文档状态
            ListenableBuilder(
              listenable: _state,
              builder: (context, _) => Text(
                'selection: ${_state.selection}\n'
                'composing: ${_state.composing}\n'
                'blocks: ${_state.blocks.length}  '
                'undo: ${_state.canUndo}  redo: ${_state.canRedo}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      color: Theme.of(context).colorScheme.outline,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
