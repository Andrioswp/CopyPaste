import 'package:copypaste/src/host.dart';
import 'package:copypaste/src/models.dart';
import 'package:copypaste/src/panel.dart';
import 'package:copypaste/src/state.dart';
import 'package:copypaste/src/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeHost implements HostApi {
  @override
  Stream<Map<Object?, Object?>> get events => const Stream.empty();
  @override
  Future<Map<Object?, Object?>> ready() async => <Object?, Object?>{};
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

void main() {
  testWidgets('panel paints content-aware rows', (WidgetTester tester) async {
    final AppState state = AppState(_FakeHost())
      ..items = <ClipItem>[
        ClipItem(
          id: '1',
          kind: ClipKind.text,
          preview: 'https://example.com/x',
          search: 'https://example.com/x',
          fileNames: const <String>[],
          fileCount: 0,
          sourceApp: 'Safari',
          createdAt: DateTime.now(),
          pinned: true,
          bytes: 20,
          width: 0,
          height: 0,
        ),
        ClipItem(
          id: '2',
          kind: ClipKind.text,
          preview: '#FF5500',
          search: '#ff5500',
          fileNames: const <String>[],
          fileCount: 0,
          sourceApp: 'Meter',
          createdAt: DateTime.now(),
          pinned: false,
          bytes: 7,
          width: 0,
          height: 0,
        ),
        ClipItem(
          id: '3',
          kind: ClipKind.text,
          preview: 'ssh -i key host',
          search: 'ssh -i key host',
          fileNames: const <String>[],
          fileCount: 0,
          sourceApp: 'Terminal',
          createdAt: DateTime.now(),
          pinned: false,
          bytes: 14,
          width: 0,
          height: 0,
        ),
      ]
      ..settings = const AppSettings(accessibility: true);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPanelTheme(brightness: Brightness.light, accent: defaultAccent),
        home: Material(
          type: MaterialType.transparency,
          child: SizedBox(
            width: PanelMetrics.width + PanelMetrics.margin * 2,
            height: 700,
            child: PanelScreen(state: state, host: _FakeHost()),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('CopyPaste'), findsOneWidget);
    expect(find.text('example.com/x'), findsOneWidget);
    expect(find.text('#FF5500'), findsOneWidget);
    expect(find.textContaining('ssh'), findsOneWidget);
    // Header badge removed — count lives in the footer only.
    expect(find.text('3'), findsNothing);
    expect(find.textContaining('записи'), findsOneWidget);
  });
}
