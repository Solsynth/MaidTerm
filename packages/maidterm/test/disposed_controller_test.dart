import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show KeyEventResult;
import 'package:maidterm/src/foundation/terminal_config.dart';
import 'package:maidterm/src/widgets/terminal_controller_impl.dart';
import 'package:test/test.dart';
void main() {
  // Regression test: a key event delivered after the controller was disposed
  // (e.g. the key-up of a close-tab shortcut racing the pane removal) used to
  // reach the freed native KeyEncoder/Terminal handles and segfault.
  group('disposed controller', () {
    test('handleKeyEvent is ignored after dispose', () {
      final c = TerminalControllerImpl(
        config: const TerminalConfig(cols: 80, rows: 24),
      );
      c.dispose();

      final result = c.handleKeyEvent(
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.keyA,
          logicalKey: LogicalKeyboardKey.keyA,
          character: 'a',
          timeStamp: Duration.zero,
        ),
      );
      expect(result, KeyEventResult.ignored);
    });

    test('mouse and scroll events are no-ops after dispose', () {
      final c = TerminalControllerImpl(
        config: const TerminalConfig(cols: 80, rows: 24),
      );
      c.dispose();

      expect(
        () => c.handleScroll(3),
        returnsNormally,
      );
    });
  });
}
