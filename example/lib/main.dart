import 'package:flutter/material.dart';
import 'package:fluxdo_render/fluxdo_render.dart';

void main() {
  runApp(const GalleryApp());
}

class GalleryApp extends StatelessWidget {
  const GalleryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'fluxdo_render gallery',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF6750A4),
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF6750A4),
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      home: const GalleryPage(),
    );
  }
}

class GalleryPage extends StatefulWidget {
  const GalleryPage({super.key});

  @override
  State<GalleryPage> createState() => _GalleryPageState();
}

class _GalleryPageState extends State<GalleryPage> {
  late final Map<String, List<FixtureEntry>> _grouped;
  FixtureEntry? _selected;
  Brightness _brightness = Brightness.light;

  @override
  void initState() {
    super.initState();
    _grouped = groupByNodeType(allFixtures);
    final sortedKeys = _grouped.keys.toList()..sort();
    if (sortedKeys.isNotEmpty) {
      _selected = _grouped[sortedKeys.first]!.first;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: _brightness == Brightness.light
          ? ThemeData(
              colorSchemeSeed: const Color(0xFF6750A4),
              useMaterial3: true,
              brightness: Brightness.light,
            )
          : ThemeData(
              colorSchemeSeed: const Color(0xFF6750A4),
              useMaterial3: true,
              brightness: Brightness.dark,
            ),
      child: Scaffold(
        appBar: AppBar(
          title: Text('fluxdo_render gallery · ${allFixtures.length} fixtures'),
          actions: [
            IconButton(
              tooltip: 'Toggle theme',
              icon: Icon(
                _brightness == Brightness.light
                    ? Icons.dark_mode
                    : Icons.light_mode,
              ),
              onPressed: () => setState(() {
                _brightness = _brightness == Brightness.light
                    ? Brightness.dark
                    : Brightness.light;
              }),
            ),
          ],
        ),
        body: Row(
          children: [
            SizedBox(
              width: 260,
              child: _FixtureNav(
                grouped: _grouped,
                selected: _selected,
                onSelect: (f) => setState(() => _selected = f),
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: _selected == null
                  ? const Center(child: Text('Select a fixture'))
                  : _FixtureDetail(fixture: _selected!),
            ),
          ],
        ),
      ),
    );
  }
}

class _FixtureNav extends StatelessWidget {
  const _FixtureNav({
    required this.grouped,
    required this.selected,
    required this.onSelect,
  });

  final Map<String, List<FixtureEntry>> grouped;
  final FixtureEntry? selected;
  final ValueChanged<FixtureEntry> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final groupKeys = grouped.keys.toList()..sort();
    return ListView(
      children: [
        for (final key in groupKeys) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              '$key · ${grouped[key]!.length}',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          for (final f in grouped[key]!)
            ListTile(
              dense: true,
              selected: identical(f, selected),
              title: Text(
                f.relativePath.split('/').last.replaceAll('.html', ''),
                style: const TextStyle(fontSize: 13),
              ),
              subtitle: f.edgeCase
                  ? const Text('edge case',
                      style: TextStyle(fontSize: 11, color: Colors.orange))
                  : null,
              onTap: () => onSelect(f),
            ),
        ],
      ],
    );
  }
}

class _FixtureDetail extends StatefulWidget {
  const _FixtureDetail({required this.fixture});

  final FixtureEntry fixture;

  @override
  State<_FixtureDetail> createState() => _FixtureDetailState();
}

class _FixtureDetailState extends State<_FixtureDetail> {
  static const _parser = ParagraphParser();

  late List<BlockNode> _nodes;
  int _parseUs = 0;

  @override
  void initState() {
    super.initState();
    _reparse();
  }

  @override
  void didUpdateWidget(covariant _FixtureDetail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fixture.relativePath != widget.fixture.relativePath) {
      _reparse();
    }
  }

  void _reparse() {
    final sw = Stopwatch()..start();
    _nodes = _parser.parse(widget.fixture.html);
    sw.stop();
    _parseUs = sw.elapsedMicroseconds;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final f = widget.fixture;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(f.relativePath, style: theme.textTheme.titleLarge),
        const SizedBox(height: 4),
        if (f.notes.isNotEmpty) ...[
          Text(
            f.notes,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 8),
        ],
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            Chip(
              avatar: const Icon(Icons.label_outline, size: 16),
              label: Text(f.nodeType),
              visualDensity: VisualDensity.compact,
            ),
            Chip(
              avatar: const Icon(Icons.speed, size: 16),
              label: Text('parse $_parseUs µs'),
              visualDensity: VisualDensity.compact,
            ),
            Chip(
              avatar: const Icon(Icons.account_tree_outlined, size: 16),
              label: Text('${_nodes.length} block nodes'),
              visualDensity: VisualDensity.compact,
            ),
            if (f.edgeCase)
              const Chip(
                avatar: Icon(Icons.warning_amber, size: 16),
                label: Text('edge case'),
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
        const SizedBox(height: 16),

        _SectionCard(
          title: 'Rendered',
          icon: Icons.visibility,
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: FluxdoRender(
              cookedHtml: f.html,
              linkHandler: (ctx, href) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(content: Text('link tapped: $href')),
                );
              },
              emojiImageBuilder: _galleryEmojiBuilder,
              mentionTapHandler: (ctx, username, href) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(content: Text('mention tapped: @$username ($href)')),
                );
              },
            ),
          ),
        ),

        _SectionCard(
          title: 'Cooked HTML source',
          icon: Icons.code,
          initiallyExpanded: false,
          child: SelectableText(
            f.html,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
            ),
          ),
        ),

        _SectionCard(
          title: 'Node tree',
          icon: Icons.account_tree,
          initiallyExpanded: false,
          child: SelectableText(
            _formatNodeTree(_nodes),
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
            ),
          ),
        ),

        if (f.source.isNotEmpty)
          _SectionCard(
            title: 'Source',
            icon: Icons.link,
            initiallyExpanded: false,
            child: SelectableText(
              f.source,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
      ],
    );
  }
}

String _formatNodeTree(List<BlockNode> nodes) {
  final buf = StringBuffer();
  for (final n in nodes) {
    _writeNode(buf, n, 0);
  }
  return buf.toString();
}

void _writeNode(StringBuffer buf, BlockNode node, int indent) {
  final pad = '  ' * indent;
  switch (node) {
    case ParagraphNode():
      buf.writeln('$pad$node');
      for (final inline in node.inlines) {
        _writeInline(buf, inline, indent + 1);
      }
    case HeadingNode():
      buf.writeln('$pad$node');
      for (final inline in node.inlines) {
        _writeInline(buf, inline, indent + 1);
      }
    case ListNode():
      buf.writeln('$pad$node');
      for (int i = 0; i < node.items.length; i++) {
        final item = node.items[i];
        buf.writeln('$pad  [$i] ${item.inlines.length} inlines'
            '${item.children == null ? "" : ", ${item.children!.length} children"}');
        for (final inline in item.inlines) {
          _writeInline(buf, inline, indent + 2);
        }
        if (item.children != null) {
          for (final sub in item.children!) {
            _writeNode(buf, sub, indent + 2);
          }
        }
      }
    case BlockquoteNode():
      buf.writeln('$pad$node');
      for (final child in node.children) {
        _writeNode(buf, child, indent + 1);
      }
  }
}

void _writeInline(StringBuffer buf, InlineNode node, int indent) {
  final pad = '  ' * indent;
  switch (node) {
    case TextRun():
      buf.writeln('$pad$node');
    case EmRun(:final children):
      buf.writeln('${pad}EmRun');
      for (final c in children) {
        _writeInline(buf, c, indent + 1);
      }
    case StrongRun(:final children):
      buf.writeln('${pad}StrongRun');
      for (final c in children) {
        _writeInline(buf, c, indent + 1);
      }
    case LineBreakRun():
      buf.writeln('${pad}LineBreakRun');
    case LinkRun(:final href, :final children):
      buf.writeln('${pad}LinkRun($href)');
      for (final c in children) {
        _writeInline(buf, c, indent + 1);
      }
    case InlineCodeRun(:final text):
      buf.writeln('${pad}InlineCodeRun(${text.length} chars): $text');
    case EmojiRun(:final name, :final url, :final isOnlyEmoji):
      buf.writeln('${pad}EmojiRun(:$name:${isOnlyEmoji ? " only" : ""}) $url');
    case MentionRun(:final username, :final href, :final statusEmoji):
      buf.writeln('${pad}MentionRun(@$username -> $href)');
      if (statusEmoji != null) {
        _writeInline(buf, statusEmoji, indent + 1);
      }
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
    this.initiallyExpanded = true,
  });

  final String title;
  final IconData icon;
  final Widget child;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded,
        leading: Icon(icon),
        title: Text(title),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [SizedBox(width: double.infinity, child: child)],
      ),
    );
  }
}

/// Gallery 内置 emoji builder。
///
/// fixture 用的 emoji 名映射到 Unicode 字符,系统字体直出
/// (macOS Apple Color Emoji / Windows Segoe UI Emoji / Linux Noto Color
/// Emoji)。这样不联网也能展示真 emoji,避免子包 fallback chip 出现。
///
/// 自定义 emoji(如 :bili_114:)没有 Unicode 对应,fall through 到子包
/// defaultEmojiImageBuilder 的 chip 占位 —— 那是合理的演示场景。
Widget _galleryEmojiBuilder(
  BuildContext context,
  EmojiRun emoji,
  double size,
) {
  final unicode = _emojiUnicode[emoji.name];
  if (unicode == null) {
    return defaultEmojiImageBuilder(context, emoji, size);
  }
  return SizedBox(
    width: size,
    height: size,
    child: Center(
      child: Text(
        unicode,
        style: TextStyle(fontSize: size, height: 1.0),
      ),
    ),
  );
}

/// fixture 用到的 emoji 名 → Unicode 映射。
/// 新增 fixture 用到新 emoji 时在这里补充即可。
const _emojiUnicode = <String, String>{
  'heart': '❤️',
  'smile': '\u{1F642}',
  'fire': '\u{1F525}',
  'tada': '\u{1F389}',
  'star': '⭐',
};
