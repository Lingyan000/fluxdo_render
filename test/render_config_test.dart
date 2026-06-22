import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo_render/fluxdo_render.dart';

void main() {
  group('NodeKind', () {
    test('每个 enum 值都有 unique dirName', () {
      final seen = <String>{};
      for (final k in NodeKind.values) {
        expect(seen.add(k.dirName), isTrue, reason: '${k.dirName} 重复');
      }
    });

    test('每个 enum 值都有非空 label', () {
      for (final k in NodeKind.values) {
        expect(k.label, isNotEmpty);
      }
    });

    test('fromDirName 反查能拿回原值', () {
      for (final k in NodeKind.values) {
        expect(NodeKind.fromDirName(k.dirName), k);
      }
    });

    test('fromDirName 未知值返回 null', () {
      expect(NodeKind.fromDirName('not_a_node'), isNull);
    });
  });

  group('RenderEngine', () {
    test('每个值都有 label 和 dualMode', () {
      for (final e in RenderEngine.values) {
        expect(e.label, isNotEmpty);
        e.dualMode; // 不抛即可
      }
    });

    test('dualMode 映射正确', () {
      expect(RenderEngine.legacy.dualMode, DualRenderMode.legacy);
      expect(RenderEngine.newImpl.dualMode, DualRenderMode.newOnly);
      expect(RenderEngine.both.dualMode, DualRenderMode.overlay);
    });
  });

  group('RenderConfig.engineFor', () {
    test('未覆盖时回落到 defaultEngine', () {
      const config = RenderConfig(
        defaultEngine: RenderEngine.newImpl,
        overrides: {},
      );
      expect(config.engineFor(NodeKind.paragraph), RenderEngine.newImpl);
      expect(config.engineFor(NodeKind.codeBlock), RenderEngine.newImpl);
    });

    test('overrides 覆盖默认值', () {
      const config = RenderConfig(
        defaultEngine: RenderEngine.legacy,
        overrides: {NodeKind.paragraph: RenderEngine.newImpl},
      );
      expect(config.engineFor(NodeKind.paragraph), RenderEngine.newImpl);
      expect(config.engineFor(NodeKind.codeBlock), RenderEngine.legacy);
    });

    test('defaults() 全部 legacy', () {
      final config = RenderConfig.defaults();
      for (final k in NodeKind.values) {
        expect(config.engineFor(k), RenderEngine.legacy);
      }
    });
  });

  group('RenderConfig.withOverride', () {
    test('设置新覆盖', () {
      final config = RenderConfig.defaults()
          .withOverride(NodeKind.paragraph, RenderEngine.newImpl);
      expect(config.engineFor(NodeKind.paragraph), RenderEngine.newImpl);
      expect(config.engineFor(NodeKind.codeBlock), RenderEngine.legacy);
    });

    test('传 null 移除覆盖,回归 default', () {
      final config = RenderConfig.defaults()
          .withOverride(NodeKind.paragraph, RenderEngine.newImpl)
          .withOverride(NodeKind.paragraph, null);
      expect(config.engineFor(NodeKind.paragraph), RenderEngine.legacy);
      expect(config.overrides, isEmpty);
    });
  });

  group('RenderConfig 序列化往返', () {
    test('空 config (defaults) 往返一致', () {
      final original = RenderConfig.defaults();
      final back = RenderConfig.fromJsonString(original.toJsonString());
      expect(back, original);
    });

    test('多个 override 往返一致', () {
      final original = RenderConfig.defaults()
          .withOverride(NodeKind.paragraph, RenderEngine.newImpl)
          .withOverride(NodeKind.codeBlock, RenderEngine.both)
          .copyWith(defaultEngine: RenderEngine.newImpl);
      final back = RenderConfig.fromJsonString(original.toJsonString());
      expect(back, original);
    });

    test('反序列化容错:未知节点名忽略', () {
      const json = '{"default": "legacy", "overrides": {"unknown_node": "newImpl", "paragraph": "newImpl"}}';
      final config = RenderConfig.fromJsonString(json);
      expect(config.engineFor(NodeKind.paragraph), RenderEngine.newImpl);
      expect(config.overrides.length, 1);
    });

    test('反序列化容错:未知 engine 名忽略', () {
      const json = '{"default": "weirdEngine", "overrides": {"paragraph": "alienEngine"}}';
      final config = RenderConfig.fromJsonString(json);
      expect(config.defaultEngine, RenderEngine.legacy);
      expect(config.overrides, isEmpty);
    });
  });

  group('RenderConfigStore 接口', () {
    test('可以被 mock 实现', () async {
      final store = _InMemoryStore();
      final loaded = store.load();
      expect(loaded, RenderConfig.defaults());

      final newConfig = RenderConfig.defaults()
          .withOverride(NodeKind.paragraph, RenderEngine.newImpl);
      await store.save(newConfig);
      expect(store.load(), newConfig);
    });
  });
}

class _InMemoryStore implements RenderConfigStore {
  RenderConfig _config = RenderConfig.defaults();
  @override
  RenderConfig load() => _config;
  @override
  Future<void> save(RenderConfig config) async => _config = config;
}
