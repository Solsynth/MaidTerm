import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/painting.dart' show FontWeight;
import 'package:libghostty/libghostty.dart' as vt;
import 'package:libghostty/libghostty.dart' show CellWidth, Style;
import 'package:maidterm/src/foundation/cell_metrics.dart';
import 'package:maidterm/src/rendering/atlas/atlas.dart';
import 'package:maidterm/src/rendering/cell_content_resolver.dart';
import 'package:test/test.dart';

/// Span rule mirrored from the renderer's `_cellSpan`:
///
/// VS16-promoted emoji (e.g. `ℹ️`, `❤️`) default to text presentation, so
/// libghostty stores the grapheme cluster (length 2, content includes
/// U+FE0F) but reports the cell `.narrow` with no spacer tail. They are
/// genuinely two columns wide, so the renderer must reserve both columns.
int renderSpan(CellWidth wide, int graphemeLength, String content) {
  if (wide == CellWidth.wide) return 2;
  if (wide == CellWidth.narrow &&
      graphemeLength > 1 &&
      content.contains('\uFE0F')) {
    return 2;
  }
  return 1;
}

void main() {
  test('VS16 emoji is reported narrow but classified two columns wide', () {
    final terminal = vt.Terminal(cols: 16, rows: 1);
    addTearDown(terminal.dispose);

    terminal.write(Uint8List.fromList(utf8.encode('\u2139\uFE0F Nuxt')));

    final renderState = vt.RenderState();
    addTearDown(renderState.dispose);
    renderState.update(terminal);

    final rows = vt.RowIterator();
    final cells = vt.CellIterator();
    rows.reset(renderState);
    String? info;
    while (rows.next()) {
      cells.reset(rows);
      while (cells.next()) {
        if (cells.codepoint == 0x2139) {
          info = cells.content;
          expect(cells.graphemeLength, greaterThan(1));
          expect(cells.content.contains('\uFE0F'), isTrue);
          // Upstream bug: the engine under-reports the width.
          expect(cells.wide, CellWidth.narrow);
          // Renderer must compensate to reserve both columns.
          expect(
            renderSpan(cells.wide, cells.graphemeLength, cells.content),
            2,
          );
        }
      }
    }
    expect(info, isNotNull);
  });

  test('info emoji rasterizes a two-cell emoji atlas entry at span 2', () {
    final metrics = const CellMetrics(
      cellWidth: 8,
      cellHeight: 17,
      baseline: 13,
    );
    final config = AtlasConfig(
      fontSize: 12,
      fontFamily: 'IBM Plex Mono',
      fontWeight: FontWeight.w400,
      fontFamilyFallback: const [],
      metrics: metrics,
      devicePixelRatio: 1,
    );
    final atlas = Atlas(config);
    addTearDown(atlas.dispose);

    final entry = CellContentResolver(atlas).resolve(
      content: '\u2139\uFE0F',
      codepoint: 0x2139,
      graphemeLength: 2,
      style: const Style(),
      span: 2,
    );

    expect(entry, isNotNull);
    expect(entry!.lane, AtlasEntryLane.emoji);
    // Two cells at 8px logical width, dpr 1 -> 16px physical.
    expect(entry.srcRight - entry.srcLeft, closeTo(16, 0.5));
  });
}
