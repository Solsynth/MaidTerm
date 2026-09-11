import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:libghostty/libghostty.dart' as vt;
import 'package:maidterm/src/foundation/cell_metrics.dart';
import 'package:maidterm/src/foundation/terminal_theme.dart';
import 'package:maidterm/src/rendering/atlas/atlas.dart';
import 'package:maidterm/src/rendering/atlas/sprite_buffer.dart';
import 'package:maidterm/src/rendering/paint_state.dart';
import 'package:maidterm/src/rendering/painters/shaped_run_painter.dart';
import 'package:maidterm/src/rendering/terminal_frame_builder.dart';

/// The operator-run fast path paints a whole punctuation run as one shaped
/// paragraph. The paragraph must be laid out so the run occupies exactly the
/// cells it came from: otherwise the glyphs drift off the cell grid and the
/// cursor (positioned from the grid) detaches from the end of the run.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const cellWidth = 18.0;
  const cellHeight = 20.0;
  const cols = 40;

  Future<double> lastInkX(String text) async {
    final metrics = const CellMetrics(
      cellWidth: cellWidth,
      cellHeight: cellHeight,
      baseline: 15,
    );
    final theme = TerminalTheme.dark();
    final config = AtlasConfig(
      fontSize: 14,
      fontFamily: theme.fontFamily,
      fontWeight: theme.fontWeight,
      fontFamilyFallback: theme.fontFamilyFallback,
      metrics: metrics,
      devicePixelRatio: 1,
    );
    final atlas = Atlas(config);
    final sprites = SpriteBuffer();
    final state = TerminalPaintState(theme, metrics);
    final builder = TerminalFrameBuilder(atlas, sprites, state);

    state.rows = 1;
    state.cols = cols;
    state.devicePixelRatio = 1;
    builder.configure(1, cols);

    final terminal = vt.Terminal(cols: cols, rows: 1);
    terminal.write(Uint8List.fromList(utf8.encode(text)));
    builder.sync(terminal, terminalDirty: true);

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    ShapedRunPainter(sprites.shaped).paint(canvas);
    final image = await recorder.endRecording().toImage(
      (cols * cellWidth).ceil(),
      cellHeight.ceil(),
    );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();

    var last = -1.0;
    for (var x = 0; x < (cols * cellWidth).ceil(); x++) {
      for (var y = 0; y < cellHeight.ceil(); y++) {
        if (bytes!.getUint8((y * (cols * cellWidth).ceil() + x) * 4 + 3) > 0) {
          last = x.toDouble();
          break;
        }
      }
    }
    return last;
  }

  test('operator run paints glyphs across exactly its own cells', () async {
    const typed = 20;
    const text = '********************';

    final last = await lastInkX(text);

    // Every asterisk owns one cell, so the last painted pixel must land in
    // the final cell of the run (one pixel of tolerance for rasterization).
    expect(
      last,
      greaterThanOrEqualTo(typed * cellWidth - 2),
      reason:
          'shaped run ink ends at $last, expected '
          '${typed * cellWidth - 2}..${typed * cellWidth}',
    );
    expect(last, lessThanOrEqualTo(typed * cellWidth));
  });
}
