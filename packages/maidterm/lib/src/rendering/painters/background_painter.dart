import 'dart:ui';
import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter/foundation.dart';

import '../atlas/sprite_buffer.dart';
import '../paint_state.dart';
import 'terminal_painter.dart';

/// Paints the terminal background layer.
///
/// At full opacity, fills the grid with the first explicit full-width cell
/// background when present, falling back to the terminal background, then
/// draws per-cell explicit background rects on top via a batched
/// [Canvas.drawVertices] call.
///
/// When [TerminalPaintState.backgroundOpacity] is less than 1.0, skips
/// the grid fill so the backdrop behind the repaint boundary layer
/// shows through on default background cells; filling here would
/// composite twice against that backdrop. Per-cell explicit background
/// rects still render on top, with alpha scaled by the frame builder when
/// [TerminalPaintState.backgroundOpacityCells] is true.
class BackgroundPainter implements TerminalPainter {
  final Paint _fillPaint;
  final Paint _vertexPaint;
  final SpriteBuffer _sprites;
  Size _viewportSize = Size.zero;
  final TerminalPaintState _state;
  int? _lastLoggedArgb;

  BackgroundPainter(this._state, this._sprites)
    : _fillPaint = Paint(),
      _vertexPaint = Paint();

  set viewportSize(Size value) => _viewportSize = value;

  @override
  void paint(Canvas canvas) {
    final terminalBackgroundArgb = _state.terminalBackgroundArgb & 0xFFFFFFFF;
    final gridWidth = _state.cols * _state.metrics.cellWidth;
    final gridHeight = _state.rows * _state.metrics.cellHeight;
    final cellBackgroundArgb =
        _sprites.background.colorForWidth(gridWidth) ?? terminalBackgroundArgb;
    if (_lastLoggedArgb != cellBackgroundArgb) {
      _lastLoggedArgb = cellBackgroundArgb;
      final terminalHex = terminalBackgroundArgb
          .toRadixString(16)
          .padLeft(8, '0');
      final fillHex = (cellBackgroundArgb & 0xFFFFFFFF)
          .toRadixString(16)
          .padLeft(8, '0');
      debugPrint(
        '[MaidTerm] terminal background: #$terminalHex '
        '(cell fill: #$fillHex)',
      );
    }
    if (_state.theme.backgroundOpacity >= 1.0) {
      _fillPaint.color = Color(cellBackgroundArgb);
      canvas.drawRect(
        Rect.fromLTWH(
          0,
          0,
          math.max(_viewportSize.width, gridWidth),
          math.max(_viewportSize.height, gridHeight),
        ),
        _fillPaint,
      );
    }

    final vertices = _sprites.backgroundVertices;
    if (vertices == null) return;
    canvas.drawVertices(vertices, BlendMode.srcOver, _vertexPaint);
  }
}
