// AudioNode parser 测试。
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo_render/fluxdo_render.dart';

void main() {
  final parser = ParagraphParser();

  test('<audio><source src .. type ..><a>文本</a> → AudioNode', () {
    const html = '<p><audio preload="metadata" controls>'
        '<source src="/uploads/x.mp3" type="audio/mpeg" data-orig-src="upload://abc.mp3">'
        '<a href="/uploads/x.mp3">/uploads/x.mp3</a></audio></p>';
    final audio = parser.parse(html).whereType<AudioNode>().single;
    expect(audio.src, '/uploads/x.mp3');
    expect(audio.mime, 'audio/mpeg');
    expect(audio.title, '/uploads/x.mp3');
  });

  test('source 无 src 时回退 data-orig-src', () {
    const html = '<audio controls><source data-orig-src="upload://abc.mp3"></audio>';
    final audio = parser.parse(html).whereType<AudioNode>().single;
    expect(audio.src, 'upload://abc.mp3');
  });
}
