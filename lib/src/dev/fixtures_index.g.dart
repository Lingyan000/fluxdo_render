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
    relativePath: r'''blockquote/multi_paragraph.html''',
    html: r'''<blockquote>
<p>第一段引用。</p>
<p>第二段引用,跟第一段同属一个 blockquote。</p>
</blockquote>
''',
    notes: r'''多段引用,验证 blockquote 内多个 ParagraphNode 之间 1em 段间距
仍生效(段落自己有 vertical em padding,blockquote 容器只加外 8px)。''',
    source: r'''https://example.com/t/sample/1/bq2''',
    edgeCase: false,
  ),
  FixtureEntry(
    relativePath: r'''blockquote/nested_three_levels.html''',
    html: r'''<blockquote>
<p>外层引用。</p>
<blockquote>
<p>中层引用。</p>
<blockquote>
<p>最里层引用。</p>
</blockquote>
</blockquote>
</blockquote>
''',
    notes: r'''三层嵌套 blockquote。验证 parser 递归 + renderer 递归 build。
每层都有自己的灰底 + 左竖条,深嵌套时视觉层次清晰。''',
    source: r'''https://example.com/t/sample/1/bq4''',
    edgeCase: true,
  ),
  FixtureEntry(
    relativePath: r'''blockquote/simple.html''',
    html: r'''<blockquote>
<p>这是一段普通的引用。</p>
</blockquote>
''',
    notes: r'''最基础形态:单 blockquote 含一段 p。验证 BlockquoteNode 解析 +
灰底 + 左竖条 + 右上下圆角。''',
    source: r'''https://example.com/t/sample/1/bq1''',
    edgeCase: false,
  ),
  FixtureEntry(
    relativePath: r'''blockquote/with_inline_mix.html''',
    html: r'''<blockquote>
<p>引用里含 <strong>粗体</strong>、<em>斜体</em>、<code>inline code</code> 和 <a href="https://example.com">链接</a>。</p>
</blockquote>
''',
    notes: r'''引用内含 strong/em/code/link inline 混排。验证 inline 节点在
blockquote 子段落里正常渲染,字色受 DefaultTextStyle.merge 影响
(onSurfaceVariant,但 link 仍是 primary 因为 LinkRun 显式设)。''',
    source: r'''https://example.com/t/sample/1/bq3''',
    edgeCase: false,
  ),
  FixtureEntry(
    relativePath: r'''blockquote/with_list_inside.html''',
    html: r'''<blockquote>
<p>引用前置说明。</p>
<ul>
<li>引用内的列表项 1</li>
<li>引用内的列表项 2,含 <a href="/x">链接</a></li>
</ul>
<p>引用后置说明。</p>
</blockquote>
''',
    notes: r'''引用内含 list:p + ul + p 混合。验证 BlockquoteNode.children 是
BlockNode 序列,可以包含 ParagraphNode + ListNode 等任意块级类型,
renderer 通过 build() dispatch 递归。''',
    source: r'''https://example.com/t/sample/1/bq5''',
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
    relativePath: r'''code_block/json_with_entities.html''',
    html: r'''<pre><code class="lang-json">{
  "name": "fluxdo",
  "version": "1.0.0",
  "dependencies": {
    "flutter": "&gt;=3.10.0",
    "html": "^0.15.0"
  }
}
</code></pre>
''',
    notes: r'''JSON 代码块含 HTML 实体 &gt;(>),验证 package:html 自动解码,
CodeBlockNode.code 是字面值 ">"。''',
    source: r'''https://example.com/t/sample/1/code4''',
    edgeCase: false,
  ),
  FixtureEntry(
    relativePath: r'''code_block/long_line_scrolls.html''',
    html: r'''<pre><code class="lang-bash">flutter run -d macos --dart-define=FLAVOR=staging --observatory-port=9100 --enable-vm-service --disable-service-auth-codes
echo "this is a very long single line that should trigger horizontal scrolling because we cannot wrap code"
</code></pre>
''',
    notes: r'''超长单行 bash 命令,验证横向滚动(SingleChildScrollView Axis.horizontal)。
不会换行,可左右滑动查看完整命令。''',
    source: r'''https://example.com/t/sample/1/code5''',
    edgeCase: true,
  ),
  FixtureEntry(
    relativePath: r'''code_block/no_language.html''',
    html: r'''<pre><code>plain text without language hint
just multiple lines
no syntax highlight needed
</code></pre>
''',
    notes: r'''无 lang-xxx class 的 pre/code,验证 language = null + 顶栏显示 "TEXT"。''',
    source: r'''https://example.com/t/sample/1/code3''',
    edgeCase: false,
  ),
  FixtureEntry(
    relativePath: r'''code_block/python_function.html''',
    html: r'''<pre><code class="lang-python">def hello():
    print("hi")
    return 42
</code></pre>
''',
    notes: r'''python 函数,验证非 dart 语言 lang-xxx 解析。''',
    source: r'''https://example.com/t/sample/1/code2''',
    edgeCase: false,
  ),
  FixtureEntry(
    relativePath: r'''emoji/custom_emoji.html''',
    html: r'''<p>自定义表情 <img src="https://cdn.example.com/uploads/custom/bili_114.gif" alt=":bili_114:" class="emoji emoji-custom" title=":bili_114:"> 来自 Discourse。</p>
''',
    notes: r'''自定义 emoji(Discourse extendedEmojiMap,服务端 customEmoji),URL 来自
CDN 而非确定性路径。验证 parser 不做 CDN 重写,把原 src 原样存入
EmojiRun.url —— 主项目的 EmojiImageBuilder 自行做 CDN 路由。
附加 `emoji-custom` class 不影响 parser(只检查 `emoji`)。''',
    source: r'''https://example.com/t/sample/1/emoji4''',
    edgeCase: false,
  ),
  FixtureEntry(
    relativePath: r'''emoji/in_heading_vs_paragraph.html''',
    html: r'''<h2>H2 标题里 <img src="https://example.com/images/emoji/twitter/star.png?v=12" alt=":star:" class="emoji" title=":star:"> 的 emoji</h2>
<p>段落里 <img src="https://example.com/images/emoji/twitter/star.png?v=12" alt=":star:" class="emoji" title=":star:"> 的 emoji 应该比上面小。</p>
''',
    notes: r'''H2 里的 emoji 应该跟随父字号(更大),段落里的 emoji 是 1em。
验证 emoji 尺寸跟随 baseStyle.fontSize(InlineFlattener 把
baseStyle.fontSize 传给 emojiBuilder 作 size)。''',
    source: r'''https://example.com/t/sample/1/emoji5''',
    edgeCase: true,
  ),
  FixtureEntry(
    relativePath: r'''emoji/multiple.html''',
    html: r'''<p>多个表情 <img src="https://example.com/images/emoji/twitter/smile.png?v=12" alt=":smile:" class="emoji" title=":smile:"> <img src="https://example.com/images/emoji/twitter/heart.png?v=12" alt=":heart:" class="emoji" title=":heart:"> <img src="https://example.com/images/emoji/twitter/fire.png?v=12" alt=":fire:" class="emoji" title=":fire:"> 一起。</p>
''',
    notes: r'''一段里多个 emoji 紧邻,验证 WidgetSpan 之间不互相错位。''',
    source: r'''https://example.com/t/sample/1/emoji2''',
    edgeCase: false,
  ),
  FixtureEntry(
    relativePath: r'''emoji/only_emoji_large.html''',
    html: r'''<p><img src="https://example.com/images/emoji/twitter/tada.png?v=12" alt=":tada:" class="emoji only-emoji" title=":tada:"></p>
''',
    notes: r'''整段仅含 emoji + class="only-emoji",Discourse 渲染为 32dp 大图。
验证 EmojiRun.isOnlyEmoji 解析 + 32px 显示。''',
    source: r'''https://example.com/t/sample/1/emoji3''',
    edgeCase: false,
  ),
  FixtureEntry(
    relativePath: r'''emoji/simple_heart.html''',
    html: r'''<p>Hello <img src="https://example.com/images/emoji/twitter/heart.png?v=12" alt=":heart:" class="emoji" title=":heart:"> world.</p>
''',
    notes: r'''最基础形态:段落内嵌 :heart: 标准 emoji。验证 EmojiRun 解析 +
WidgetSpan 渲染 + 1em 字号(跟 baseStyle 一致)。''',
    source: r'''https://example.com/t/sample/1/emoji1''',
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
    relativePath: r'''horizontal_rule/between_paragraphs.html''',
    html: r'''<p>前一段。</p>
<hr>
<p>后一段。</p>
''',
    notes: r'''hr 在两段之间,验证视觉分隔效果:p 段落本身上下有 1em margin,
hr 自带 12 上下 padding,叠加不会塌缩(Column 不折叠 margin)。''',
    source: r'''https://example.com/t/sample/1/hr2''',
    edgeCase: false,
  ),
  FixtureEntry(
    relativePath: r'''horizontal_rule/multiple_consecutive.html''',
    html: r'''<hr>
<hr>
<hr>
''',
    notes: r'''连续 3 条 hr(罕见但合法)。每条独立 BlockNode,id 各自递增;
视觉上三条等距分隔线。''',
    source: r'''https://example.com/t/sample/1/hr3''',
    edgeCase: true,
  ),
  FixtureEntry(
    relativePath: r'''horizontal_rule/simple.html''',
    html: r'''<hr>
''',
    notes: r'''最基础形态:单独一条 hr。验证 HorizontalRuleNode 解析 + 1px 线
+ 上下 12 padding。''',
    source: r'''https://example.com/t/sample/1/hr1''',
    edgeCase: false,
  ),
  FixtureEntry(
    relativePath: r'''image/inside_link.html''',
    html: r'''<p>点击查看大图:<a href="https://example.com/lightbox/foo"><img src="https://example.com/upload/thumb.png" alt="thumbnail" width="100" height="100"></a></p>
''',
    notes: r'''img 嵌套在 link 内 — 验证 LinkRun.children 含 ImageRun 正常解析。
注意:WidgetSpan 不带 recognizer,所以图片本身**不可点**(已知限制,
跟 emoji-in-link 同源,留到阶段 5 自研选区时统一解决)。主项目接入
通常会在 imageContentBuilder 内自己包 GestureDetector 处理 lightbox。''',
    source: r'''https://example.com/t/sample/1/img4''',
    edgeCase: true,
  ),
  FixtureEntry(
    relativePath: r'''image/lightbox_consecutive.html''',
    html: r'''<p><strong>段落 1。</strong></p>
<p><div class="lightbox-wrapper"><a class="lightbox" href="https://cdn.example.com/original/img1.png" title="img1"><img src="https://cdn.example.com/optimized/img1_690x52.png" alt="img1" width="690" height="52"><div class="meta"><svg class="d-icon"><use href="#far-image"></use></svg><span class="filename">img1</span><span class="informations">1686×128 15.7 KB</span></div></a></div><br>
<div class="lightbox-wrapper"><a class="lightbox" href="https://cdn.example.com/original/img2.png" title="img2"><img src="https://cdn.example.com/optimized/img2_509x500.png" alt="img2" width="509" height="500"><div class="meta"><svg class="d-icon"><use href="#far-image"></use></svg><span class="filename">img2</span><span class="informations">832×816 54.4 KB</span></div></a></div></p>
<p><strong>段落 2,两图之后。</strong></p>
''',
    notes: r'''两张连续 lightbox-wrapper(中间 <br> 分隔)。重要回归 case:
不能让两张图各产 ParagraphNode,否则 1em+1em margin 堆出大空隙。
parser 改:lightbox 走 pendingInlines 流,两张图 + LineBreakRun 合并
到同一 ParagraphNode,自然垂直排列且段间距正常。''',
    source: r'''https://example.com/t/sample/1/img7''',
    edgeCase: true,
  ),
  FixtureEntry(
    relativePath: r'''image/lightbox_wrapper.html''',
    html: r'''<p><strong>段落 1。</strong></p>
<p><div class="lightbox-wrapper"><a class="lightbox" href="https://cdn.example.com/original/4X/d/1/e/abcdef.png" data-download-href="/uploads/short-url/xyz.png?dl=1" title="d5112e737a71778e6de420459be91f92" rel="noopener nofollow ugc"><img src="https://cdn.example.com/optimized/4X/d/1/e/abcdef_2_690x52.png" alt="d5112e737a71778e6de420459be91f92" data-base62-sha1="xyz" width="690" height="52"><div class="meta"><svg class="fa d-icon d-icon-far-image svg-icon" aria-hidden="true"><use href="#far-image"></use></svg><span class="filename">d5112e737a71778e6de420459be91f92</span><span class="informations">1686×128 15.7 KB</span><svg class="fa d-icon d-icon-discourse-expand svg-icon" aria-hidden="true"><use href="#discourse-expand"></use></svg></div></a></div></p>
<p><strong>段落 2,图片之后。</strong></p>
''',
    notes: r'''Discourse cooked 把上传图包成 lightbox-wrapper:
  div.lightbox-wrapper > a.lightbox(href=原图) > img(src=缩略图) +
  div.meta(文件名 + 尺寸 + svg)
HTML5 不允许 p 含 div,package:html 会自动闭合 p,所以 wrapper 实际
顶层 block。Parser 应该:
  1. 识别 div.lightbox-wrapper
  2. 提 img 的 src (缩略图) + a 的 href (原图,填 lightboxUrl)
  3. .meta 子树不进 textContent(否则会显示 filename + 尺寸 KB 文字)
没修之前:全靠 fallback textContent 把 .meta 文字渲染成 "filename 尺寸 KB"。''',
    source: r'''https://example.com/t/sample/1/img6''',
    edgeCase: true,
  ),
  FixtureEntry(
    relativePath: r'''image/multiple_in_paragraph.html''',
    html: r'''<p>对比图:<img src="https://example.com/upload/before.png" alt="before" width="120" height="80"> 和 <img src="https://example.com/upload/after.png" alt="after" width="120" height="80"></p>
''',
    notes: r'''一段里多张图,验证 WidgetSpan 之间正常排列 + 中间文本不被吞。''',
    source: r'''https://example.com/t/sample/1/img3''',
    edgeCase: false,
  ),
  FixtureEntry(
    relativePath: r'''image/simple.html''',
    html: r'''<p>看这张截图:<img src="https://example.com/upload/screenshot.png" alt="screenshot"></p>
''',
    notes: r'''最基础形态:段落内一张无尺寸 img。验证 ImageRun 解析(width/height
= null)+ 子包默认 builder 走 fallback placeholder(假 URL 加载失败)。''',
    source: r'''https://example.com/t/sample/1/img1''',
    edgeCase: false,
  ),
  FixtureEntry(
    relativePath: r'''image/standalone_blocks.html''',
    html: r'''<p>第一张图:</p>
<p><img src="https://example.com/upload/first.png" alt="first" width="200" height="120"></p>
<p>第二张图:</p>
<p><img src="https://example.com/upload/second.png" alt="second" width="200" height="120"></p>
''',
    notes: r'''Discourse 通常把图片 cooked 成独立 `<p><img></p>` 块,验证两张图
各自独立段落。这是图片帖正文最常见的形态。''',
    source: r'''https://example.com/t/sample/1/img5''',
    edgeCase: true,
  ),
  FixtureEntry(
    relativePath: r'''image/with_dimensions.html''',
    html: r'''<p>固定尺寸的图:<img src="https://example.com/upload/diagram.png" alt="diagram" width="200" height="120"></p>
''',
    notes: r'''带 width/height attribute,验证 parser 把数字 attribute 转 double
填到 ImageRun.width/height,fallback placeholder 用这个尺寸撑出
正确的占位框。''',
    source: r'''https://example.com/t/sample/1/img2''',
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
    relativePath: r'''list/nested_ul_ol.html''',
    html: r'''<ul>
<li>外层第一项
<ul>
<li>嵌套 A</li>
<li>嵌套 B</li>
</ul>
</li>
<li>外层第二项
<ol>
<li>嵌套有序 1</li>
<li>嵌套有序 2</li>
</ol>
</li>
</ul>
''',
    notes: r'''嵌套混合(外层 ul 含 li 内 ul 和 li 内 ol)。验证 parser 递归 +
ListItem.children + depth 递增 + renderer 递归 buildList。''',
    source: r'''https://example.com/t/sample/1/list4''',
    edgeCase: true,
  ),
  FixtureEntry(
    relativePath: r'''list/ol_simple.html''',
    html: r'''<ol>
<li>第一步:打开终端</li>
<li>第二步:运行命令</li>
<li>第三步:查看结果</li>
</ol>
''',
    notes: r'''最基础有序列表(ol + 3 li)。验证数字 marker (1. 2. 3.) +
ordered = true。''',
    source: r'''https://example.com/t/sample/1/list2''',
    edgeCase: false,
  ),
  FixtureEntry(
    relativePath: r'''list/ol_two_digit.html''',
    html: r'''<ol>
<li>第一项</li>
<li>第二项</li>
<li>第三项</li>
<li>第四项</li>
<li>第五项</li>
<li>第六项</li>
<li>第七项</li>
<li>第八项</li>
<li>第九项</li>
<li>第十项</li>
</ol>
''',
    notes: r'''10 项有序列表,验证 "9." 和 "10." 数字 marker 对齐(FontFeature
tabularFigures 等宽数字)。如果没启用等宽特性,9 比 10 窄,文本
起始位置会左移。''',
    source: r'''https://example.com/t/sample/1/list5''',
    edgeCase: true,
  ),
  FixtureEntry(
    relativePath: r'''list/ul_simple.html''',
    html: r'''<ul>
<li>苹果</li>
<li>香蕉</li>
<li>橙子</li>
</ul>
''',
    notes: r'''最基础无序列表(ul + 3 li 纯文本)。验证 ListNode/ListItem 解析 +
bullet marker (•) + padding-left 20。''',
    source: r'''https://example.com/t/sample/1/list1''',
    edgeCase: false,
  ),
  FixtureEntry(
    relativePath: r'''list/with_inline_mix.html''',
    html: r'''<ul>
<li>第一项 含 <strong>粗体</strong> 和 <a href="https://example.com">链接</a></li>
<li>第二项 含 <code>inline code</code> 和 <em>斜体</em></li>
<li>第三项 含 <img src="https://example.com/images/emoji/twitter/heart.png" alt=":heart:" class="emoji" title=":heart:"> emoji</li>
</ul>
''',
    notes: r'''list 项内含 inline 混排:strong + link + code + em + emoji。
验证 InlineSpanText 在 list item 内正常复用,所有 inline 节点
都能在 li 内正确渲染(包括 LinkRun recognizer + EmojiRun WidgetSpan)。''',
    source: r'''https://example.com/t/sample/1/list3''',
    edgeCase: false,
  ),
  FixtureEntry(
    relativePath: r'''mention/group_mention.html''',
    html: r'''<p>问题反馈给 <a class="mention" href="/u/team_support">@team_support</a> 组,而不是个人。</p>
''',
    notes: r'''group mention(`@team_support`)用法跟单人 mention 完全一致,
主项目用户卡跳转时按 username 自动区分 user / group。这条 fixture
确保 parser 不对 username 形态(下划线 / 短横线)做特殊处理。''',
    source: r'''https://example.com/t/sample/1/mention4''',
    edgeCase: false,
  ),
  FixtureEntry(
    relativePath: r'''mention/multiple.html''',
    html: r'''<p>多人 <a class="mention" href="/u/alice">@alice</a> <a class="mention" href="/u/bob">@bob</a> <a class="mention" href="/u/charlie">@charlie</a> 同时参与。</p>
''',
    notes: r'''一段里多个 mention 紧邻,验证 chip 之间不互相错位 + 字间距合理。''',
    source: r'''https://example.com/t/sample/1/mention2''',
    edgeCase: false,
  ),
  FixtureEntry(
    relativePath: r'''mention/non_mention_user_link.html''',
    html: r'''<p>普通用户链接 <a href="/u/bob">@bob</a> 没有 class=mention,应该走普通 LinkRun。这种形态由主项目 mentionedUsers 列表识别后追加 class,parser 阶段不该主动猜。</p>
''',
    notes: r'''反例:`<a href="/u/bob">@bob</a>` 没有 class="mention",应该解析为
普通 LinkRun(不带 chip 样式)。验证 parser 只在 class=mention 时
走 MentionRun 分支,主项目若想识别为 mention,应在 cooked HTML
预处理阶段加 class(legacy 是这么做的)。''',
    source: r'''https://example.com/t/sample/1/mention5''',
    edgeCase: true,
  ),
  FixtureEntry(
    relativePath: r'''mention/simple.html''',
    html: r'''<p>欢迎 <a class="mention" href="/u/alice">@alice</a> 加入。</p>
''',
    notes: r'''最基础形态:段落内一个 @alice mention。验证 MentionRun 解析 +
chip 样式渲染(灰底圆角 + primary 字 + 0.82em)。''',
    source: r'''https://example.com/t/sample/1/mention1''',
    edgeCase: false,
  ),
  FixtureEntry(
    relativePath: r'''mention/with_status_emoji.html''',
    html: r'''<p>状态用户 <a class="mention" href="/u/alice">@alice<img src="https://example.com/images/emoji/twitter/fire.png?v=12" class="emoji mention-status" alt=":fire:" title=":fire:" style="width:14px;height:14px;vertical-align:middle;margin-left:2px"></a> 在线。</p>
''',
    notes: r'''含状态 emoji 的 mention(Discourse 主项目通过 _preprocessHtml 注入
`<img class="emoji mention-status">`,parser 把它从 a 子树挑出来
填到 MentionRun.statusEmoji)。验证 chip 内 emoji 在用户名右侧 +
size 跟父 chip 字号 * 1.2。''',
    source: r'''https://example.com/t/sample/1/mention3''',
    edgeCase: true,
  ),
  FixtureEntry(
    relativePath: r'''onebox/default_with_thumbnail.html''',
    html: r'''<aside class="onebox allowlistedgeneric" data-onebox-src="https://example.com/article">
<header class="source">
<img src="https://example.com/favicon.ico" class="site-icon" data-dominant-color="3a3a3a" width="32" height="32">
<a href="https://example.com/article" target="_blank" rel="noopener nofollow ugc">example.com</a>
</header>
<article class="onebox-body">
<div class="aspect-image">
<img src="https://example.com/thumb.jpg" class="thumbnail" data-dominant-color="888888" width="690" height="345">
</div>
<h3><a href="https://example.com/article" target="_blank" rel="noopener nofollow ugc">A Generic Article Title</a></h3>
<p>This is the article description shown in the onebox preview card,
providing a few lines of summary so the reader gets context before
clicking through to the actual page.</p>
</article>
</aside>
''',
    notes: r'''Discourse 默认 onebox 形态(allowlistedgeneric):header.source 含
favicon + 站点名,article 含 thumbnail + h3 标题 + p 描述。
应识别为 OneboxKind.defaultKind。''',
    source: r'''https://example.com/t/sample/1/onebox1''',
    edgeCase: false,
  ),
  FixtureEntry(
    relativePath: r'''onebox/github_pr.html''',
    html: r'''<aside class="onebox githubpullrequest" data-onebox-src="https://github.com/owner/repo/pull/123">
<header class="source">
<img src="https://github.com/favicon.ico" class="site-icon" width="32" height="32">
<a href="https://github.com/owner/repo/pull/123" target="_blank" rel="noopener nofollow ugc">github.com</a>
</header>
<article class="onebox-body">
<h4><a href="https://github.com/owner/repo/pull/123" target="_blank">Add feature X to handle Y</a></h4>
<div class="github-row">
<div class="user">
<img alt="" src="https://avatars.githubusercontent.com/u/12345" class="thumbnail onebox-avatar-inline" width="20" height="20">
<a href="https://github.com/somebody" target="_blank">somebody</a>
</div>
</div>
<p>This PR refactors the X module to support Y. Closes #100, fixes the issue
where users couldn't do Z.</p>
</article>
</aside>
''',
    notes: r'''GitHub Pull Request onebox(class="onebox githubpullrequest")。
应识别为 OneboxKind.github。子包通用卡片只显示标题 + 描述 + favicon;
legacy 完整版含作者头像 / 文件统计等,主项目 oneboxBuilder 可接管。''',
    source: r'''https://example.com/t/sample/1/onebox2''',
    edgeCase: false,
  ),
  FixtureEntry(
    relativePath: r'''onebox/youtube.html''',
    html: r'''<aside class="onebox youtube-onebox" data-onebox-src="https://www.youtube.com/watch?v=dQw4w9WgXcQ">
<header class="source">
<img src="https://www.youtube.com/favicon.ico" class="site-icon" width="16" height="16">
<a href="https://www.youtube.com/watch?v=dQw4w9WgXcQ" target="_blank" rel="noopener nofollow ugc">www.youtube.com</a>
</header>
<article class="onebox-body">
<div class="aspect-image-full-size">
<img src="https://img.youtube.com/vi/dQw4w9WgXcQ/maxresdefault.jpg" class="thumbnail" data-dominant-color="222222" width="690" height="388">
</div>
<h3><a href="https://www.youtube.com/watch?v=dQw4w9WgXcQ" target="_blank">A YouTube Video Title</a></h3>
<p>Video description provided by Discourse's youtube onebox.</p>
</article>
</aside>
''',
    notes: r'''YouTube 视频 onebox(class="onebox youtube-onebox")。
应识别为 OneboxKind.video。子包通用卡片展示标题 + 缩略图;
legacy 完整版有播放按钮覆盖 + 时长,主项目可在 oneboxBuilder 内
调 video_onebox_builder。''',
    source: r'''https://example.com/t/sample/1/onebox3''',
    edgeCase: false,
  ),
  FixtureEntry(
    relativePath: r'''paragraph/inline_svg_skip.html''',
    html: r'''<p>含 <svg class="fa d-icon d-icon-far-image svg-icon" aria-hidden="true"><use href="#far-image"></use></svg> 图标的段落,svg 应该完全跳过,不留任何文字噪音。</p>
''',
    notes: r'''inline `<svg>` (Discourse d-icon)应该被 parser 整体跳过。
不跳过会出现 `<use href="#far-image">` 字面值进 textContent
形成噪音。''',
    source: r'''https://example.com/t/sample/1/svg_skip''',
    edgeCase: true,
  ),
  FixtureEntry(
    relativePath: r'''paragraph/ins_del_diff.html''',
    html: r'''<p>编辑前:这是 <del>旧文本</del> 段落。</p>
<p>编辑后:这是 <ins>新文本</ins> 段落。</p>
<p>合并:这是 <del>旧</del><ins>新</ins> 部分。</p>
''',
    notes: r'''编辑历史 diff 形态:`<ins>` 新增 / `<del>` 删除。
阶段 1 简化:ins 降级 EmRun(斜体);del 展平内容(信息保留无样式)。
阶段 2 应该加 InsertedRun / DeletedRun + 绿/红着色。''',
    source: r'''https://example.com/t/sample/1/insdel''',
    edgeCase: true,
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
    relativePath: r'''quote_card/nested_quote.html''',
    html: r'''<aside class="quote" data-username="outer_user" data-post="2" data-topic="111">
<div class="title">
<img alt="" src="https://example.com/avatar/outer/40.png" class="avatar">
outer_user:
</div>
<blockquote>
<p>外层引用包了一个内层引用:</p>
<aside class="quote" data-username="inner_user" data-post="1" data-topic="111">
<div class="title">
<img alt="" src="https://example.com/avatar/inner/40.png" class="avatar">
inner_user:
</div>
<blockquote>
<p>这是最内层的引用内容。</p>
</blockquote>
</aside>
<p>外层的回应。</p>
</blockquote>
</aside>
''',
    notes: r'''双层嵌套引用(quote 内含 quote)。验证 parser 递归 + renderer 内递归
build,每层都有自己的灰底 + 头像。''',
    source: r'''https://example.com/t/sample/1/qc4''',
    edgeCase: true,
  ),
  FixtureEntry(
    relativePath: r'''quote_card/no_title_block.html''',
    html: r'''<aside class="quote" data-username="dave" data-post="7" data-topic="999">
<blockquote>
<p>没有标题块,只有 data-username 和正文。</p>
</blockquote>
</aside>
''',
    notes: r'''反例:无 .title 块的 quote(罕见,但 Discourse 某些 plugin 输出会缺)。
验证 parser 容错:avatarUrl/titleText/titleHref 均为 null,头像走
首字母 chip fallback。''',
    source: r'''https://example.com/t/sample/1/qc5''',
    edgeCase: true,
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
  FixtureEntry(
    relativePath: r'''quote_card/with_rich_content.html''',
    html: r'''<aside class="quote" data-username="charlie" data-post="5" data-topic="999">
<div class="title">
<img alt="" src="https://example.com/avatar/charlie/40.png" class="avatar">
charlie:
</div>
<blockquote>
<p>第一段引用,含 <strong>粗体</strong>。</p>
<p>第二段引用,含 <a href="https://example.com">链接</a> 和 <code>code</code>。</p>
<ul>
<li>列表项 1</li>
<li>列表项 2</li>
</ul>
</blockquote>
</aside>
''',
    notes: r'''引用正文含 inline 混排(strong/code/link)+ list,验证 _parseBlocks
在 blockquote 内递归正常,所有 inline + block 都能在 quote 内显示。''',
    source: r'''https://example.com/t/sample/1/qc3''',
    edgeCase: false,
  ),
  FixtureEntry(
    relativePath: r'''quote_card/with_title.html''',
    html: r'''<aside class="quote" data-username="bob" data-post="3" data-topic="999">
<div class="title">
<div class="quote-controls"></div>
<img alt="" width="20" height="20" src="https://example.com/avatar/bob/40.png" class="avatar">
<a href="/t/topic-slug/999/3">原帖标题(新版格式)</a>
</div>
<blockquote>
<p>带标题的引用,标题应该是主色可点。</p>
</blockquote>
</aside>
''',
    notes: r'''含标题(.title 内 a 标签)的引用,验证 titleText/titleHref 解析 +
标题主色可点 + linkHandler 路由跳原帖。''',
    source: r'''https://example.com/t/sample/1/qc2''',
    edgeCase: false,
  ),
  FixtureEntry(
    relativePath: r'''spoiler/block_simple.html''',
    html: r'''<div class="spoiler">
<p>这是一段块级剧透内容。</p>
<p>包含两段,默认遮蔽,点击展开。</p>
</div>
''',
    notes: r'''块级 div.spoiler,默认显示 "剧透内容,点击显示" 占位,点击后
展开为两段段落。再点收回。''',
    source: r'''https://example.com/t/sample/1/sp2''',
    edgeCase: false,
  ),
  FixtureEntry(
    relativePath: r'''spoiler/block_with_rich_content.html''',
    html: r'''<div class="spoiler">
<p>块级剧透,内部含列表和代码:</p>
<ul>
<li>项 1</li>
<li>项 2:<code>flutter run</code></li>
</ul>
<p>结束。</p>
</div>
''',
    notes: r'''块级 spoiler 含 p + ul + code 等混合内容,验证 SpoilerBlockNode.children
是 BlockNode 序列(走 _parseBlocks 递归);揭示后内嵌内容完整展示。''',
    source: r'''https://example.com/t/sample/1/sp4''',
    edgeCase: true,
  ),
  FixtureEntry(
    relativePath: r'''spoiler/inline_simple.html''',
    html: r'''<p>答案是 <span class="spoiler">42</span>,你猜对了吗?</p>
''',
    notes: r'''最基础形态:span.spoiler 行内剧透。默认遮蔽为黑色块,点击展开
显示 "42"。''',
    source: r'''https://example.com/t/sample/1/sp1''',
    edgeCase: false,
  ),
  FixtureEntry(
    relativePath: r'''spoiler/inline_with_nested.html''',
    html: r'''<p>含 <span class="spoiler">关键 <strong>剧情</strong></span> 和 <span class="spoiler"><a href="https://example.com">线索链接</a></span> 的句子。</p>
''',
    notes: r'''行内 spoiler 含嵌套样式(strong)和 link。验证 SpoilerRun.children
可以承载任意 inline 节点;揭示后嵌套样式 + 链接全部生效(link 可点)。''',
    source: r'''https://example.com/t/sample/1/sp3''',
    edgeCase: true,
  ),
];
