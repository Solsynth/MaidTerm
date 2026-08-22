import 'dart:typed_data';

import 'package:maidterm/src/widgets/sixel_decoder.dart';
import 'package:test/test.dart';

void main() {
  group('SixelDecoder', () {
    Uint8List bytes(String s) => Uint8List.fromList(s.codeUnits);

    test('decodes the terminfo.dev probe image (1x2 black)', () {
      // ESC P q #0;2;0;0;0 ~ - ~ ESC \  — the exact sixel render probe.
      final image = SixelDecoder.decode(bytes('#0;2;0;0;0~-~'));
      expect(image, isNotNull);
      expect(image!.width, 1);
      expect(image.height, 12);
      expect(image.rgba.length, 1 * 12 * 4);
      // All pixels opaque black.
      for (var i = 0; i < image.rgba.length; i += 4) {
        expect(image.rgba[i], 0);
        expect(image.rgba[i + 1], 0);
        expect(image.rgba[i + 2], 0);
        expect(image.rgba[i + 3], 0xFF);
      }
    });

    test('honors palette definitions and transparency', () {
      // Color 0 -> red; '@' = 0b000001 paints only the bottom pixel.
      final image = SixelDecoder.decode(bytes('#0;2;100;0;0@'));
      expect(image!.width, 1);
      expect(image.height, 6);
      // Bottom pixel (row 5) is red and opaque.
      expect(image.rgba[20], 255);
      expect(image.rgba[21], 0);
      expect(image.rgba[22], 0);
      expect(image.rgba[23], 0xFF);
      // Top pixel (row 0) stays transparent.
      expect(image.rgba[0], 0);
      expect(image.rgba[3], 0);
    });

    test('default palette applies to unreferenced color indices', () {
      // '#15' selects the default bright-white entry; '~' paints it.
      final image = SixelDecoder.decode(bytes('#15~'));
      expect(image!.rgba[0], 0xFF);
      expect(image.rgba[1], 0xFF);
      expect(image.rgba[2], 0xFF);
    });

    test('run-length encoding expands horizontally', () {
      // '!' + '1' repeats '~' (6 set bits) twice => 2 columns.
      final image = SixelDecoder.decode(bytes('#15!1~'));
      expect(image!.width, 2);
      expect(image.rgba[0], 0xFF);
      expect(image.rgba[4 * 4], 0xFF); // pixel (1, 0)
    });

    test('dollar returns to column zero of the same band', () {
      // Two columns of '~' separated by '$': both land on band 0, x 0.
      final image = SixelDecoder.decode(bytes('~\$~'));
      expect(image!.width, 1);
      expect(image.height, 6);
      expect(image.rgba[4 + 3], 0xFF); // pixel (0, 1) painted opaque
    });

    test('line feed advances to the next band', () {
      final image = SixelDecoder.decode(bytes('#15~-~'));
      expect(image!.height, 12);
      expect(image.rgba[0], 0xFF); // band 0
      expect(image.rgba[4 * 6], 0xFF); // band 1, top pixel
    });

    test('empty payload returns null', () {
      expect(SixelDecoder.decode(Uint8List(0)), isNull);
    });

    test('palette-only payload (no pixels) returns null', () {
      expect(SixelDecoder.decode(bytes('#0;2;0;0;0')), isNull);
    });
  });
}
