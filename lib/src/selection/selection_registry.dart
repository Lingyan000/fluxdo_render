/// 全局选区注册表 —— 持有当前 post 内所有可选文本块的句柄。
///
/// 对齐 super_editor 的 DocumentLayout:各块自行注册,顶层手势/导出层遍历。
/// **不把块重写成 RenderObject 子**(我们只读,块已是普通 widget)。
library;

import 'package:flutter/widgets.dart';

import 'selectable_block_handle.dart';
import 'selection_coordinator.dart';
import 'selection_geometry.dart';

/// 注册表。每个 FluxdoRender 实例一个(随 SelectionScope 下传)。
class SelectionRegistry {
  int _nextSeq = 0;
  final Map<int, SelectableBlockHandle> _blocks = {};

  /// 领一个单调自增 seq(块 initState 时调,作为 SelectableBlockId 主键)。
  int allocSeq() => _nextSeq++;

  void register(SelectableBlockHandle handle) {
    _blocks[handle.id.seq] = handle;
  }

  void unregister(int seq) {
    _blocks.remove(seq);
  }

  SelectableBlockHandle? byId(SelectableBlockId id) => _blocks[id.seq];

  Iterable<SelectableBlockHandle> get all => _blocks.values;

  int get length => _blocks.length;

  /// 按视觉顺序(全局 y,再 x)排序的块列表。
  ///
  /// **实时按几何排序,不用注册序**:虚拟化/Column rebuild 下注册顺序不可靠。
  /// 只收 globalRect 可用(已 mount)的块;未 mount 的块本就取不到几何,
  /// 第一版接受"只在已 mount 块间选"(见 plan 已知取舍)。
  List<SelectableBlockHandle> visualOrder() {
    final withRect = <(SelectableBlockHandle, Rect)>[];
    for (final h in _blocks.values) {
      final r = h.globalRect();
      if (r != null) withRect.add((h, r));
    }
    withRect.sort((a, b) {
      final dy = a.$2.top.compareTo(b.$2.top);
      if (dy != 0) return dy;
      return a.$2.left.compareTo(b.$2.left);
    });
    return [for (final e in withRect) e.$1];
  }

  @override
  String toString() => 'SelectionRegistry(${_blocks.length} blocks)';
}

/// 当前选区 + registry 的下传载体(实际作为 InheritedWidget 由 SelectionScope 持有)。
class SelectionController extends ChangeNotifier {
  SelectionController(this.registry);

  final SelectionRegistry registry;

  DocumentSelection? _selection;
  DocumentSelection? get selection => _selection;

  set selection(DocumentSelection? value) {
    if (_selection == value) return;
    _selection = value;
    // 全局唯一活动选区:起选时清掉其他帖的选区;自己清空时注销活动者。
    if (value != null) {
      SelectionCoordinator.instance.activate(this);
    } else {
      SelectionCoordinator.instance.deactivate(this);
    }
    notifyListeners();
  }

  void clear() => selection = null;

  @override
  void dispose() {
    SelectionCoordinator.instance.deactivate(this);
    super.dispose();
  }
}
