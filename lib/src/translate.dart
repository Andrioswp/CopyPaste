import 'dart:convert';
import 'dart:io';

/// In-app Google Translate via the public `translate_a/single` endpoint
/// (same one used by the web widget — no API key).
Future<String> translateWithGoogle(
  String text, {
  String source = 'auto',
  String target = 'ru',
}) async {
  final String trimmed = text.trim();
  if (trimmed.isEmpty) return '';

  // GET query strings get unwieldy; split long pasteboard blobs into chunks.
  const int maxChunk = 1200;
  if (trimmed.length <= maxChunk) {
    return _translateChunk(trimmed, source: source, target: target);
  }

  final StringBuffer out = StringBuffer();
  int start = 0;
  while (start < trimmed.length) {
    int end = (start + maxChunk).clamp(0, trimmed.length);
    if (end < trimmed.length) {
      final int breakAt = trimmed.lastIndexOf(RegExp(r'[\s\n.]'), end);
      if (breakAt > start + 200) end = breakAt + 1;
    }
    final String piece = trimmed.substring(start, end).trim();
    if (piece.isNotEmpty) {
      if (out.isNotEmpty) out.write('\n');
      out.write(await _translateChunk(piece, source: source, target: target));
    }
    start = end;
  }
  return out.toString();
}

Future<String> _translateChunk(
  String text, {
  required String source,
  required String target,
}) async {
  final Uri uri = Uri.https(
    'translate.googleapis.com',
    '/translate_a/single',
    <String, String>{
      'client': 'gtx',
      'sl': source,
      'tl': target,
      'dt': 't',
      'q': text,
    },
  );

  final HttpClient client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 8)
    ..idleTimeout = const Duration(seconds: 8);
  try {
    final HttpClientRequest request = await client.getUrl(uri);
    request.headers.set(HttpHeaders.userAgentHeader, 'CopyPaste/0.1');
    final HttpClientResponse response =
        await request.close().timeout(const Duration(seconds: 12));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('HTTP ${response.statusCode}', uri: uri);
    }
    final String body =
        await response.transform(utf8.decoder).join().timeout(const Duration(seconds: 12));
    return _parseGtxResponse(body);
  } finally {
    client.close(force: true);
  }
}

/// Response shape: `[[["translated","original",…], …], …]`
String _parseGtxResponse(String body) {
  final Object? decoded = jsonDecode(body);
  if (decoded is! List || decoded.isEmpty) {
    throw const FormatException('Unexpected Google Translate payload');
  }
  final Object? sentences = decoded.first;
  if (sentences is! List) {
    throw const FormatException('Unexpected Google Translate sentences');
  }
  final StringBuffer buffer = StringBuffer();
  for (final Object? part in sentences) {
    if (part is List && part.isNotEmpty && part.first is String) {
      buffer.write(part.first as String);
    }
  }
  final String result = buffer.toString().trim();
  if (result.isEmpty) {
    throw const FormatException('Empty translation');
  }
  return result;
}
