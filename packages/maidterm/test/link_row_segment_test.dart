import 'package:libghostty/libghostty.dart' show Position;
import 'package:maidterm/src/foundation/cell_range.dart';
import 'package:maidterm/src/rendering/terminal_frame_builder.dart';
import 'package:test/test.dart';

void main() {
  group('LinkRowSegment for wrapped links', () {
    // A range that soft-wraps across rows 2-4 of an 80-col grid.
    final range = CellRange(
      start: const Position(row: 2, col: 76),
      end: const Position(row: 4, col: 12),
    );

    test('first row runs from the start column to the grid end', () {
      final segment = LinkRowSegment.resolve(range, 2, cols: 80);
      expect(segment.startCol, 76);
      expect(segment.endCol, 79);
    });

    test('middle rows span the full grid width', () {
      final segment = LinkRowSegment.resolve(range, 3, cols: 80);
      expect(segment.startCol, 0);
      expect(segment.endCol, 79);
    });

    test('last row runs from the grid start to the end column', () {
      final segment = LinkRowSegment.resolve(range, 4, cols: 80);
      expect(segment.startCol, 0);
      expect(segment.endCol, 12);
    });

    test('single-row range keeps its own columns on every row', () {
      final single = CellRange(
        start: const Position(row: 1, col: 5),
        end: const Position(row: 1, col: 9),
      );
      final segment = LinkRowSegment.resolve(single, 1, cols: 80);
      expect(segment.startCol, 5);
      expect(segment.endCol, 9);
    });

    test('rows outside the range are rejected', () {
      expect(
        () => LinkRowSegment.resolve(range, 1, cols: 80),
        throwsStateError,
      );
    });
  });
}
