import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';

import 'host.dart';
import 'models.dart';
import 'theme.dart';

enum PanelPage { history, settings }

/// Single source of truth for the panel UI. Native events are the only way
/// the history changes; the UI never mutates the list locally.
class AppState extends ChangeNotifier {
  AppState(this.host);

  final HostApi host;
  StreamSubscription<Map<Object?, Object?>>? _subscription;

  List<ClipItem> items = <ClipItem>[];
  AppSettings settings = const AppSettings();
  String query = '';
  int selected = 0;
  PanelPage page = PanelPage.history;
  bool capturingHotkey = false;

  /// True when the panel was placed above the cursor: the list is then drawn
  /// in reverse, with the newest entry closest to the input field.
  bool flipped = false;

  /// Set by [selectFromPointer]; the panel reads and clears it.
  bool pointerSelection = false;
  bool axBannerDismissed = false;
  String? notice;
  String? menuItemId;
  double menuX = 0;
  double menuY = 0;
  bool ready = false;

  /// Increments every time the native panel is shown; the UI uses it to
  /// reset the query and focus the search field.
  final ValueNotifier<int> showTick = ValueNotifier<int>(0);

  Future<void> bootstrap() async {
    // Subscribe first: the host starts pushing history right after the engine
    // boots, and the very first `ready` call may race with channel setup.
    _subscription = host.events.listen(_onEvent);
    for (int attempt = 0; attempt < 25; attempt++) {
      try {
        final Map<Object?, Object?> snapshot = await host.ready();
        _applySnapshot(snapshot);
        ready = true;
        notifyListeners();
        return;
      } catch (_) {
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }
    }
    notice = 'Не удалось связаться с системным слоем приложения';
    notifyListeners();
  }

  void _applySnapshot(Map<Object?, Object?> snapshot) {
    items = _parseItems(snapshot['items']);
    final Object? rawSettings = snapshot['settings'];
    if (rawSettings is Map<Object?, Object?>) {
      settings = AppSettings.fromMap(rawSettings);
    }
  }

  List<ClipItem> _parseItems(Object? value) {
    if (value is! List) return <ClipItem>[];
    return value
        .whereType<Map<Object?, Object?>>()
        .map(ClipItem.fromMap)
        .toList(growable: false);
  }

  void _onEvent(Map<Object?, Object?> event) {
    switch ('${event['type']}') {
      case 'history':
        items = _parseItems(event['items']);
        _clampSelection();
      case 'settings':
        final Object? raw = event['settings'];
        if (raw is Map<Object?, Object?>) {
          settings = AppSettings.fromMap(raw);
        }
      case 'shown':
        query = '';
        page = PanelPage.history;
        selected = 0;
        menuItemId = null;
        // The host reports whether the panel had to open above the cursor; in
        // that case the list is rendered bottom-up so the newest entry sits
        // right next to the input field.
        flipped = event['flipped'] == true;
        showTick.value++;
      case 'openSettings':
        page = PanelPage.settings;
        showTick.value++;
      case 'hotkeyCapture':
        capturingHotkey = false;
        final Object? spec = event['spec'];
        if (spec is Map<Object?, Object?>) {
          settings = AppSettings(
            hotkey: HotkeySpec.fromMap(spec),
            autoPaste: settings.autoPaste,
            launchAtLogin: settings.launchAtLogin,
            maxItems: settings.maxItems,
            glassStyle: settings.glassStyle,
            appearance: settings.appearance,
            accessibility: settings.accessibility,
            accent: settings.accent,
            dark: settings.dark,
            version: settings.version,
          );
        } else {
          notice = 'Сочетание не назначено';
          _clearNoticeLater();
        }
      case 'notice':
        final String text = '${event['text'] ?? ''}';
        if (text.isNotEmpty) {
          notice = text;
          _clearNoticeLater();
        }
    }
    notifyListeners();
  }

  void _clearNoticeLater() {
    Timer(const Duration(seconds: 4), () {
      if (notice != null) {
        notice = null;
        notifyListeners();
      }
    });
  }

  void setQuery(String value) {
    query = value;
    selected = 0;
    notifyListeners();
  }

  void dismissAxBanner() {
    axBannerDismissed = true;
    notifyListeners();
  }

  void openSettings() {
    page = PanelPage.settings;
    notifyListeners();
    _reportHeight();
  }

  void closeSettings() {
    page = PanelPage.history;
    notifyListeners();
    _reportHeight();
  }

  void setCapturing(bool value) {
    capturingHotkey = value;
    notifyListeners();
  }

  void select(int index) {
    if (ordered.isEmpty) return;
    pointerSelection = false;
    selected = index.clamp(0, ordered.length - 1);
    notifyListeners();
  }

  /// Selection driven by the pointer position. The panel skips auto-scrolling
  /// for it: the row under the cursor is already visible, and scrolling the
  /// list here made the highlight jump between rows on fast mouse movement.
  void selectFromPointer(int index) {
    if (ordered.isEmpty) return;
    final int clamped = index.clamp(0, ordered.length - 1);
    if (clamped == selected) return;
    pointerSelection = true;
    selected = clamped;
    notifyListeners();
  }

  void moveSelection(int delta) {
    if (ordered.isEmpty) return;
    final int next = selected + delta;
    if (next < 0) {
      selected = ordered.length - 1;
    } else if (next >= ordered.length) {
      selected = 0;
    } else {
      selected = next;
    }
    notifyListeners();
  }

  void _clampSelection() {
    if (ordered.isEmpty) {
      selected = 0;
      return;
    }
    selected = selected.clamp(0, ordered.length - 1);
  }

  void openMenu(String id, double x, double y) {
    menuItemId = id;
    menuX = x;
    menuY = y;
    notifyListeners();
  }

  void closeMenu() {
    if (menuItemId == null) return;
    menuItemId = null;
    notifyListeners();
  }

  List<ClipItem> get filtered =>
      items.where((ClipItem item) => item.matches(query)).toList(growable: false);

  List<ClipItem> get pinned =>
      filtered.where((ClipItem item) => item.pinned).toList(growable: false);

  List<ClipItem> get recent =>
      filtered.where((ClipItem item) => !item.pinned).toList(growable: false);

  /// Flattened order used for keyboard navigation: pinned first.
  List<ClipItem> get ordered => <ClipItem>[...pinned, ...recent];

  ClipItem? get selectedItem {
    final List<ClipItem> list = ordered;
    if (list.isEmpty) return null;
    return list[selected.clamp(0, list.length - 1)];
  }

  bool get showAxBanner =>
      settings.autoPaste && !settings.accessibility && !axBannerDismissed;

  /// Accent colour reported by AppKit, with a sane fallback.
  Color get accentColor =>
      settings.accent == 0 ? defaultAccent : Color(0xFF000000 | settings.accent);

  /// Height of the glass card, so the native window can hug the content.
  double get desiredHeight {
    final double banners =
        (showAxBanner ? 42 : 0) + (notice != null ? 34 : 0);
    if (page == PanelPage.settings) return 520 + banners;
    double height = PanelMetrics.headerHeight + PanelMetrics.searchHeight;
    final List<ClipItem> pinnedItems = pinned;
    final List<ClipItem> recentItems = recent;
    int budget = PanelMetrics.maxRows.toInt();
    int rows = 0;
    int headers = 0;
    if (pinnedItems.isNotEmpty) {
      headers++;
      final int take = math.min(pinnedItems.length, budget);
      rows += take;
      budget -= take;
    }
    if (recentItems.isNotEmpty && budget > 0) {
      headers++;
      rows += math.min(recentItems.length, budget);
    }
    if (rows == 0) {
      height += 132;
    } else {
      height += headers * PanelMetrics.sectionLabelHeight;
      height += rows * PanelMetrics.rowHeight;
    }
    height += PanelMetrics.footerHeight + 10 + banners;
    return height.clamp(250, 820);
  }

  double _reportedHeight = -1;

  void _reportHeight() {
    final double height = desiredHeight;
    if ((height - _reportedHeight).abs() < 0.5) return;
    _reportedHeight = height;
    unawaited(host.setPanelHeight(height));
  }

  /// Called by the panel after every rebuild to keep the window snug.
  void syncPanelHeight() {
    if (!ready) return;
    if (page == PanelPage.settings) {
      _reportHeight();
      return;
    }
    _reportHeight();
  }

  Future<void> pasteSelected() async {
    final ClipItem? item = selectedItem;
    if (item == null) return;
    await host.pasteItem(item.id, autoPaste: settings.autoPaste);
  }

  Future<void> paste(ClipItem item) => host.pasteItem(item.id, autoPaste: settings.autoPaste);

  Future<void> copyOnly(ClipItem item) => host.copyItem(item.id);

  Future<void> togglePin(ClipItem item) => host.setPinned(item.id, !item.pinned);

  Future<void> remove(ClipItem item) => host.deleteItem(item.id);

  Future<void> clearHistory() => host.clearHistory(keepPinned: true);

  Future<void> hide() => host.hide();

  Future<void> requestAccessibilityFromUi() async {
    await host.requestAccessibility();
    notice = 'Включи CopyPaste в списке «Универсальный доступ» и вернись сюда';
    notifyListeners();
    _clearNoticeLater();
  }

  Future<void> quitApp() => host.quit();

  Future<void> reveal(ClipItem item) => host.revealItem(item.id);

  Future<void> setSetting(String key, Object? value) => host.setSetting(key, value);

  Future<void> beginCapture() async {
    setCapturing(true);
    await host.beginHotkeyCapture();
  }

  Future<void> cancelCapture() async {
    setCapturing(false);
    await host.cancelHotkeyCapture();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    showTick.dispose();
    super.dispose();
  }
}
