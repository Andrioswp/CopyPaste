/// Geometry helper for pointer-driven selection in the history list.
///
/// Rows have fixed heights, so the entry under the cursor can be computed
/// directly from the pointer position. The earlier implementation relied on
/// per-row `MouseRegion.onEnter` events, and a fast mouse sweep skipped rows
/// between frames — the blue highlight jumped over entries as a result.
library;

/// Returns the selection index of the entry under [localY], or `null` when the
/// pointer is over a section label or outside the content.
///
/// [entryHeights] and [entryIndices] describe the entries in visual order;
/// `entryIndices[i]` is the keyboard-selection index of that entry (`null` for
/// labels). [scrollOffset] is the current scroll position of the list.
int? selectionIndexAt({
  required List<double> entryHeights,
  required List<int?> entryIndices,
  required double localY,
  required double scrollOffset,
}) {
  assert(entryHeights.length == entryIndices.length);
  final double y = localY + scrollOffset;
  if (y < 0) return null;
  double cursor = 0;
  for (int i = 0; i < entryHeights.length; i++) {
    final double next = cursor + entryHeights[i];
    if (y >= cursor && y < next) return entryIndices[i];
    cursor = next;
  }
  return null;
}
