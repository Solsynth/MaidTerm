import 'dart:ui';

import '../atlas/sprite_buffer.dart';
import 'terminal_painter.dart';

/// Paints paragraph-shaped text runs that need ligature shaping.
final class ShapedRunPainter implements TerminalPainter {
  final ShapedRunBuffer _runs;

  ShapedRunPainter(this._runs);

  @override
  void paint(Canvas canvas) {
    if (_runs.count == 0) return;

    for (final row in _runs.rows) {
      for (final run in row) {
        canvas.save();
        canvas.clipRect(run.clip);
        if (run.widthScale == 1.0) {
          canvas.drawParagraph(run.paragraph, run.offset);
        } else {
          canvas.translate(run.offset.dx, run.offset.dy);
          canvas.scale(run.widthScale, 1.0);
          canvas.drawParagraph(run.paragraph, Offset.zero);
        }
        canvas.restore();
      }
    }
  }
}
