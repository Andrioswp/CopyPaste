import 'package:copypaste/src/entry_hit.dart';
import 'package:flutter_test/flutter_test.dart';

/// Heights used by the panel: 26 for a section label, 54 for an entry.
const double label = 26;
const double row = 54;

List<double> _heights() => <double>[
      label,
      row, row, row,
      label,
      row, row, row, row, row,
    ];

List<int?> _indices() => <int?>[
      null,
      0, 1, 2,
      null,
      3, 4, 5, 6, 7,
    ];

void main() {
  test('maps the pointer to the row under it', () {
    final List<double> heights = _heights();
    final List<int?> indices = _indices();

    int? at(double y, {double scroll = 0}) => selectionIndexAt(
          entryHeights: heights,
          entryIndices: indices,
          localY: y,
          scrollOffset: scroll,
        );

    expect(at(0), isNull, reason: 'первая строка — заголовок раздела');
    expect(at(25.9), isNull);
    expect(at(26), 0);
    expect(at(79.9), 0);
    expect(at(80), 1);
    expect(at(26 + 54 * 3 - 1), 2);
    expect(at(26 + 54 * 3), isNull, reason: 'второй заголовок');
    expect(at(26 + 54 * 3 + 26 - 1), isNull, reason: 'второй заголовок');
    expect(at(26 + 54 * 3 + 26), 3);
  });

  test('honours the scroll offset', () {
    final List<double> heights = _heights();
    final List<int?> indices = _indices();
    expect(
      selectionIndexAt(
        entryHeights: heights,
        entryIndices: indices,
        localY: 0,
        scrollOffset: label,
      ),
      0,
      reason: 'при прокрутке на высоту заголовка под курсором первая запись',
    );
    expect(
      selectionIndexAt(
        entryHeights: heights,
        entryIndices: indices,
        localY: 0,
        scrollOffset: -10,
      ),
      isNull,
      reason: 'выше начала списка выбора нет',
    );
  });

  test('a fast sweep never skips an entry', () {
    final List<double> heights = _heights();
    final List<int?> indices = _indices();
    final double total = heights.fold<double>(0, (double a, double b) => a + b);

    final List<int> visited = <int>[];
    // Steps of 7 px emulate a fast mouse movement: fewer events than rows.
    for (double y = 0; y < total; y += 7) {
      final int? index = selectionIndexAt(
        entryHeights: heights,
        entryIndices: indices,
        localY: y,
        scrollOffset: 0,
      );
      if (index != null && (visited.isEmpty || visited.last != index)) {
        visited.add(index);
      }
    }

    expect(visited, <int>[0, 1, 2, 3, 4, 5, 6, 7],
        reason: 'порядок должен быть строго последовательным, без перескоков');
  });
}
