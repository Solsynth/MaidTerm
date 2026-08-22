import 'package:maidterm/src/rendering/atlas/sprite_buffer.dart';
import 'package:test/test.dart';

void main() {
  test('colorForWidth returns an unsigned ARGB color', () {
    final sprites = RectSprites()..configure(1, 1);
    addTearDown(sprites.dispose);

    sprites.beginRow(0);
    sprites.add(0, 0, 100, 20, 0xFF232436);
    sprites.endRow();

    expect(sprites.colorForWidth(100), 0xFF232436);
  });
}
