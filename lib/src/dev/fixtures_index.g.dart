// GENERATED — do not edit by hand.
// 重新生成: dart run test/fixtures/scripts/gen_fixtures_index.dart

import 'fixtures_index.dart';

const List<FixtureEntry> allFixtures = [
  FixtureEntry(
    relativePath: r'''_edge_cases/nested_quote_three_levels.html''',
    html: r'''<p>正文段落 1。</p>
<aside class="quote">
<blockquote>
<aside class="quote">
<blockquote>
<aside class="quote">
<blockquote><p>最里层引用,深三层。</p></blockquote>
</aside>
<p>中间层补充。</p>
</blockquote>
</aside>
<p>最外层引用补充。</p>
</blockquote>
</aside>
<p>正文段落 2,引用之后。</p>
''',
    notes: r'''深三层嵌套 quote(aside > blockquote > aside > blockquote > aside > blockquote)。
用于验证递归渲染 + 嵌套层级缩进 + 跨层级 margin 折叠。
历史上 fwfh 在这种 case 上偶有"丢失中间层"的问题。''',
    source: r'''https://example.com/t/sample/1/5''',
    edgeCase: true,
  ),
  FixtureEntry(
    relativePath: r'''code_block/dart_hello_world.html''',
    html: r'''<pre><code class="lang-dart">void main() {
  print('hello');
}
</code></pre>
''',
    notes: r'''<pre><code class="lang-dart"> 形态,3 行 dart 代码。
用于验证代码块基础渲染 + 语言识别。''',
    source: r'''https://example.com/t/sample/1/3''',
    edgeCase: false,
  ),
  FixtureEntry(
    relativePath: r'''heading/h1_h2_h3.html''',
    html: r'''<h1>顶层标题</h1>
<h2>二级标题</h2>
<h3>三级标题</h3>
''',
    notes: r'''h1/h2/h3 三级标题相邻,用于验证标题样式 + margin 折叠。''',
    source: r'''https://example.com/t/sample/1/2''',
    edgeCase: false,
  ),
  FixtureEntry(
    relativePath: r'''heading/h1_only.html''',
    html: r'''<h1>这是一级标题(h1)</h1>
''',
    notes: r'''最简形态:单个 <h1>,验证最大字号 + 加粗 + 上下间距。''',
    source: r'''https://example.com/t/sample/1/h1''',
    edgeCase: false,
  ),
  FixtureEntry(
    relativePath: r'''heading/h2_only.html''',
    html: r'''<h2>这是二级标题(h2)</h2>
''',
    notes: r'''单个 <h2>,Discourse 最常用的标题级别。''',
    source: r'''https://example.com/t/sample/1/h2''',
    edgeCase: false,
  ),
  FixtureEntry(
    relativePath: r'''heading/h2_with_inline.html''',
    html: r'''<h2>标题中含 <em>斜体</em> 和 <strong>粗体</strong> 与 <br>换行</h2>
''',
    notes: r'''h2 内含 <em> / <strong> / <br>,验证 heading 复用 InlineFlattener
的嵌套样式合并 + LineBreak。''',
    source: r'''https://example.com/t/sample/1/h2-inline''',
    edgeCase: false,
  ),
  FixtureEntry(
    relativePath: r'''heading/h3_only.html''',
    html: r'''<h3>这是三级标题(h3)</h3>
''',
    notes: r'''单个 <h3>。''',
    source: r'''https://example.com/t/sample/1/h3''',
    edgeCase: false,
  ),
  FixtureEntry(
    relativePath: r'''heading/h4_h5_h6.html''',
    html: r'''<h4>这是四级标题(h4)</h4>
<h5>这是五级标题(h5)</h5>
<h6>这是六级标题(h6)</h6>
''',
    notes: r'''h4 / h5 / h6 三个低级别标题相邻,验证字号梯度 + 间距。''',
    source: r'''https://example.com/t/sample/1/h456''',
    edgeCase: false,
  ),
  FixtureEntry(
    relativePath: r'''heading/heading_with_paragraphs.html''',
    html: r'''<h2>章节 1</h2>
<p>这是章节 1 的正文,验证 heading 跟下一段 paragraph 的间距。</p>
<h2>章节 2</h2>
<p>章节 2 的正文段落。</p>
''',
    notes: r'''heading 跟 paragraph 交替,验证两类节点间距过渡是否符合视觉直觉
(heading 上下 margin 大于 paragraph)。''',
    source: r'''https://example.com/t/sample/1/h2-p''',
    edgeCase: false,
  ),
  FixtureEntry(
    relativePath: r'''inline_code/inside_link.html''',
    html: r'''<p>查看 <a href="https://api.flutter.dev/flutter/widgets/RichText-class.html"><code>RichText</code> 文档</a> 了解细节。</p>
''',
    notes: r'''Inline code 嵌套在 link 内 — 验证 LinkRun.children 含 InlineCodeRun 时
正常渲染:tap 区域含 code 文本,code 仍是 monospace + 灰底,link 下划线
覆盖 code 文本。''',
    source: r'''https://example.com/t/sample/1/inline_code5''',
    edgeCase: true,
  ),
  FixtureEntry(
    relativePath: r'''inline_code/long_breaking.html''',
    html: r'''<p>长命令示例:<code>flutter run -d macos --dart-define=FLAVOR=staging --observatory-port=9100</code> 在终端里换行也要正常显示。</p>
''',
    notes: r'''超长 inline code,会强制跨行。当前阶段灰底用 TextStyle.background
(矩形),跨行会出现两行各自带矩形(不会合并)。这是已知缺陷,
阶段 5 自研 paint 时补齐(对应 InlineCodePainter 跨行 RRect 合并)。''',
    source: r'''https://example.com/t/sample/1/inline_code4''',
    edgeCase: true,
  ),
  FixtureEntry(
    relativePath: r'''inline_code/multiple.html''',
    html: r'''<p>常用命令有 <code>git status</code>、<code>git diff</code> 和 <code>git log</code>,各自查看不同信息。</p>
''',
    notes: r'''一段里多个 InlineCodeRun 紧邻,验证灰底不要错位、相邻代码段之间正常
断字。''',
    source: r'''https://example.com/t/sample/1/inline_code2''',
    edgeCase: false,
  ),
  FixtureEntry(
    relativePath: r'''inline_code/simple.html''',
    html: r'''<p>使用 <code>flutter pub get</code> 拉取依赖。</p>
''',
    notes: r'''最简单的行内代码:中文段落里夹一段命令。验证 InlineCodeRun 基础渲染
(monospace + 灰底)。''',
    source: r'''https://example.com/t/sample/1/inline_code1''',
    edgeCase: false,
  ),
  FixtureEntry(
    relativePath: r'''inline_code/special_chars.html''',
    html: r'''<p>注意 HTML 实体:<code>&lt;div class="foo"&gt;</code> 在源码里是字面值。</p>
''',
    notes: r'''代码内含 HTML 实体(&lt; &gt; &amp; &quot;),package:html 应自动反转义
成 < > & ",InlineCodeRun.text 应是字面值。''',
    source: r'''https://example.com/t/sample/1/inline_code3''',
    edgeCase: false,
  ),
  FixtureEntry(
    relativePath: r'''paragraph/link_empty_href.html''',
    html: r'''<p>这是 <a href="">空 href 的 a 标签</a>,应该退化为普通文本。</p>
<p>这是 <a>无 href 的 a 标签</a>,同样退化。</p>
''',
    notes: r'''边界 case:空 href / 无 href 属性的 a 标签。parser 应该退化为
普通文本(展平子节点),不该产生 LinkRun。视觉上跟纯文本一致,
无下划线、不可点。''',
    source: r'''https://example.com/t/sample/1/link5''',
    edgeCase: true,
  ),
  FixtureEntry(
    relativePath: r'''paragraph/link_internal.html''',
    html: r'''<p>内部链接示例:<a href="/t/topic/12345/3">某个话题</a> 和 <a href="/u/alice">某个用户</a>。</p>
''',
    notes: r'''内部链接(/t/topic/.../post 和 /u/username),主项目侧 LinkHandler
应该走 launchContentLink 路由到 TopicDetailPage / UserProfilePage。
子包侧只验证 LinkRun 携带的 href 字符串原值。''',
    source: r'''https://example.com/t/sample/1/link2''',
    edgeCase: false,
  ),
  FixtureEntry(
    relativePath: r'''paragraph/link_multiple.html''',
    html: r'''<p>段落 1 含 <a href="https://example.com/1">链接 1</a>。</p>
<p>段落 2 含 <a href="https://example.com/2">链接 2</a>。</p>
<p>段落 3 含 <a href="https://example.com/3">链接 3</a>。</p>
''',
    notes: r'''多段落 + 每段一个链接,验证多 LinkRun 的 recognizer 全部正确管理
(没有 widget dispose 时 leak)。''',
    source: r'''https://example.com/t/sample/1/link3''',
    edgeCase: false,
  ),
  FixtureEntry(
    relativePath: r'''paragraph/link_simple_external.html''',
    html: r'''<p>这是含 <a href="https://example.com">外部链接</a> 的段落。</p>
''',
    notes: r'''段落内含一个外部 https 链接。验证 LinkRun(InlineNode)基础渲染
(下划线 + 可点击)。link 不是 NodeKind,fixture 归属 paragraph。''',
    source: r'''https://example.com/t/sample/1/link1''',
    edgeCase: false,
  ),
  FixtureEntry(
    relativePath: r'''paragraph/link_with_inline_style.html''',
    html: r'''<p>包含 <a href="https://example.com"><strong>粗体</strong> 和 <em>斜体</em></a> 的链接。</p>
''',
    notes: r'''链接内嵌 <strong> + <em>,验证 link span 内部嵌套样式合并:
bold + italic 样式应该被保留,link 的下划线也应该有。''',
    source: r'''https://example.com/t/sample/1/link4''',
    edgeCase: false,
  ),
  FixtureEntry(
    relativePath: r'''paragraph/multi_p.html''',
    html: r'''<p>第一段内容,普通段落。</p>
<p>第二段,跟第一段之间隔了一个段落边界。</p>
<p>第三段,验证多段渲染顺序与间距。</p>
''',
    notes: r'''三个相邻 <p>,验证多段渲染顺序与垂直间距。''',
    source: r'''https://example.com/t/sample/1/p3''',
    edgeCase: false,
  ),
  FixtureEntry(
    relativePath: r'''paragraph/nested_emphasis.html''',
    html: r'''<p>外层 <em>外层斜体 <strong>嵌套粗体 <em>双重斜体</em> 后续</strong> 后续</em> 收尾</p>
''',
    notes: r'''em / strong 三层嵌套,验证 InlineFlattener 嵌套样式合并。
历史上 fwfh 在深嵌套场景下偶尔丢中间层样式。''',
    source: r'''https://example.com/t/sample/1/p4''',
    edgeCase: false,
  ),
  FixtureEntry(
    relativePath: r'''paragraph/plain_text.html''',
    html: r'''<p>这是一段最简单的纯文本段落,没有任何行内样式。</p>
''',
    notes: r'''最简形态:单个 <p> 内只有纯文本,无任何行内样式。
阶段 1.1 的"基础渲染"用例。''',
    source: r'''https://example.com/t/sample/1/p1''',
    edgeCase: false,
  ),
  FixtureEntry(
    relativePath: r'''paragraph/simple_with_em_strong.html''',
    html: r'''<p>这是一段最简单的段落,含 <em>斜体</em> 与 <strong>粗体</strong>。</p>
''',
    notes: r'''最简形态:一个 <p> 内含 <em> + <strong>。
用于验证段落 + 行内基础样式渲染。''',
    source: r'''https://example.com/t/sample/1/1''',
    edgeCase: false,
  ),
  FixtureEntry(
    relativePath: r'''paragraph/with_br.html''',
    html: r'''<p>line 1 内容<br>line 2 在 br 之后<br>line 3</p>
''',
    notes: r'''单个段落内含多个 <br> 强制换行,用于验证 LineBreakRun 渲染。''',
    source: r'''https://example.com/t/sample/1/p2''',
    edgeCase: false,
  ),
  FixtureEntry(
    relativePath: r'''quote_card/single_layer_simple.html''',
    html: r'''<aside class="quote no-group" data-username="alice" data-post="1" data-topic="999">
<div class="title">
<div class="quote-controls"></div>
<img alt="" width="20" height="20" src="https://example.com/avatar/alice/40.png" class="avatar"> alice:</div>
<blockquote>
<p>这是一段被引用的内容。</p>
</blockquote>
</aside>
<p>这是回复正文。</p>
''',
    notes: r'''单层引用卡(aside.quote)含用户头像 + 用户名 + 引用正文,后跟回复段落。
这是 Discourse 最常见的"@回复"形态。''',
    source: r'''https://example.com/t/sample/1/4''',
    edgeCase: false,
  ),
];
