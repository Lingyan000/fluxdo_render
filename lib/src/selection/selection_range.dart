/// 把全局 [DocumentSelection] 拆成「每个块的渲染偏移区间」。
///
/// 高亮(各块画自己的 box)和复制(各块投影自己的文本)都要用。归一化:
/// 按 visualOrder 视觉序定 start/end,端点块截 renderOffset,中间块整段。
library;

import 'selectable_block_handle.dart';
import 'selection_geometry.dart';
import 'selection_registry.dart';

/// 单块的渲染偏移区间 `[start, end)`。
class BlockRange {
  const BlockRange(this.handle, this.start, this.end);
  final SelectableBlockHandle handle;
  final int start;
  final int end;
  bool get isEmpty => start >= end;
}

/// 按视觉序展开 selection,返回涉及的每个块及其渲染偏移区间(视觉序)。
///
/// 单块选区:返回该块一段(start/end 按 renderOffset 排序)。
/// 跨块选区:首块 [startOffset, len)、中间块整段、末块 [0, endOffset)。
/// 取不到端点块几何(details 折叠/spoiler 未揭示的子块未 mount)时返回空列表。
List<BlockRange> expandSelection(
  SelectionRegistry registry,
  DocumentSelection selection,
) {
  final order = registry.visualOrder();
  if (order.isEmpty) return const [];

  int indexOf(SelectableBlockId id) {
    for (var i = 0; i < order.length; i++) {
      if (order[i].id == id) return i;
    }
    return -1;
  }

  final baseIdx = indexOf(selection.base.blockId);
  final extentIdx = indexOf(selection.extent.blockId);
  if (baseIdx < 0 || extentIdx < 0) return const [];

  // 归一化:确定视觉序上的 (startIdx, startOffset) → (endIdx, endOffset)
  late int startIdx, endIdx, startOffset, endOffset;
  if (baseIdx < extentIdx ||
      (baseIdx == extentIdx &&
          selection.base.renderOffset <= selection.extent.renderOffset)) {
    startIdx = baseIdx;
    startOffset = selection.base.renderOffset;
    endIdx = extentIdx;
    endOffset = selection.extent.renderOffset;
  } else {
    startIdx = extentIdx;
    startOffset = selection.extent.renderOffset;
    endIdx = baseIdx;
    endOffset = selection.base.renderOffset;
  }

  final result = <BlockRange>[];
  for (var i = startIdx; i <= endIdx; i++) {
    final h = order[i];
    final len = h.projection.renderLength;
    final s = (i == startIdx) ? startOffset : 0;
    final e = (i == endIdx) ? endOffset : len;
    final cs = s.clamp(0, len);
    final ce = e.clamp(0, len);
    if (cs < ce) result.add(BlockRange(h, cs, ce));
  }
  return result;
}
