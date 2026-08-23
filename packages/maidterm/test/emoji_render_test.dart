import 'dart:convert';
import 'dart:typed_data';

import 'package:libghostty/libghostty.dart' as vt;
import 'package:maidterm/src/foundation/cell_metrics.dart';
import 'package:maidterm/src/foundation/terminal_theme.dart';
import 'package:maidterm/src/rendering/atlas/atlas.dart';
import 'package:maidterm/src/rendering/atlas/sprite_buffer.dart';
import 'package:maidterm/src/rendering/paint_state.dart';
import 'package:maidterm/src/rendering/terminal_frame_builder.dart';
import 'package:test/test.dart';

/// Renders a row through the real [TerminalFrameBuilder] and inspects the
/// emitted sprites. Returns the emoji sprite rects/positions and the x
/// positions of narrow text sprites.
({
  List<List<double>> emoji,
  List<double> textX,
}) renderRow(String text) {
  const cellWidth = 8.0;
  const cellHeight = 17.0;
  final metrics = const CellMetrics(
    cellWidth: cellWidth,
    cellHeight: cellHeight,
    baseline: 13,
  );
  final theme = TerminalTheme.dark();
  final config = AtlasConfig(
    fontSize: 12,
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
  state.cols = 24;
  state.devicePixelRatio = 1;
  builder.configure(1, 24);

  final terminal = vt.Terminal(cols: 24, rows: 1);
  terminal.write(Uint8List.fromList(utf8.encode(text)));
  builder.sync(terminal, terminalDirty: true);

  final emoji = sprites.emoji;
  final rects = emoji.sealedRects;
  final transforms = emoji.sealedTransforms;
  final emojiSprites = <List<double>>[];
  for (var i = 0; i < emoji.count; i++) {
    emojiSprites.add([
      transforms[i * 4 + 2],
      (rects[i * 4 + 2] - rects[i * 4]).roundToDouble(),
    ]);
  }

  final textSprites = sprites.regular;
  final textTransforms = textSprites.sealedTransforms;
  final textX = <double>[];
  for (var i = 0; i < textSprites.count; i++) {
    textX.add(textTransforms[i * 4 + 2]);
  }

  builder.dispose();
  terminal.dispose();
  atlas.dispose();
  return (emoji: emojiSprites, textX: textX);
}

void main() {
  test('info emoji renders two cells wide and does not shift the row', () {
    final row = renderRow('\u2139\uFE0F X');
    // The emoji is one sprite, two cells wide (2 * 8px = 16px), placed at
    // column 0.
    expect(row.emoji, [[0, 16]]);
    // The space is empty and the following 'X' lands two cells after the
    // emoji plus one cell for the space: 3 * 8px = 24px. Before the fix the
    // emoji reserved one cell, so 'X' was placed at 16px and overlapped.
    expect(row.textX, [24]);
  });
}
