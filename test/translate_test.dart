import 'package:copypaste/src/translate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('translates a short English phrase to Russian', () async {
    final String result = await translateWithGoogle('Hello world', target: 'ru');
    expect(result.toLowerCase(), contains('привет'));
  }, timeout: const Timeout(Duration(seconds: 20)));
}
