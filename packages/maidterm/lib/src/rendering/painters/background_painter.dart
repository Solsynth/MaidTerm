import 'dart:ui';
import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter/foundation.dart';

import '../atlas/sprite_buffer.dart';
import '../paint_state.dart';
import 'terminal_painter.dart';

/// Paints the terminal default background, then explicit cell backgrounds.
///
/// Explicit cell backgrounds are limited to the cells that specify them. A
/// full-width run is not a terminal-wide fill: ordinary applications can emit
/// one while using the alternate screen, and promoting it would briefly tint
/// unrelated rows and the padding during screen transitions.
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
    if (_lastLoggedArgb != terminalBackgroundArgb) {
      _lastLoggedArgb = terminalBackgroundArgb;
      final terminalHex = terminalBackgroundArgb
          .toRadixString(16)
          .padLeft(8, '0');
      debugPrint('[MaidTerm] terminal background: #$terminalHex');
    }
    if (_state.theme.backgroundOpacity >= 1.0) {
      _fillPaint.color = Color(terminalBackgroundArgb);
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
