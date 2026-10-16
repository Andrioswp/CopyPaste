/// Domain models shared between the native host and the Flutter UI.
library;

enum ClipKind { text, rich, image, files, unknown }

/// Visual / typographic treatment for a text preview.
enum ClipShape { plain, url, code, color }

ClipKind clipKindFrom(Object? value) {
  switch ('$value') {
    case 'text':
      return ClipKind.text;
    case 'rich':
      return ClipKind.rich;
    case 'image':
      return ClipKind.image;
    case 'files':
      return ClipKind.files;
    default:
      return ClipKind.unknown;
  }
}

/// One entry of the clipboard history. The heavy payload (full text, blob
/// data) stays on the native side; the UI only needs a short preview.
class ClipItem {
  const ClipItem({
    required this.id,
    required this.kind,
    required this.preview,
    required this.search,
    required this.fileNames,
    required this.fileCount,
    required this.sourceApp,
    required this.createdAt,
    required this.pinned,
    required this.bytes,
    required this.width,
    required this.height,
    this.primaryFile = '',
    this.sourceIcon = '',
    this.blob,
  });

  final String id;
  final ClipKind kind;
  final String preview;
  final String search;
  final List<String> fileNames;
  final int fileCount;

  /// Full path of the first copied file, used for image thumbnails.
  final String primaryFile;
  final String sourceApp;

  /// Cached PNG of the source app icon (filled by the native host).
  final String sourceIcon;
  final DateTime createdAt;
  final bool pinned;
  final int bytes;
  final int width;
  final int height;
  final String? blob;

  static ClipItem fromMap(Map<Object?, Object?> map) {
    final double millis = (map['createdAt'] as num?)?.toDouble() ?? 0;
    return ClipItem(
      id: '${map['id'] ?? ''}',
      kind: clipKindFrom(map['kind']),
      preview: '${map['preview'] ?? ''}',
      search: '${map['search'] ?? ''}'.toLowerCase(),
      fileNames: ((map['fileNames'] as List?) ?? const <Object?>[])
          .map((Object? e) => '$e')
          .toList(growable: false),
      fileCount: (map['fileCount'] as num?)?.toInt() ?? 0,
      primaryFile: '${map['primaryFile'] ?? ''}',
      sourceApp: '${map['sourceApp'] ?? ''}',
      sourceIcon: '${map['sourceIcon'] ?? ''}',
      createdAt: DateTime.fromMillisecondsSinceEpoch(millis.round()),
      pinned: map['pinned'] == true,
      bytes: (map['bytes'] as num?)?.toInt() ?? 0,
      width: (map['width'] as num?)?.toInt() ?? 0,
      height: (map['height'] as num?)?.toInt() ?? 0,
      blob: map['blob'] as String?,
    );
  }

  /// Content-aware shape for badges and typography. Images and files keep
  /// their own glyphs; only text-like entries are classified.
  ClipShape get shape {
    switch (kind) {
      case ClipKind.image:
      case ClipKind.files:
        return ClipShape.plain;
      case ClipKind.text:
      case ClipKind.rich:
      case ClipKind.unknown:
        return detectClipShape(preview);
    }
  }

  /// First meaningful line, used as the row title.
  String get title {
    switch (kind) {
      case ClipKind.image:
        return width > 0 && height > 0
            ? 'Изображение $width×$height'
            : 'Изображение';
      case ClipKind.files:
        if (fileNames.isEmpty) return plural(fileCount, 'файл', 'файла', 'файлов');
        if (fileCount <= 1) return fileNames.first;
        return '${fileNames.first}  +${fileCount - 1}';
      case ClipKind.text:
      case ClipKind.rich:
      case ClipKind.unknown:
        final ClipShape detected = shape;
        if (detected == ClipShape.url) return formatUrlTitle(preview);
        if (detected == ClipShape.color) {
          final String hex = preview.trim();
          return hex.isEmpty ? '(пустая строка)' : hex;
        }
        final String line = preview.split('\n').firstWhere(
              (String l) => l.trim().isNotEmpty,
              orElse: () => preview,
            );
        final String clean = line.replaceAll(RegExp(r'\s+'), ' ').trim();
        return clean.isEmpty ? '(пустая строка)' : clean;
    }
  }

  /// Short type label for the subtitle (empty for plain text).
  String get shapeLabel {
    switch (kind) {
      case ClipKind.image:
        return 'Картинка';
      case ClipKind.files:
        return fileCount > 1 ? 'Файлы' : 'Файл';
      case ClipKind.text:
      case ClipKind.rich:
      case ClipKind.unknown:
        return switch (shape) {
          ClipShape.url => 'Ссылка',
          ClipShape.code => 'Код',
          ClipShape.color => 'Цвет',
          ClipShape.plain => '',
        };
    }
  }

  /// Secondary line: type · source · time. Byte size is omitted for text.
  String get subtitle {
    final List<String> parts = <String>[];
    final String label = shapeLabel;
    if (label.isNotEmpty) parts.add(label);
    if (sourceApp.isNotEmpty) parts.add(sourceApp);
    parts.add(relativeTime(createdAt));
    if (kind == ClipKind.files && fileCount > 1) {
      parts.add(plural(fileCount, 'файл', 'файла', 'файлов'));
    } else if (kind == ClipKind.image && bytes > 0) {
      parts.add(humanBytes(bytes));
    }
    return parts.join(' · ');
  }

  bool matches(String query) {
    if (query.isEmpty) return true;
    final String needle = query.toLowerCase().trim();
    if (needle.isEmpty) return true;
    for (final String word in needle.split(RegExp(r'\s+'))) {
      if (!search.contains(word)) return false;
    }
    return true;
  }
}

String plural(int n, String one, String few, String many) {
  final int mod10 = n % 10;
  final int mod100 = n % 100;
  if (mod10 == 1 && mod100 != 11) return '$n $one';
  if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) return '$n $few';
  return '$n $many';
}

final RegExp _hexColor = RegExp(
  r'^#(?:[0-9A-Fa-f]{3}|[0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$',
);
final RegExp _rgbColor = RegExp(
  r'^rgba?\(\s*\d{1,3}\s*,\s*\d{1,3}\s*,\s*\d{1,3}(?:\s*,\s*(?:0|1|0?\.\d+))?\s*\)$',
  caseSensitive: false,
);
final RegExp _urlScheme = RegExp(r'^(https?|ftp):\/\/', caseSensitive: false);
final RegExp _bareUrl = RegExp(
  r'^(?:www\.)?[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)+(?:[/:?#].*)?$',
  caseSensitive: false,
);
final RegExp _sqlKeywords = RegExp(
  r'\b(SELECT|INSERT|UPDATE|DELETE|FROM|WHERE|JOIN|CREATE|ALTER)\b',
  caseSensitive: false,
);

/// Classifies a text preview so the UI can pick a glyph and typeface.
ClipShape detectClipShape(String preview) {
  final String trimmed = preview.trim();
  if (trimmed.isEmpty) return ClipShape.plain;
  // Whole-string colour samples only — multi-line blobs stay plain/code.
  if (!trimmed.contains('\n') && looksLikeColor(trimmed)) return ClipShape.color;
  if (looksLikeUrl(trimmed)) return ClipShape.url;
  if (looksLikeCode(trimmed)) return ClipShape.code;
  return ClipShape.plain;
}

bool looksLikeColor(String value) =>
    _hexColor.hasMatch(value) || _rgbColor.hasMatch(value);

bool looksLikeUrl(String value) {
  final String candidate = value.trim().split(RegExp(r'\s+')).first;
  if (candidate.length < 4) return false;
  if (_urlScheme.hasMatch(candidate)) return true;
  // Bare host/path without a scheme — require a dot and a plausible TLD path.
  if (!candidate.contains('.') || candidate.contains(' ')) return false;
  if (candidate.contains('@') && !candidate.contains('/')) return false;
  return _bareUrl.hasMatch(candidate);
}

bool looksLikeCode(String value) {
  final String trimmed = value.trim();
  if (trimmed.isEmpty) return false;
  if (trimmed.contains('\n') &&
      (trimmed.contains('{') ||
          trimmed.contains(';') ||
          trimmed.contains('=>') ||
          trimmed.contains('```'))) {
    return true;
  }
  final String lower = trimmed.toLowerCase();
  const List<String> prefixes = <String>[
    'ssh ',
    'git ',
    'npm ',
    'yarn ',
    'pnpm ',
    'curl ',
    'wget ',
    'docker ',
    'kubectl ',
    'sudo ',
    '#!/',
    'import ',
    'export ',
    'const ',
    'let ',
    'var ',
    'function ',
    'def ',
    'class ',
    'package ',
    'SELECT ',
    'INSERT ',
    'UPDATE ',
    'DELETE ',
  ];
  for (final String prefix in prefixes) {
    if (lower.startsWith(prefix.toLowerCase())) return true;
  }
  if (_sqlKeywords.hasMatch(trimmed) && trimmed.contains(' ')) return true;
  return false;
}

/// Compact URL for the row title: `host/path` without the scheme.
String formatUrlTitle(String preview) {
  final String raw = preview.trim().split(RegExp(r'\s+')).first;
  if (raw.isEmpty) return '(пустая строка)';
  try {
    final Uri uri = Uri.parse(raw.contains('://') ? raw : 'https://$raw');
    final String host = uri.host.replaceFirst(RegExp(r'^www\.'), '');
    if (host.isEmpty) return raw;
    final String path = uri.path == '/' ? '' : uri.path;
    final String query = uri.hasQuery ? '?…' : '';
    final String fragment = uri.hasFragment ? '#…' : '';
    final String composed = '$host$path$query$fragment';
    if (composed.length <= 64) return composed;
    return '${composed.substring(0, 61)}…';
  } catch (_) {
    return raw;
  }
}

/// Parses `#RGB` / `#RRGGBB` / `#RRGGBBAA` into `0xAARRGGBB`, or null.
int? parseHexColorValue(String preview) {
  final String value = preview.trim();
  if (!_hexColor.hasMatch(value)) return null;
  String hex = value.substring(1);
  if (hex.length == 3) {
    hex = hex.split('').map((String c) => '$c$c').join();
  }
  if (hex.length == 6) hex = 'FF$hex';
  if (hex.length != 8) return null;
  return int.tryParse(hex, radix: 16);
}

String humanBytes(int bytes) {
  if (bytes < 1024) return '$bytes Б';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} КБ';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} МБ';
}

String relativeTime(DateTime time, {DateTime? now}) {
  final DateTime reference = now ?? DateTime.now();
  final Duration diff = reference.difference(time);
  if (diff.inSeconds < 5) return 'только что';
  if (diff.inSeconds < 60) return '${diff.inSeconds} с назад';
  if (diff.inMinutes < 60) return '${diff.inMinutes} мин назад';
  if (diff.inHours < 24 && reference.day == time.day) {
    return '${diff.inHours} ч назад';
  }
  final DateTime today = DateTime(reference.year, reference.month, reference.day);
  final DateTime day = DateTime(time.year, time.month, time.day);
  final int days = today.difference(day).inDays;
  if (days == 0) return '${diff.inHours} ч назад';
  if (days == 1) return 'вчера';
  if (days < 7) return '$days дн назад';
  final String dd = time.day.toString().padLeft(2, '0');
  final String mm = time.month.toString().padLeft(2, '0');
  return time.year == reference.year ? '$dd.$mm' : '$dd.$mm.${time.year}';
}

/// A global shortcut: Carbon virtual key code + Carbon modifier mask,
/// optionally requiring the Fn (Globe) key.
class HotkeySpec {
  const HotkeySpec({
    this.keyCode = 9,
    this.modifiers = 768,
    this.fn = false,
    this.fnOnly = false,
  });

  static const HotkeySpec fallback = HotkeySpec();

  final int keyCode;
  final int modifiers;
  final bool fn;
  final bool fnOnly;

  static const int cmd = 256;
  static const int shift = 512;
  static const int option = 2048;
  static const int control = 4096;

  bool get isEmpty => fnOnly == false && keyCode == 0;

  static HotkeySpec fromMap(Map<Object?, Object?> map) => HotkeySpec(
        keyCode: (map['keyCode'] as num?)?.toInt() ?? 9,
        modifiers: (map['modifiers'] as num?)?.toInt() ?? 768,
        fn: map['fn'] == true,
        fnOnly: map['fnOnly'] == true,
      );

  Map<String, Object?> toMap() => <String, Object?>{
        'keyCode': keyCode,
        'modifiers': modifiers,
        'fn': fn,
        'fnOnly': fnOnly,
      };

  String get label {
    if (fnOnly) return 'Fn';
    final StringBuffer buffer = StringBuffer();
    if (modifiers & control != 0) buffer.write('⌃');
    if (modifiers & option != 0) buffer.write('⌥');
    if (modifiers & shift != 0) buffer.write('⇧');
    if (modifiers & cmd != 0) buffer.write('⌘');
    if (fn) buffer.write('Fn+');
    buffer.write(keyName(keyCode));
    return buffer.toString();
  }

  /// Whether this shortcut needs the accessibility permission to be observed.
  bool get needsAccessibility => fn || fnOnly;
}

const Map<int, String> _keyNames = <int, String>{
  0: 'A', 1: 'S', 2: 'D', 3: 'F', 4: 'H', 5: 'G', 6: 'Z', 7: 'X', 8: 'C', 9: 'V',
  11: 'B', 12: 'Q', 13: 'W', 14: 'E', 15: 'R', 16: 'Y', 17: 'T', 18: '1', 19: '2',
  20: '3', 21: '4', 22: '6', 23: '5', 24: '=', 25: '9', 26: '7', 27: '−', 28: '8',
  10: '§', 29: '0', 30: ']', 31: 'O', 32: 'U', 33: '[', 34: 'I', 35: 'P', 36: '⏎', 37: 'L',
  38: 'J', 39: "'", 40: 'K', 41: ';', 42: '\\', 43: ',', 44: '/', 45: 'N', 46: 'M',
  47: '.', 48: '⇥', 49: 'Пробел', 50: '`', 51: '⌫', 53: 'Esc', 64: 'F17', 65: '.',
  67: '*', 69: '+', 71: '⌧', 75: '/', 76: '⌤', 78: '−', 79: 'F18', 80: 'F19',
  81: '=', 82: '0', 83: '1', 84: '2', 85: '3', 86: '4', 87: '5', 88: '6', 89: '7',
  90: 'F20', 91: '8', 92: '9', 96: 'F5', 97: 'F6', 98: 'F7', 99: 'F3', 100: 'F8',
  101: 'F9', 103: 'F11', 105: 'F13', 106: 'F16', 107: 'F14', 109: 'F10',
  111: 'F12', 113: 'F15', 114: 'Help', 115: '↖', 116: '⇞', 117: '⌦', 118: 'F4',
  119: '↘', 120: 'F2', 121: '⇟', 122: 'F1', 123: '←', 124: '→', 125: '↓', 126: '↑',
};

String keyName(int keyCode) {
  final String? name = _keyNames[keyCode];
  if (name != null) return name;
  if (keyCode >= 123 && keyCode <= 126) return '?';
  return 'Key $keyCode';
}

class AppSettings {
  const AppSettings({
    this.hotkey = HotkeySpec.fallback,
    this.autoPaste = true,
    this.launchAtLogin = false,
    this.maxItems = 500,
    this.glassStyle = 'auto',
    this.appearance = 'system',
    this.accessibility = false,
    this.accent = 0x0A84FF,
    this.dark = false,
    this.version = '0.1.0',
  });

  final HotkeySpec hotkey;
  final bool autoPaste;
  final bool launchAtLogin;
  final int maxItems;
  final String glassStyle;

  /// "system", "light" or "dark".
  final String appearance;
  final bool accessibility;
  final int accent;
  final bool dark;
  final String version;

  static AppSettings fromMap(Map<Object?, Object?> map) {
    final Object? hotkey = map['hotkey'];
    return AppSettings(
      hotkey: hotkey is Map<Object?, Object?>
          ? HotkeySpec.fromMap(hotkey)
          : HotkeySpec.fallback,
      autoPaste: map['autoPaste'] != false,
      launchAtLogin: map['launchAtLogin'] == true,
      maxItems: (map['maxItems'] as num?)?.toInt() ?? 500,
      glassStyle: '${map['glassStyle'] ?? 'auto'}',
      appearance: '${map['appearance'] ?? 'system'}',
      accessibility: map['accessibility'] == true,
      accent: (map['accent'] as num?)?.toInt() ?? 0x0A84FF,
      dark: map['dark'] == true,
      version: '${map['version'] ?? '0.1.0'}',
    );
  }
}
