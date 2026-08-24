import 'dart:convert';
import 'dart:typed_data';

import 'package:maidterm/src/foundation/terminal_config.dart';
import 'package:maidterm/src/widgets/terminal_controller_impl.dart';
import 'package:test/test.dart';

void main() {
  group('paste newline handling', () {
    TerminalControllerImpl controller() {
      final c = TerminalControllerImpl(
        config: const TerminalConfig(cols: 120, rows: 40),
      );
      addTearDown(c.dispose);
      return c;
    }

    test('unbracketed CRLF paste emits one CR per line', () {
      final c = controller();
      final outputs = <Uint8List>[];
      c.onOutput = outputs.add;

      // Windows clipboard: CRLF line endings.
      c.paste('line1\r\nline2\r\nline3');

      final text = utf8.decode(outputs.single, allowMalformed: true);
      // Unbracketed: LF is replaced by CR; CRLF must not become CRCR.
      expect(text, 'line1\rline2\rline3');
      expect(text, isNot(contains('\r\r')));
    });

    test('bracketed CRLF paste emits clean LF inside fenceposts', () {
      final c = controller();
      final outputs = <Uint8List>[];
      c.onOutput = outputs.add;

      // vim/nano enable bracketed paste mode 2004.
      c.write(Uint8List.fromList('\x1b[?2004h'.codeUnits));
      c.paste('line1\r\nline2');

      final text = utf8.decode(outputs.single, allowMalformed: true);
      // Bracketed: text passes through, but CRLF must be LF so vim sees one
      // line break per line instead of CR + LF.
      expect(text, '\x1b[200~line1\nline2\x1b[201~');
      expect(text, isNot(contains('\r')));
    });

    test('lone CR paste normalizes to LF', () {
      final c = controller();
      final outputs = <Uint8List>[];
      c.onOutput = outputs.add;

      c.paste('a\rb');

      final text = utf8.decode(outputs.single, allowMalformed: true);
      expect(text, 'a\rb');
    });

    test('LF-only paste is untouched', () {
      final c = controller();
      final outputs = <Uint8List>[];
      c.onOutput = outputs.add;

      c.paste('a\nb');

      final text = utf8.decode(outputs.single, allowMalformed: true);
      expect(text, 'a\rb');
    });
  });
}
