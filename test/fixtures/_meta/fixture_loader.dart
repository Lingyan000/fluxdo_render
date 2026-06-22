// fixture 加载器,golden / 单元测试 都用这个集中入口。

import 'dart:io';

/// 单个 fixture 的内容 + 路径信息。
class Fixture {
  Fixture({
    required this.path,
    required this.relativePath,
    required this.html,
  });

  /// 绝对路径。
  final String path;

  /// 相对 test/fixtures/ 的路径(如 "paragraph/simple_with_em.html")。
  final String relativePath;

  /// cooked HTML 内容。
  final String html;

  /// fixture 名称(去掉 .html 后缀的相对路径)。
  String get name => relativePath.replaceFirst(RegExp(r'\.html$'), '');

  /// 节点类型(目录名,_edge_cases 折算为 "edge_case")。
  String get nodeType {
    final dir = relativePath.split('/').first;
    return dir == '_edge_cases' ? 'edge_case' : dir;
  }
}

/// 拿到所有 fixture(适用于全量 golden 测试)。
List<Fixture> loadAll() {
  final root = _findFixturesDir();
  final result = <Fixture>[];
  for (final entity in root.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.html')) continue;
    if (entity.path.contains('/_meta/')) continue;
    if (entity.path.contains('/scripts/')) continue;
    result.add(_load(entity, root));
  }
  return result;
}

/// 按节点类型拿 fixture(用于"只测某节点"的 golden 测试)。
List<Fixture> loadByNodeType(String nodeType) {
  final root = _findFixturesDir();
  final dir = nodeType == 'edge_case' ? '_edge_cases' : nodeType;
  final subDir = Directory('${root.path}/$dir');
  if (!subDir.existsSync()) return const [];
  return subDir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.html'))
      .map((f) => _load(f, root))
      .toList();
}

Fixture _load(File f, Directory root) {
  return Fixture(
    path: f.absolute.path,
    relativePath: f.path.substring(root.path.length + 1),
    html: f.readAsStringSync(),
  );
}

Directory _findFixturesDir() {
  // 测试 cwd 可能在 packages/fluxdo_render 或在主项目根
  for (final candidate in [
    'test/fixtures',
    'packages/fluxdo_render/test/fixtures',
  ]) {
    final d = Directory(candidate);
    if (d.existsSync()) return d;
  }
  throw FileSystemException('找不到 test/fixtures 目录,请在 packages/fluxdo_render 或主项目根目录运行');
}
