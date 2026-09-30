import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:maidterm_app/windows/tab_strip_geometry.dart';

void main() {
  /// Three 100px chips laid out along [axis].
  Rect Function(String) chips(Axis axis) {
    final index = {'a': 0, 'b': 1, 'c': 2};
    return (tabId) {
      final offset = index[tabId]! * 100.0;
      return axis == Axis.horizontal
          ? Rect.fromLTWH(offset, 0, 100, 40)
          : Rect.fromLTWH(0, offset, 40, 100);
    };
  }

  int indexAt(Offset cursor, {required Axis axis, required String dragging}) =>
      tabInsertionIndex(
        cursor: cursor,
        axis: axis,
        orderedTabIds: const ['a', 'b', 'c'],
        draggedTabId: dragging,
        rectOf: chips(axis),
      );

  test('a horizontal strip inserts where the cursor passed the tab centers', () {
    expect(indexAt(const Offset(10, 20), axis: Axis.horizontal, dragging: 'c'), 0);
    // Past a's center (50) but not b's (150).
    expect(indexAt(const Offset(60, 20), axis: Axis.horizontal, dragging: 'c'), 1);
    // Exactly on b's center: the cursor has not passed it yet.
    expect(indexAt(const Offset(150, 20), axis: Axis.horizontal, dragging: 'c'), 1);
    expect(indexAt(const Offset(151, 20), axis: Axis.horizontal, dragging: 'c'), 2);
    expect(indexAt(const Offset(400, 20), axis: Axis.horizontal, dragging: 'c'), 2);
  });

  test('a vertical strip measures along the vertical axis', () {
    expect(indexAt(const Offset(20, 10), axis: Axis.vertical, dragging: 'c'), 0);
    expect(indexAt(const Offset(20, 160), axis: Axis.vertical, dragging: 'c'), 2);
  });

  test('the dragged tab does not count towards its own index', () {
    // With 'a' lifted, the cursor past b leaves index 1: it lands after b.
    expect(indexAt(const Offset(60, 20), axis: Axis.horizontal, dragging: 'a'), 0);
    expect(indexAt(const Offset(160, 20), axis: Axis.horizontal, dragging: 'a'), 1);
    expect(indexAt(const Offset(260, 20), axis: Axis.horizontal, dragging: 'a'), 2);
  });

  test('tabs without a box are skipped instead of guessed at', () {
    final index = tabInsertionIndex(
      cursor: const Offset(250, 20),
      axis: Axis.horizontal,
      orderedTabIds: const ['a', 'b', 'c'],
      draggedTabId: 'c',
      rectOf: (tabId) {
        if (tabId == 'b') return null;
        return Rect.fromLTWH(tabId == 'a' ? 0 : 200, 0, 100, 40);
      },
    );

    // Only a crossed its center; the unlaid-out b cannot be counted.
    expect(index, 1);
  });

  test('a tab missing from the strip still counts the ones it passed', () {
    final index = tabInsertionIndex(
      cursor: const Offset(250, 20),
      axis: Axis.horizontal,
      orderedTabIds: const ['a', 'b', 'c'],
      draggedTabId: 'gone',
      rectOf: chips(Axis.horizontal),
    );

    // Every laid-out tab's center was passed, the dragged one is not in the
    // strip at all.
    expect(index, 2);
  });
}
