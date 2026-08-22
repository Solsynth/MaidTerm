import 'dart:typed_data';
import 'dart:ui';

import 'package:maidterm/src/foundation/cell_metrics.dart';
import 'package:maidterm/src/foundation/terminal_theme.dart';
import 'package:maidterm/src/rendering/atlas/sprite_buffer.dart';
import 'package:maidterm/src/rendering/painters/background_painter.dart';
import 'package:maidterm/src/rendering/paint_state.dart';
import 'package:test/test.dart';

void main() {
  test('uses a full-width cell fill for the terminal canvas', () async {
    final state = TerminalPaintState(
      TerminalTheme.light(),
      const CellMetrics(cellWidth: 10, cellHeight: 10, baseline: 8),
    )
      ..cols = 2
      ..rows = 1;
    final sprites = SpriteBuffer()..configure(1, 2);
    addTearDown(sprites.dispose);

    sprites.beginRow(0);
    sprites.background.add(0, 0, 20, 10, 0xFF232436);
    sprites.endRow();
    sprites.seal();

    final painter = BackgroundPainter(state, sprites)..viewportSize = const Size(30, 10);
    final recorder = PictureRecorder();
    painter.paint(Canvas(recorder));
    final image = await recorder.endRecording().toImage(30, 10);
    addTearDown(image.dispose);
    final bytes = (await image.toByteData(format: ImageByteFormat.rawRgba))!.buffer;
    final rgba = Uint8List.view(bytes);

    expect(rgba.sublist(0, 4), [0x23, 0x24, 0x36, 0xFF]);
    final outsideGrid = (25 * 4);
    expect(rgba.sublist(outsideGrid, outsideGrid + 4), [
      0x23,
      0x24,
      0x36,
      0xFF,
    ]);
  });
}
