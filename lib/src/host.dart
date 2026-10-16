import 'dart:async';

import 'package:flutter/services.dart';

/// Everything the UI can ask the native host to do. Kept as an interface so
/// the panel can be rendered (and previewed in tests) without macOS.
abstract class HostApi {
  Future<Map<Object?, Object?>> ready();

  Stream<Map<Object?, Object?>> get events;

  Future<void> hide();

  Future<void> pasteItem(String id, {bool autoPaste = true});

  Future<void> copyItem(String id);

  Future<void> setPinned(String id, bool pinned);

  Future<void> deleteItem(String id);

  Future<void> clearHistory({bool keepPinned = true});

  Future<void> setSetting(String key, Object? value);

  Future<void> beginHotkeyCapture();

  Future<void> cancelHotkeyCapture();

  Future<void> setPanelHeight(double height);

  /// Widens the native window so the hover-preview card fits to the right
  /// of the glass pane without covering the list.
  Future<void> setPeekVisible(bool visible);

  Future<void> requestAccessibility();

  Future<void> revealItem(String id);

  /// Writes a line to the host's diagnostic log (used to trace pointer events).
  Future<void> logUi(String message);

  Future<void> quit();
}

class NativeHost implements HostApi {
  NativeHost() {
    _events = _eventChannel
        .receiveBroadcastStream()
        .map((Object? event) => (event as Map<Object?, Object?>));
  }

  static const MethodChannel _methodChannel = MethodChannel('copypaste/host');
  static const EventChannel _eventChannel = EventChannel('copypaste/events');

  late final Stream<Map<Object?, Object?>> _events;

  @override
  Stream<Map<Object?, Object?>> get events => _events;

  @override
  Future<Map<Object?, Object?>> ready() async {
    final Object? result = await _methodChannel.invokeMethod<Object?>('ready');
    return result is Map<Object?, Object?> ? result : <Object?, Object?>{};
  }

  @override
  Future<void> hide() => _invoke('hide');

  @override
  Future<void> pasteItem(String id, {bool autoPaste = true}) =>
      _invoke('paste', <String, Object?>{'id': id, 'autoPaste': autoPaste});

  @override
  Future<void> copyItem(String id) => _invoke('copy', <String, Object?>{'id': id});

  @override
  Future<void> setPinned(String id, bool pinned) =>
      _invoke('pin', <String, Object?>{'id': id, 'pinned': pinned});

  @override
  Future<void> deleteItem(String id) => _invoke('delete', <String, Object?>{'id': id});

  @override
  Future<void> clearHistory({bool keepPinned = true}) =>
      _invoke('clear', <String, Object?>{'keepPinned': keepPinned});

  @override
  Future<void> setSetting(String key, Object? value) =>
      _invoke('setSetting', <String, Object?>{'key': key, 'value': value});

  @override
  Future<void> beginHotkeyCapture() => _invoke('beginHotkeyCapture');

  @override
  Future<void> cancelHotkeyCapture() => _invoke('cancelHotkeyCapture');

  @override
  Future<void> setPanelHeight(double height) =>
      _invoke('setHeight', <String, Object?>{'height': height});

  @override
  Future<void> setPeekVisible(bool visible) =>
      _invoke('setPeekVisible', <String, Object?>{'visible': visible});

  @override
  Future<void> requestAccessibility() => _invoke('requestAccessibility');

  @override
  Future<void> revealItem(String id) => _invoke('reveal', <String, Object?>{'id': id});

  @override
  Future<void> logUi(String message) => _invoke('log', <String, Object?>{'message': message});

  @override
  Future<void> quit() => _invoke('quit');

  Future<void> _invoke(String method, [Map<String, Object?>? args]) async {
    try {
      await _methodChannel.invokeMethod<Object?>(method, args);
    } on PlatformException {
      // The host is the source of truth; a failed call is not fatal for the UI.
    } on MissingPluginException {
      // Running outside of the macOS host (tests, previews).
    }
  }
}
