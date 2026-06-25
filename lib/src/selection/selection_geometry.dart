/// 自研逻辑选区的几何/定位基础类型。
///
/// 设计对齐 super_editor 的 Document/Position/Selection 三件套,但只读场景:
/// - 不需要多态 nodePosition(本引擎所有可选块统一是「一个 RenderParagraph +
///   渲染偏移」,占位符 emoji/mention/image 是段落里的一个 ￼ 偏移,不是独立块)
/// - 偏移统一用**渲染偏移**(RenderParagraph 坐标系,￼ 各占 1),命中/高亮都认它;
///   逻辑投影只在复制那一刻转(见 projection.dart)
library;

import 'package:flutter/foundation.dart';

/// 可选文本块的稳定标识。
///
/// **用 registry 分配的自增 [seq] 做主键,不用 BlockNode.id** —— 后者在容器
/// (表格 cell / blockquote)内不保证全局唯一,且表格 cell 内段落可能无独立 id。
/// seq 单调自增,天然全局唯一;但 seq **不代表视觉顺序**(虚拟化/重建下注册
/// 顺序会乱),视觉序由 registry 按几何 y 实时排序(见 SelectionRegistry)。
@immutable
class SelectableBlockId {
  const SelectableBlockId(this.seq, {this.debugLabel});

  /// registry 单调自增主键。
  final int seq;

  /// 仅调试用的可读标签(如 "paragraph#3" / "codeblock"),不参与 ==。
  final String? debugLabel;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SelectableBlockId &&
          runtimeType == other.runtimeType &&
          seq == other.seq;

  @override
  int get hashCode => seq;

  @override
  String toString() =>
      'SelectableBlockId($seq${debugLabel == null ? "" : ", $debugLabel"})';
}

/// 文档内一个点:某块 + 块内渲染偏移。
@immutable
class DocumentPosition {
  const DocumentPosition({required this.blockId, required this.renderOffset});

  final SelectableBlockId blockId;

  /// RenderParagraph 坐标系的字符偏移(￼ 各占 1)。
  final int renderOffset;

  DocumentPosition copyWith({SelectableBlockId? blockId, int? renderOffset}) =>
      DocumentPosition(
        blockId: blockId ?? this.blockId,
        renderOffset: renderOffset ?? this.renderOffset,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DocumentPosition &&
          runtimeType == other.runtimeType &&
          blockId == other.blockId &&
          renderOffset == other.renderOffset;

  @override
  int get hashCode => Object.hash(blockId, renderOffset);

  @override
  String toString() => 'DocumentPosition($blockId @$renderOffset)';
}

/// 有向选区:[base] 锚点(起选不动)→ [extent] 浮标(跟手指/鼠标走)。
///
/// base/extent 的文档先后由 registry 的视觉序 + 同块 renderOffset 决定
/// (见 SelectionExporter 的归一化),本类不强制 base ≤ extent。
@immutable
class DocumentSelection {
  const DocumentSelection({required this.base, required this.extent});

  /// 折叠选区(光标态)的便捷构造 —— 只读场景下罕用,主要给"点空白前的
  /// 起选起点"或单元测试用。
  const DocumentSelection.collapsed(DocumentPosition position)
      : base = position,
        extent = position;

  final DocumentPosition base;
  final DocumentPosition extent;

  /// base == extent → 无实际选中范围。
  bool get isCollapsed => base == extent;

  /// 选区是否只落在单个块内。
  bool get isSingleBlock => base.blockId == extent.blockId;

  DocumentSelection copyWith({DocumentPosition? base, DocumentPosition? extent}) =>
      DocumentSelection(
        base: base ?? this.base,
        extent: extent ?? this.extent,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DocumentSelection &&
          runtimeType == other.runtimeType &&
          base == other.base &&
          extent == other.extent;

  @override
  int get hashCode => Object.hash(base, extent);

  @override
  String toString() => 'DocumentSelection($base → $extent)';
}
