import 'package:maidterm/src/rendering/atlas/sprite_buffer.dart';
import 'package:test/test.dart';

void main() {
  test('dominantCoverage reports a full-grid fill', () {
    final sprites = RectSprites()..configure(1, 1);
    addTearDown(sprites.dispose);

    sprites.beginRow(0);
    sprites.add(0, 0, 100, 20, 0xFF232436);
    sprites.endRow();

    expect(sprites.dominantCoverage(100, 20), closeTo(1.0, 0.0001));
  });

  test('dominantCoverage ignores rects outside the grid', () {
    final sprites = RectSprites()..configure(2, 2);
    addTearDown(sprites.dispose);

    // One full row inside the grid, one fully outside it.
    sprites.beginRow(0);
    sprites.add(0, 0, 100, 10, 0xFF232436);
    sprites.endRow();
    sprites.beginRow(1);
    sprites.add(0, 100, 100, 120, 0xFF654321);
    sprites.endRow();

    expect(sprites.dominantCoverage(100, 20), closeTo(0.5, 0.0001));
  });
}
