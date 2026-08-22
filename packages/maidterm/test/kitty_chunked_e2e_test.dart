import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:maidterm/src/widgets/vt_graphics_rewriter.dart';
import 'package:maidterm/maidterm.dart' show TerminalController;
import 'package:test/test.dart';

void main() {
  test('chunked blackcat-style transmit completes with OK', () async {
    final controller = TerminalController();
    var nextId = 0;
    final rewriter = VtGraphicsRewriter(nextImageId: () => 0x40000000 + nextId++);
    final responses = <String>[];
    controller.onOutput = (Uint8List bytes) {
      responses.add(utf8.decode(bytes, allowMalformed: true));
    };

    // 2x2 RGBA pixel, zlib-compressed like blackcat sends (f=32,o=z).
    const b64 = 'eJxzUBD474CEASx0Bb0=';
    void feed(String s) => controller.write(rewriter.feed(Uint8List.fromList(s.codeUnits)));

    feed('\x1b_Gf=32,o=z,s=2,v=2,a=T,m=1;$b64\x1b\\');
    feed('\x1b_Gm=1;QUFBQQ==\x1b\\');
    feed('\x1b_Gm=0;\x1b\\');
    // Drain pending responses.
    for (var i = 0; i < 10; i++) {
      feed('');
    }
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    final all = responses.join();
    expect(all, contains('OK'));
    expect(all, isNot(contains('EINVAL')));
  });
}
