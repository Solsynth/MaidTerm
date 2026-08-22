import 'dart:convert';
import 'dart:typed_data';

import 'package:maidterm/src/widgets/vt_graphics_rewriter.dart';
import 'package:test/test.dart';

void main() {
  var nextId = 0;
  VtGraphicsRewriter rewriter() {
    nextId = 0;
    return VtGraphicsRewriter(nextImageId: () => 0x40000000 + nextId++);
  }

  Uint8List out(VtGraphicsRewriter r, String input) =>
      r.feed(Uint8List.fromList(input.codeUnits));

  String asString(Uint8List b) => utf8.decode(b, allowMalformed: true);

  group('VtGraphicsRewriter', () {
    test('injects an image id into implicit-id kitty transmits', () {
      const png =
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';
      final r = rewriter();
      final result = asString(out(r, '\x1b_Ga=T,f=100,s=1,v=1,t=d;$png\x1b\\'));
      expect(result, '\x1b_Gi=1073741824,a=T,f=100,s=1,v=1,t=d;$png\x1b\\');
    });

    test('injects before a control-less transmit payload', () {
      final r = rewriter();
      final result = asString(out(r, '\x1b_G;QUFBQQ==\x1b\\'));
      expect(result, '\x1b_Gi=1073741824,;QUFBQQ==\x1b\\');
    });

    test('leaves explicit-id transmits untouched', () {
      final r = rewriter();
      const seq = '\x1b_Ga=t,t=d,f=100,i=7,s=1,v=1;QUFBQQ==\x1b\\';
      expect(asString(out(r, seq)), seq);
    });

    test('leaves image-number transmits untouched', () {
      final r = rewriter();
      const seq = '\x1b_Ga=t,t=d,f=100,I=3,s=1,v=1;QUFBQQ==\x1b\\';
      expect(asString(out(r, seq)), seq);
    });

    test('leaves continuation chunks (m=1) untouched', () {
      final r = rewriter();
      const seq = '\x1b_Gm=1;QUFBQQ==\x1b\\';
      expect(asString(out(r, seq)), seq);
    });

    test('leaves kitty queries untouched', () {
      final r = rewriter();
      const seq = '\x1b_Gi=31,s=1,v=1,a=q,t=d,f=24;AAAA\x1b\\';
      expect(asString(out(r, seq)), seq);
    });

    test('converts sixel DCS into kitty transmit + display', () {
      final r = rewriter();
      final result = asString(out(r, '\x1bPq#0;2;0;0;0~-~\x1b\\'));
      // Transmit of the decoded 1x12 RGBA plus display of the image.
      expect(result, startsWith('\x1b_Ga=t,f=32,t=d,i=1073741824,s=1,v=12;'));
      expect(result, endsWith('\x1b\\\x1b_Ga=p,i=1073741824\x1b\\'));
      // The RGBA payload is 1*12*4 = 48 bytes.
      final b64 = result.substring(result.indexOf(';') + 1, result.indexOf('\x1b\\'));
      expect(base64.decode(b64).length, 48);
    });

    test('handles sixel DCS with params before q', () {
      final r = rewriter();
      final result = asString(out(r, '\x1bP2;1;8q#0;2;0;0;0~\x1b\\'));
      expect(result, startsWith('\x1b_Ga=t,f=32,t=d,i=1073741824,s=1,v=6;'));
    });

    test('passes non-sixel DCS through verbatim', () {
      final r = rewriter();
      final seq = '\x1bP1\$r\x1b\\'; // some other DCS
      expect(asString(out(r, seq)), seq);
    });

    test('passes non-kitty APC through verbatim', () {
      final r = rewriter();
      const seq = '\x1b_25a1;AAAA\x1b\\'; // glyph protocol style
      expect(asString(out(r, seq)), seq);
    });

    test('passes plain text, CSI and OSC through unchanged', () {
      final r = rewriter();
      const input = 'hello\x1b[31mred\x1b]2;title\x07done';
      expect(asString(out(r, input)), input);
    });

    test('buffers sequences split across feed calls', () {
      final r = rewriter();
      final part1 = out(r, '\x1b_Ga=T,f=100,s=1,v=1,t=d;QUFB');
      final part2 = out(r, 'QQ==\x1b\\');
      expect(part1, isEmpty); // held until the terminator arrives
      expect(asString(part2), '\x1b_Gi=1073741824,a=T,f=100,s=1,v=1,t=d;QUFBQQ==\x1b\\');
    });

    test('aborted string (ESC not followed by backslash) is passed through', () {
      final r = rewriter();
      final result = asString(out(r, '\x1b_Ga=T;QUFB\x1b[1mX'));
      // The unterminated APC bytes plus the fresh CSI sequence.
      expect(result, '\x1b_Ga=T;QUFB\x1b[1mX');
    });

    test('oversized strings degrade to passthrough', () {
      final r = rewriter();
      final big = 'A' * (VtGraphicsRewriter.maxBufferBytes + 10);
      final result = asString(out(r, '\x1b_Ga=t;$big\x1b\\'));
      expect(result, '\x1b_Ga=t;$big\x1b\\');
    });
  });
}
