import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:copypaste/src/host.dart';
import 'package:copypaste/src/models.dart';
import 'package:copypaste/src/panel.dart';
import 'package:copypaste/src/state.dart';
import 'package:copypaste/src/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Host stub: the preview only needs the panel to render, not to talk to macOS.
class FakeHost implements HostApi {
  @override
  Stream<Map<Object?, Object?>> get events => const Stream<Map<Object?, Object?>>.empty();

  @override
  Future<Map<Object?, Object?>> ready() async => <Object?, Object?>{
        'items': <Object?>[],
        'settings': <Object?, Object?>{},
      };

  @override
  Future<void> beginHotkeyCapture() async {}

  @override
  Future<void> cancelHotkeyCapture() async {}

  @override
  Future<void> clearHistory({bool keepPinned = true}) async {}

  @override
  Future<void> copyItem(String id) async {}

  @override
  Future<void> deleteItem(String id) async {}

  @override
  Future<void> hide() async {}

  @override
  Future<void> logUi(String message) async {}

  @override
  Future<void> pasteItem(String id, {bool autoPaste = true}) async {}

  @override
  Future<void> quit() async {}

  @override
  Future<void> requestAccessibility() async {}

  @override
  Future<void> revealItem(String id) async {}

  @override
  Future<void> setPanelHeight(double height) async {}

  @override
  Future<void> setPeekVisible(bool visible) async {}

  @override
  Future<void> setPinned(String id, bool pinned) async {}

  @override
  Future<void> setSetting(String key, Object? value) async {}
}

const List<(String, ClipKind, String, String, int)> _sample = <(String, ClipKind, String, String, int)>[
  ('1', ClipKind.text, 'https://flutter.dev/docs/get-started/macos', 'Safari', 48),
  ('2', ClipKind.text, 'SELECT id, title, created_at FROM clippings ORDER BY created_at DESC LIMIT 50;', 'DataGrip', 78),
  ('3', ClipKind.image, 'Скриншот 2560×1440', 'CleanShot X', 980),
  ('4', ClipKind.files, 'Смета_финал.xlsx', 'Finder', 24),
  ('5', ClipKind.rich, 'Уважаемый Андрей, отправляю правки по макету — стекло уже ближе к системному.', 'Mail', 210),
  ('6', ClipKind.text, '#0A84FF', 'Digital Color Meter', 7),
  ('7', ClipKind.text, 'npm run build && open build/macos/Build/Products/Release/CopyPaste.app', 'Terminal', 66),
  ('8', ClipKind.files, 'design-glass-v7.fig', 'Finder', 1400),
];

List<ClipItem> _items() {
  final DateTime now = DateTime.now();
  final List<ClipItem> items = <ClipItem>[];
  // More entries than fit in the panel, so the preview also shows the
  // scrollbar that hints at the history below the fold.
  const int count = 22;
  for (int i = 0; i < count; i++) {
    final (String id, ClipKind kind, String preview, String app, int bytes) =
        _sample[i % _sample.length];
    items.add(
      ClipItem(
        id: '$id-$i',
        kind: kind,
        preview: preview,
        search: preview.toLowerCase(),
        fileNames: kind == ClipKind.files ? <String>[preview] : const <String>[],
        fileCount: kind == ClipKind.files ? 1 : 0,
        sourceApp: app,
        createdAt: now.subtract(Duration(minutes: i * 7 + 1)),
        pinned: i == 1 || i == 3,
        bytes: bytes,
        width: kind == ClipKind.image ? 2560 : 0,
        height: kind == ClipKind.image ? 1440 : 0,
      ),
    );
  }
  return items;
}

Future<void> _loadSystemFont() async {
  const List<String> candidates = <String>[
    '/System/Library/Fonts/SFNS.ttf',
    '/System/Library/Fonts/Supplemental/Arial.ttf',
  ];
  for (final String path in candidates) {
    final File file = File(path);
    if (!file.existsSync()) continue;
    final Uint8List bytes = await file.readAsBytes();
    final FontLoader loader = FontLoader('SFP');
    loader.addFont(Future<ByteData>.value(ByteData.view(bytes.buffer)));
    await loader.load();
    break;
  }
  // Icons come from Flutter's bundled Material icon font, which a golden test
  // does not load on its own (they would render as empty boxes).
  final File icons = File(
    '/opt/homebrew/share/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  );
  if (icons.existsSync()) {
    final Uint8List bytes = await icons.readAsBytes();
    final FontLoader loader = FontLoader('MaterialIcons');
    loader.addFont(Future<ByteData>.value(ByteData.view(bytes.buffer)));
    await loader.load();
  }
}

/// Mock desktop wallpaper so the glass has something to refract.
Widget _wallpaper() {
  return DecoratedBox(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[Color(0xFF16233D), Color(0xFF4C2A55), Color(0xFFB5563A), Color(0xFFE8A85C)],
      ),
    ),
    child: Stack(
      children: <Widget>[
        Positioned(
          left: -80,
          top: -40,
          child: Container(
            width: 320,
            height: 320,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: <Color>[const Color(0xFFFFD9A0).withValues(alpha: 0.85), const Color(0x00FFD9A0)],
              ),
            ),
          ),
        ),
        Positioned(
          right: -60,
          bottom: 40,
          child: Container(
            width: 280,
            height: 280,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: <Color>[const Color(0xFF6FC3FF).withValues(alpha: 0.55), const Color(0x006FC3FF)],
              ),
            ),
          ),
        ),
        Positioned(
          left: 40,
          bottom: -60,
          child: Container(
            width: 240,
            height: 240,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: <Color>[const Color(0xFF9AE6B4).withValues(alpha: 0.35), const Color(0x009AE6B4)],
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

Future<void> _renderPreview(
  WidgetTester tester, {
  required String name,
  required bool dark,
  required AppState state,
  String? query,
  bool settings = false,
}) async {
  final double cardHeight = state.desiredHeight;
  final Size size = Size(PanelMetrics.width + PanelMetrics.margin * 2, cardHeight + PanelMetrics.margin * 2);

  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);

  if (query != null) state.setQuery(query);
  if (settings) state.openSettings();

  final ThemeData baseTheme = buildPanelTheme(
    brightness: dark ? Brightness.dark : Brightness.light,
    accent: state.accentColor,
  );
  final ThemeData theme = baseTheme.copyWith(
    textTheme: baseTheme.textTheme.apply(fontFamily: 'SFP'),
    primaryTextTheme: baseTheme.primaryTextTheme.apply(fontFamily: 'SFP'),
  );

  final GlobalKey boundaryKey = GlobalKey();

  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      home: RepaintBoundary(
        key: boundaryKey,
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: Stack(
            children: <Widget>[
              Positioned.fill(child: _wallpaper()),
              // Stands in for the native NSGlassEffectView / NSVisualEffectView.
              Positioned(
                left: PanelMetrics.margin,
                top: PanelMetrics.margin,
                right: PanelMetrics.margin,
                bottom: PanelMetrics.margin,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(PanelMetrics.radius),
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 34, sigmaY: 34),
                    child: const ColoredBox(color: Color(0x14FFFFFF)),
                  ),
                ),
              ),
              Theme(
                data: theme,
                child: Material(
                  type: MaterialType.transparency,
                  child: DefaultTextStyle(
                    style: TextStyle(fontFamily: 'SFP', color: theme.colorScheme.onSurface),
                    child: PanelScreen(state: state, host: FakeHost()),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 400));

  final RenderRepaintBoundary boundary =
      boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final ui.Image image = await boundary.toImage(pixelRatio: 2);
  final ByteData? data = await image.toByteData(format: ui.ImageByteFormat.png);
  final Directory dir = Directory('preview')..createSync(recursive: true);
  File('${dir.path}/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _loadSystemFont();
  });

  testWidgets('renders light panel preview', (WidgetTester tester) async {
    final AppState state = AppState(FakeHost())
      ..items = _items()
      ..settings = const AppSettings(accessibility: true, accent: 0x0A84FF, dark: false);
    await _renderPreview(tester, name: 'panel_light', dark: false, state: state);
  });

  testWidgets('renders dark panel preview', (WidgetTester tester) async {
    final AppState state = AppState(FakeHost())
      ..items = _items()
      ..settings = const AppSettings(accessibility: true, accent: 0x0A84FF, dark: true);
    await _renderPreview(tester, name: 'panel_dark', dark: true, state: state);
  });

  testWidgets('renders search preview', (WidgetTester tester) async {
    final AppState state = AppState(FakeHost())
      ..items = _items()
      ..settings = const AppSettings(accessibility: true, accent: 0x0A84FF, dark: false);
    await _renderPreview(tester, name: 'panel_search', dark: false, state: state, query: 'fin');
  });

  testWidgets('renders settings preview', (WidgetTester tester) async {
    final AppState state = AppState(FakeHost())
      ..items = _items()
      ..settings = const AppSettings(accessibility: false, accent: 0x0A84FF, dark: false);
    await _renderPreview(tester, name: 'panel_settings', dark: false, state: state, settings: true);
  });
}
