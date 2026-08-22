import 'dart:typed_data';

import 'package:meta/meta.dart';

/// Decoded sixel bitmap in straight-alpha RGBA.
///
/// Pixels that carry no sixel bits are transparent (alpha 0), so the
/// terminal background shows through exactly like a native sixel renderer.
@immutable
final class SixelImage {
  final int width;
  final int height;

  /// `width * height * 4` bytes of RGBA.
  final Uint8List rgba;

  const SixelImage({
    required this.width,
    required this.height,
    required this.rgba,
  });
}

/// Minimal, spec-faithful decoder for the DEC sixel graphics format.
///
/// Handles the sixel payload after the DCS final byte `q`: palette
/// definitions (`#Pc;2;R;G;B` and `#Pc` selection), run-length encoding
/// (`!N`), carriage return (`$`), line feed (`-`), and the sixel data
/// characters (0x3F..0x7E, 6 vertical pixels each, MSB on top). The
/// xterm-style `"Pan;Pad;Aspect` parameters and any other unknown bytes
/// are ignored.
///
/// The image is emitted pixel-for-pixel (no aspect-ratio correction);
/// the terminal sizes the placement in cells when it displays the image.
abstract final class SixelDecoder {
  /// Maximum decoded width or height in pixels. Guards against
  /// malicious or corrupt payloads allocating unbounded memory.
  static const int maxDimension = 16384;

  /// Maximum palette index we are willing to address. Sixel palettes are
  /// small; anything beyond this is treated as black.
  static const int maxPaletteEntries = 256;

  /// DEC standard 16-color default palette (RRGGBB). Used for color
  /// indices that are referenced but never defined by the payload.
  static const List<int> defaultPalette = [
    0x000000, //  0 black
    0x0000AA, //  1 blue
    0xAA0000, //  2 red
    0xAA00AA, //  3 magenta
    0x00AA00, //  4 green
    0x00AAAA, //  5 cyan
    0xAAAA00, //  6 yellow
    0xAAAAAA, //  7 white
    0x000000, //  8 black
    0x5555FF, //  9 blue (bright)
    0xFF5555, // 10 red (bright)
    0xFF55FF, // 11 magenta (bright)
    0x55FF55, // 12 green (bright)
    0x55FFFF, // 13 cyan (bright)
    0xFFFF55, // 14 yellow (bright)
    0xFFFFFF, // 15 white (bright)
  ];

  /// Decodes [payload] (the sixel data following the DCS `q` final byte)
  /// into an RGBA image, or returns null when the payload is empty or
  /// exceeds the [maxDimension] bounds.
  static SixelImage? decode(Uint8List payload) {
    if (payload.isEmpty) return null;

    // Palette: index -> packed RRGGBB. Entries are lazily resolved from
    // the DEC default palette on first use, so setting index 0 to a new
    // value only overrides that entry.
    final palette = <int, int>{};

    // Per-band state: band = 6 vertical pixels. Two parallel growable
    // lists per band: the 6-bit column pattern and the color index.
    final bandPatterns = <List<int>>[[]];
    final bandColors = <List<int>>[[]];

    var x = 0;
    var band = 0;
    var currentColor = 0;
    var maxX = 0;
    var maxBand = 0;
    var hasAnyPixel = false;

    void ensureBand(int index) {
      while (bandPatterns.length <= index) {
        bandPatterns.add([]);
        bandColors.add([]);
      }
    }

    void putColumn(int pattern, int color) {
      if (x >= maxDimension) return;
      final patterns = bandPatterns[band];
      while (patterns.length <= x) {
        patterns.add(0);
        bandColors[band].add(0);
      }
      if (x > maxX) maxX = x;
      if (band > maxBand) maxBand = band;
      patterns[x] = pattern;
      bandColors[band][x] = color;
      if (pattern != 0) hasAnyPixel = true;
    }

    int readNumber(int from) {
      var value = 0;
      var i = from;
      while (i < payload.length) {
        final c = payload[i];
        if (c < 0x30 || c > 0x39) break;
        value = value * 10 + (c - 0x30);
        if (value > 1000000) value = 1000000; // saturate absurd values
        i += 1;
      }
      return value;
    }

    var i = 0;
    while (i < payload.length) {
      final c = payload[i];

      if (c == 0x23) {
        // '#' — palette operation.
        final colorIndex = readNumber(i + 1);
        i += 1;
        // skip digits
        while (i < payload.length && payload[i] >= 0x30 && payload[i] <= 0x39) {
          i += 1;
        }
        if (i >= payload.length) break;
        if (payload[i] == 0x3B) {
          // ';' — definition: #Pc;Pu;Px;Py;Pz
          i += 1; // consume ';'
          final colorSpace = readNumber(i); // Pu: 2 = RGB, 1 = HLS
          i += 1;
          while (i < payload.length && payload[i] >= 0x30 && payload[i] <= 0x39) {
            i += 1;
          }
          if (colorSpace != 2) {
            // Only RGB definitions are supported; skip the rest.
            var skipped = 0;
            while (i < payload.length && skipped < 3) {
              if (payload[i] == 0x3B) {
                skipped += 1;
              } else if (payload[i] < 0x30 || payload[i] > 0x39) {
                break;
              }
              i += 1;
            }
            if (colorIndex <= maxPaletteEntries) currentColor = colorIndex;
            continue;
          }
          // ';' separators
          final components = <int>[];
          while (components.length < 3) {
            if (i >= payload.length || payload[i] != 0x3B) break;
            i += 1; // consume ';'
            final v = readNumber(i);
            components.add(v);
            i += 1;
            while (i < payload.length &&
                payload[i] >= 0x30 &&
                payload[i] <= 0x39) {
              i += 1;
            }
          }
          // RGB in 0..100 scale per DEC, but some emitters use 0..255.
          final scale255 =
              components.any((v) => v > 100) && components.every((v) => v <= 255);
          int component(int v) =>
              scale255 ? v : ((v * 255 + 50) ~/ 100).clamp(0, 255);
          if (components.length == 3 && colorIndex <= maxPaletteEntries) {
            palette[colorIndex] = (component(components[0]) << 16) |
                (component(components[1]) << 8) |
                component(components[2]);
          }
        }
        if (colorIndex <= maxPaletteEntries) currentColor = colorIndex;
        continue;
      }

      if (c == 0x21) {
        // '!' — run-length encoding: repeat next char count + 1 times.
        final count = readNumber(i + 1);
        i += 1;
        while (i < payload.length && payload[i] >= 0x30 && payload[i] <= 0x39) {
          i += 1;
        }
        if (i >= payload.length) break;
        final repeatChar = payload[i];
        final repeat = count + 1;
        i += 1;
        if (repeatChar >= 0x3F && repeatChar <= 0x7E) {
          for (var r = 0; r < repeat && x < maxDimension; r++) {
            putColumn(repeatChar - 0x3F, currentColor);
            x += 1;
          }
        }
        // '$' / '-' / '#' after '!' are rare but legal-ish; fall through
        // would double-consume, so handle them inline instead.
        if (repeatChar == 0x24) {
          x = 0;
        } else if (repeatChar == 0x2D) {
          band += 1;
          x = 0;
          ensureBand(band);
        }
        continue;
      }

      if (c == 0x24) {
        // '$' — return to column 0 of the current band.
        x = 0;
        i += 1;
        continue;
      }

      if (c == 0x2D) {
        // '-' — advance to the next band.
        band += 1;
        x = 0;
        ensureBand(band);
        i += 1;
        continue;
      }

      if (c >= 0x3F && c <= 0x7E) {
        putColumn(c - 0x3F, currentColor);
        x += 1;
      }
      i += 1;
    }

    if (!hasAnyPixel) return null;

    final width = maxX + 1;
    final height = (maxBand + 1) * 6;
    if (width > maxDimension || height > maxDimension) return null;

    final rgba = Uint8List(width * height * 4);
    int colorRgb(int index) {
      final defined = palette[index];
      if (defined != null) return defined;
      if (index < defaultPalette.length) return defaultPalette[index];
      return 0x000000;
    }

    for (var b = 0; b <= maxBand; b++) {
      final patterns = bandPatterns[b];
      final colors = bandColors[b];
      final yBase = b * 6;
      for (var px = 0; px < patterns.length; px++) {
        final pattern = patterns[px];
        if (pattern == 0) continue;
        final rgb = colorRgb(colors[px]);
        final base = (yBase * width + px) * 4;
        for (var bit = 0; bit < 6; bit++) {
          if ((pattern & (1 << (5 - bit))) == 0) continue;
          final offset = base + bit * width * 4;
          rgba[offset] = (rgb >> 16) & 0xFF;
          rgba[offset + 1] = (rgb >> 8) & 0xFF;
          rgba[offset + 2] = rgb & 0xFF;
          rgba[offset + 3] = 0xFF;
        }
      }
    }

    return SixelImage(width: width, height: height, rgba: rgba);
  }
}
