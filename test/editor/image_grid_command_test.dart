/// 图片原子「加入网格」命令:三分支块结构 + 单事务 undo + 序列化。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo_render/editor.dart';
import 'package:fluxdo_render/fluxdo_render.dart';

const _img = ImageRun(src: 'upload://new.png', alt: 'n', width: 100, height: 80);
const _gridImg = ImageRun(src: 'upload://old.png', alt: 'o', width: 50, height: 50);

TextBlock _textWithImg(String id, {String before = 'a', String after = 'b'}) =>
    TextBlock(
      id: id,
      content: EditableTextContent.fromInlines([
        if (before.isNotEmpty) TextRun(before),
        _img,
        if (after.isNotEmpty) TextRun(after),
      ]),
    );

IslandBlock _gridIsland(String id) => IslandBlock(
      id: id,
      node: const ImageGridNode(id: 'b_g', images: [_gridImg]),
    );

void main() {
  test('分支1:前邻 grid → append,选中 grid 岛,undo 一步还原', () {
    final s = EditorState(blocks: [
      _gridIsland('e_g'),
      _textWithImg('e_t'),
    ]);
    addTearDown(s.dispose);
    final beforeBlocks = s.blocks;

    expect(addImageAtomToGrid(s, 'e_t', 1), isTrue);
    expect(s.blocks, hasLength(2));
    final grid = (s.blocks[0] as IslandBlock).node as ImageGridNode;
    expect(grid.images, [_gridImg, _img], reason: 'append 到尾');
    expect((s.blocks[1] as TextBlock).content.text, 'ab');
    expect(s.selection!.base.blockId, 'e_g', reason: '整选 grid 岛');
    expect(s.selection!.extent.offset, 1);

    s.undo();
    expect(s.blocks, beforeBlocks, reason: '单事务 undo 一步整体还原');
  });

  test('分支2:后邻 grid → prepend;删原子后空段丢弃', () {
    final s = EditorState(blocks: [
      _textWithImg('e_t', before: '', after: ''), // 段内只有图
      _gridIsland('e_g'),
    ]);
    addTearDown(s.dispose);

    expect(addImageAtomToGrid(s, 'e_t', 0), isTrue);
    // 空段丢弃 → 只剩 grid 岛(+文档不变量自动补的空段)
    final islands = s.blocks.whereType<IslandBlock>().toList();
    expect(islands, hasLength(1));
    final grid = islands.single.node as ImageGridNode;
    expect(grid.images, [_img, _gridImg], reason: 'prepend 到头');
  });

  test('分支3:无邻 grid → 原地新建,段切三段', () {
    final s = EditorState(blocks: [_textWithImg('e_t')]);
    addTearDown(s.dispose);

    expect(addImageAtomToGrid(s, 'e_t', 1), isTrue);
    expect(s.blocks, hasLength(3));
    expect((s.blocks[0] as TextBlock).content.text, 'a');
    final grid = (s.blocks[1] as IslandBlock).node as ImageGridNode;
    expect(grid.images, [_img]);
    expect((s.blocks[2] as TextBlock).content.text, 'b');
    // 序列化含 [grid]
    expect(docToMarkdown(s.blocks), contains('[grid]'));
    expect(docToMarkdown(s.blocks), contains('![n|100x80](upload://new.png)'));

    s.undo();
    expect(s.blocks, hasLength(1));
    expect((s.blocks[0] as TextBlock).content.text, 'a￼b');
  });

  test('非图原子位置返回 false 不动文档', () {
    final s = EditorState.fromTexts(['纯文本']);
    addTearDown(s.dispose);
    expect(addImageAtomToGrid(s, s.blocks.first.id, 0), isFalse);
  });

  test('replaceAtomAt reselect:true 保持原子整选', () {
    final s = EditorState(blocks: [_textWithImg('e_t')]);
    addTearDown(s.dispose);
    s.replaceAtomAt('e_t', 1, _img.copyWith(scale: 75), reselect: true);
    expect(s.selection!.base.offset, 1);
    expect(s.selection!.extent.offset, 2, reason: '原子整选保持');
    expect(((s.blocks[0] as TextBlock).content.atoms[1] as ImageRun).scale, 75);
    // 默认(date chip 路径)仍是折叠到原子后
    s.replaceAtomAt('e_t', 1, _img);
    expect(s.selection!.isCollapsed, isTrue);
    expect(s.selection!.base.offset, 2);
  });

  test('copyWith alt:空串清空,null 不改', () {
    const img = ImageRun(src: 's', alt: '原');
    expect(img.copyWith(alt: '新').alt, '新');
    expect(img.copyWith(alt: '').alt, '');
    expect(img.copyWith(scale: 50).alt, '原');
  });
}
