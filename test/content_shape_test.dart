import 'package:copypaste/src/models.dart';
import 'package:flutter_test/flutter_test.dart';

ClipItem _text(String preview) => ClipItem(
      id: '1',
      kind: ClipKind.text,
      preview: preview,
      search: preview.toLowerCase(),
      fileNames: const <String>[],
      fileCount: 0,
      sourceApp: 'Cursor',
      createdAt: DateTime(2026, 10, 16, 9),
      pinned: false,
      bytes: preview.length,
      width: 0,
      height: 0,
    );

void main() {
  group('detectClipShape', () {
    test('classifies urls', () {
      expect(detectClipShape('https://alekseyignatyev.ru/'), ClipShape.url);
      expect(detectClipShape('www.example.com/docs'), ClipShape.url);
      expect(detectClipShape('flutter.dev/docs/get-started'), ClipShape.url);
    });

    test('classifies colours', () {
      expect(detectClipShape('#0A84FF'), ClipShape.color);
      expect(detectClipShape('#abc'), ClipShape.color);
      expect(detectClipShape('rgba(10, 132, 255, 0.5)'), ClipShape.color);
    });

    test('classifies code and shell', () {
      expect(
        detectClipShape('ssh -i ~/.ssh/key -L 2663:127.0.0.1:2663 host'),
        ClipShape.code,
      );
      expect(
        detectClipShape('SELECT id, title FROM clippings WHERE pinned = 1;'),
        ClipShape.code,
      );
      expect(detectClipShape('npm run build && open dist/'), ClipShape.code);
      expect(
        detectClipShape('const x = 1;\nfunction f() { return x; }'),
        ClipShape.code,
      );
    });

    test('leaves plain prose alone', () {
      expect(detectClipShape('Погода'), ClipShape.plain);
      expect(detectClipShape('The core issue is that the entire system'), ClipShape.plain);
    });
  });

  group('titles and subtitles', () {
    test('formats url titles without scheme', () {
      final ClipItem item = _text('https://alekseyignatyev.ru/projects/foo');
      expect(item.title, 'alekseyignatyev.ru/projects/foo');
      expect(item.shape, ClipShape.url);
    });

    test('omits byte size from text subtitles', () {
      final ClipItem item = ClipItem(
        id: '1',
        kind: ClipKind.text,
        preview: 'Погода',
        search: 'погода',
        fileNames: const <String>[],
        fileCount: 0,
        sourceApp: 'Cursor',
        createdAt: DateTime.now(),
        pinned: false,
        bytes: 12,
        width: 0,
        height: 0,
      );
      expect(item.subtitle, startsWith('Cursor · '));
      expect(item.subtitle.contains('Б'), isFalse);
      expect(item.subtitle.contains('КБ'), isFalse);
    });

    test('prefixes typed subtitles with a shape label', () {
      final ClipItem url = _text('https://example.com/path');
      expect(url.subtitle, startsWith('Ссылка · '));
      final ClipItem code = _text('ssh -i ~/.ssh/key host');
      expect(code.subtitle, startsWith('Код · '));
    });

    test('parses hex colours to ARGB', () {
      expect(parseHexColorValue('#0A84FF'), 0xFF0A84FF);
      expect(parseHexColorValue('#abc'), 0xFFAABBCC);
      expect(parseHexColorValue('not-a-color'), isNull);
    });
  });
}
