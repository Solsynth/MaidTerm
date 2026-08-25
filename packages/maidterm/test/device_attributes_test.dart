import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:maidterm/src/widgets/terminal_controller_impl.dart';
import 'package:test/test.dart';

void main() {
  test('DA1 advertises sixel (feature 4)', () async {
    final controller = TerminalControllerImpl();
    final responses = <String>[];
    controller.onOutput = (Uint8List bytes) {
      responses.add(utf8.decode(bytes, allowMalformed: true));
    };
    controller.write(Uint8List.fromList('\x1b[0c'.codeUnits));
    await Future<void>.delayed(Duration.zero);
    expect(responses.join(), '\x1b[?62;4c');
  });
}
