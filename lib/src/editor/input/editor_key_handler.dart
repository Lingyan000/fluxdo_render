/// 编辑器硬件键盘处理。
///
/// 职责边界(对齐 appflowy keyboard_service_widget 的分层):
/// - **可打印字符不在这里处理** —— 全部走 IME(updateEditingValue);
/// - 本层只管导航/结构键:方向、Backspace/Delete、Enter、Cmd/Ctrl 组合;
/// - **composing 非空时一律让路**(返回 ignored,平台把按键交给 IME 处理
///   候选窗上下移动/翻页等)。
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../model/editor_state.dart';

/// 处理结果由调用方(FluxdoEditor 的 Focus.onKeyEvent)透传给框架。
///
/// [onMoveVertical]:上下键的垂直光标移动。需要行几何(RenderParagraph),
/// 纯 EditorState 做不了 → 由 FluxdoEditor 注入实现。
///
/// 退格/删除/回车在**框架侧本地处理**并返回 handled(EditableText +
/// DefaultTextEditingShortcuts 同款,平台不再收到该键)。与平台 insertText
/// 流的一致性由两道围栏保证:macOS 键盘管理器逐键串行(应答前不路由下一
/// 键,setEditingState 先于应答入队)+ 段落切换时重开输入连接(框架按
/// client ID 丢弃旧连接的迟到消息,见 EditorImeClient.syncFromState)。
KeyEventResult handleEditorKeyEvent(
  EditorState state,
  KeyEvent event, {
  required void Function() onEdited,
  void Function(int direction, {required bool extend})? onMoveVertical,
}) {
  if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
    return KeyEventResult.ignored;
  }

  // IME 预编辑中:候选窗需要方向/回车/退格 —— 用 skipRemainingHandlers
  // 而非 ignored:事件仍交还平台(IME 正常收到),但**不再冒泡**到上层
  // Shortcuts(否则方向键会触发 DirectionalFocusIntent,焦点被遍历走)。
  if (state.hasComposing) {
    return KeyEventResult.skipRemainingHandlers;
  }

  final isMac = defaultTargetPlatform == TargetPlatform.macOS;
  final pressed = HardwareKeyboard.instance;
  final primary = isMac ? pressed.isMetaPressed : pressed.isControlPressed;
  final shift = pressed.isShiftPressed;

  // 跨段选区 + 可打印字符:IME 窗口只覆盖单段,平台模型里没有这个跨段
  // 选区 —— 直接放行会让平台把字符插进**过期的单段模型**,再经 diff 写进
  // 错误位置。先本地删选区(收敛为单段折叠光标,监听器会同步 setEditingState
  // 刷新平台模型),然后 skipRemainingHandlers 把按键交还平台 IME:
  // 渠道 FIFO 保证平台先应用新模型再处理该键 → 字符插在正确位置。
  final sel = state.selection;
  if (sel != null && !sel.isSingleBlock) {
    final ch = event.character;
    final isPrintable = ch != null &&
        ch.isNotEmpty &&
        !primary &&
        ch.codeUnitAt(0) >= 0x20;
    if (isPrintable) {
      state.deleteSelection();
      onEdited();
      return KeyEventResult.skipRemainingHandlers;
    }
  }

  bool handled = true;
  switch (event.logicalKey) {
    case LogicalKeyboardKey.arrowLeft:
      state.moveCaretHorizontal(-1, extend: shift);
    case LogicalKeyboardKey.arrowRight:
      state.moveCaretHorizontal(1, extend: shift);
    case LogicalKeyboardKey.arrowUp:
      onMoveVertical?.call(-1, extend: shift);
    case LogicalKeyboardKey.arrowDown:
      onMoveVertical?.call(1, extend: shift);
    case LogicalKeyboardKey.backspace:
      state.backspace();
      onEdited();
    case LogicalKeyboardKey.delete:
      state.deleteForward();
      onEdited();
    case LogicalKeyboardKey.enter:
    case LogicalKeyboardKey.numpadEnter:
      state.sealHistory();
      state.splitParagraph();
      onEdited();
    case LogicalKeyboardKey.keyA when primary:
      state.selectAll();
    case LogicalKeyboardKey.keyZ when primary && shift:
      state.redo();
      onEdited();
    case LogicalKeyboardKey.keyZ when primary:
      state.undo();
      onEdited();
    default:
      handled = false;
  }
  return handled ? KeyEventResult.handled : KeyEventResult.ignored;
}
