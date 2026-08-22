import 'dart:convert';
import 'dart:typed_data';

import 'package:maidterm/src/widgets/sixel_decoder.dart';
import 'package:maidterm/src/foundation/terminal_progress.dart';

/// Rewrites the terminal input stream to close two graphics-protocol gaps
/// in the libghostty core:
///
/// 1. **Kitty graphics acknowledgment.** The core suppresses the
///    `ESC _ G i=N;OK ESC \` response for transmits that rely on an
///    auto-assigned image id (no `i=` in the command). Capability probes
///    detect the protocol from that response, so a fresh id is injected
///    into transmit commands that omit one, letting the core reply.
/// 2. **DEC sixel.** The core does not implement sixel at all. Sixel DCS
///    sequences (`ESC P ... q ... ESC \`) are decoded to RGBA and
///    re-emitted as Kitty graphics transmit + display commands, which the
///    core renders and which advance the cursor the way a sixel renderer
///    would.
///
/// All other bytes — text, CSI, OSC, non-graphics APC/DCS — pass through
/// untouched. Sequences that span [feed] calls are buffered until they
/// complete; malformed or oversized strings degrade to verbatim
/// passthrough.
final class VtGraphicsRewriter {
  /// Supplies the next image id for injected Kitty transmits. Ids must
  /// stay out of the range the core auto-assigns (0x7FFFFFFF upward).
  final int Function() nextImageId;

  /// Receives OSC 9;4 progress reports.
  void Function(TerminalProgress progress)? onProgress;

  /// Receives OSC 9/777 desktop notification requests.
  void Function(String title, String body)? onNotification;

  /// Maximum notification payload buffered before passthrough.
  static const int maxNotificationBytes = 8192;

  /// Maximum bytes buffered for one control string. Beyond this the
  /// remainder of the string is forwarded verbatim.
  static const int maxBufferBytes = 16 * 1024 * 1024;

  final BytesBuilder _out = BytesBuilder(copy: false);
  final BytesBuilder _buf = BytesBuilder(copy: false);
  _State _state = _State.plain;
  bool _stringIsApc = false;

  VtGraphicsRewriter({required this.nextImageId});

  /// Feeds one chunk of pty/backend output and returns the rewritten
  /// bytes to hand to the terminal core.
  Uint8List feed(Uint8List chunk) {
    _out.clear();
    for (final b in chunk) {
      _step(b);
    }
    final result = _out.takeBytes();
    // _out may share storage with the caller's chunk; copy to detach.
    return Uint8List.fromList(result);
  }

  void _step(int b) {
    switch (_state) {
      case _State.plain:
        if (b == 0x1b) {
          _buf.add([b]);
          _state = _State.esc;
        } else {
          _out.addByte(b);
        }

      case _State.esc:
        _buf.add([b]);
        switch (b) {
          case 0x5f: // ESC _ — APC
            _state = _State.string;
            _stringIsApc = true;
          case 0x50: // ESC P — DCS
            _state = _State.string;
            _stringIsApc = false;
          case 0x5d: // ESC ] — OSC
            _state = _State.osc;
          default: // Plain ESC sequence (or lone ESC \).
            _flushVerbatim();
            _state = _State.plain;
        }

      case _State.osc:
        if (b == 0x07) {
          _buf.add([b]);
          _processOscComplete();
          _state = _State.plain;
        } else if (b == 0x1b) {
          _buf.add([b]);
          _state = _State.oscEsc;
        } else {
          _buf.add([b]);
          if (_buf.length > maxNotificationBytes) {
            _out.add(_buf.takeBytes());
            _state = _State.oscPassthrough;
          }
        }

      case _State.oscEsc:
        if (b == 0x5c) {
          _buf.add([b]);
          _processOscComplete();
          _state = _State.plain;
        } else {
          final collected = _buf.takeBytes();
          _out.add(collected.sublist(0, collected.length - 1));
          _buf.clear();
          _buf.add([0x1b, b]);
          switch (b) {
            case 0x5f:
              _state = _State.string;
              _stringIsApc = true;
            case 0x50:
              _state = _State.string;
              _stringIsApc = false;
            case 0x5d:
              _state = _State.osc;
            default:
              _flushVerbatim();
              _state = _State.plain;
          }
        }

      case _State.oscPassthrough:
        _out.addByte(b);
        if (b == 0x07) {
          _state = _State.plain;
        } else if (b == 0x1b) {
          _state = _State.oscPassthroughEsc;
        }

      case _State.oscPassthroughEsc:
        _out.addByte(b);
        if (b == 0x5c) {
          _state = _State.plain;
        } else {
          _state = _State.oscPassthrough;
        }

      case _State.string:
        if (b == 0x1b) {
          _buf.add([b]);
          _state = _State.stringEsc;
        } else if (b == 0x18 || b == 0x1a) {
          // CAN/SUB abort the string; forward the collected bytes so the
          // core re-parses them exactly as it would have without us.
          _buf.add([b]);
          _flushVerbatim();
          _state = _State.plain;
        } else {
          _buf.add([b]);
        }
        if (_state == _State.string && _buf.length > maxBufferBytes) {
          // Oversized string: stop buffering, forward the rest raw.
          _out.add(_buf.takeBytes());
          _state = _State.passthrough;
        }

      case _State.stringEsc:
        if (b == 0x5c) {
          // ESC \ — string terminator. The full string is in _buf.
          _buf.add([b]);
          _processComplete();
          _state = _State.plain;
        } else {
          // ESC followed by something else: the string is malformed.
          // Forward everything before the ESC verbatim, then treat the
          // ESC and this byte as a fresh escape sequence.
          final collected = _buf.takeBytes();
          _out.add(collected.sublist(0, collected.length - 1));
          _buf.clear();
          _buf.add([0x1b, b]);
          switch (b) {
            case 0x5f:
              _state = _State.string;
              _stringIsApc = true;
            case 0x50:
              _state = _State.string;
              _stringIsApc = false;
            default:
              _flushVerbatim();
              _state = _State.plain;
          }
        }

      case _State.passthrough:
        _out.addByte(b);
        if (b == 0x1b) {
          _state = _State.passthroughEsc;
        }

      case _State.passthroughEsc:
        _out.addByte(b);
        if (b == 0x5c) {
          _state = _State.plain;
        } else {
          _state = _State.passthrough;
        }
    }
  }

  void _flushVerbatim() {
    _out.add(_buf.takeBytes());
  }

  void _processComplete() {
    final bytes = _buf.takeBytes();
    final rewritten = _stringIsApc ? _rewriteKitty(bytes) : _rewriteDcs(bytes);
    _out.add(rewritten ?? bytes);
  }

  void _processOscComplete() {
    final bytes = _buf.takeBytes();
    final terminatorLength = bytes.last == 0x07 ? 1 : 2;
    final payloadEnd = bytes.length - terminatorLength;
    if (payloadEnd <= 2) {
      _out.add(bytes);
      return;
    }

    final payload = utf8.decode(
      bytes.sublist(2, payloadEnd),
      allowMalformed: true,
    );
    final separator = payload.indexOf(';');
    if (separator < 0) {
      _out.add(bytes);
      return;
    }

    final command = payload.substring(0, separator);
    final args = payload.substring(separator + 1);
    String? title;
    String? body;
    if (command == '9') {
      final progressParams = args.startsWith('4;') ? args.substring(2) : null;
      final progress = progressParams == null
          ? null
          : TerminalProgress.tryParse(progressParams);
      if (progress != null) {
        onProgress?.call(progress);
      } else if (args.isNotEmpty) {
        body = args;
      }
    } else if (command == '777') {
      final parts = args.split(';');
      if (parts.isNotEmpty && parts.first == 'notify') {
        final notification = parts.skip(1).toList();
        if (notification.length >= 2) {
          title = notification.first;
          body = notification.skip(1).join(';');
        } else if (notification.length == 1) {
          body = notification.first;
        }
      }
    }

    final notificationBody = body;
    if (notificationBody != null && notificationBody.isNotEmpty) {
      onNotification?.call(title ?? '', notificationBody);
    }
    _out.add(bytes);
  }

  /// Returns the rewritten APC bytes for a complete `ESC _ ... ESC \`
  /// string, or null to keep [bytes] as-is.
  Uint8List? _rewriteKitty(Uint8List bytes) {
    // bytes = ESC _ G <controls>[; <data>] ESC \
    if (bytes.length < 4 || bytes[2] != 0x47) return null; // not kitty
    final needsId = _kittyTransmitNeedsId(bytes);
    if (!needsId) return null;
    final id = nextImageId();
    // ESC _ G + "i=<id>," + the original controls and payload.
    final prefix = utf8.encode('i=$id,');
    final result = Uint8List(3 + prefix.length + bytes.length - 3);
    result.setRange(0, 3, [0x1b, 0x5f, 0x47]);
    result.setRange(3, 3 + prefix.length, prefix);
    result.setRange(3 + prefix.length, result.length, bytes, 3);
    return result;
  }

  /// Whether a complete kitty APC is a transmit without an explicit image
  /// id or number (the case where the core suppresses its response).
  ///
  /// Continuation chunks — commands whose only control is `m=` — belong to
  /// the transmission opened by their start chunk and never carry their own
  /// id, so injecting one would fork the transmission. Start chunks are
  /// recognized by carrying any other key alongside `m=`.
  bool _kittyTransmitNeedsId(Uint8List bytes) {
    // bytes = ESC _ G controls... ESC \ ; the data part (after ';') is
    // irrelevant here.
    var i = 3;
    final end = bytes.length - 2; // exclude trailing ESC \
    var hasAction = false;
    var actionIsTransmit = false;
    var hasContinuation = false;
    var hasOtherKey = false;
    while (i < end) {
      final key = bytes[i];
      if (key == 0x3b) break; // ';' — data starts; controls done

      if (key == 0x2c) {
        // ',' — separator; next key starts at i+1
        i += 1;
        continue;
      }
      // Parse key=value.
      var j = i + 1;
      while (j < end &&
          bytes[j] != 0x3d &&
          bytes[j] != 0x2c &&
          bytes[j] != 0x3b) {
        j += 1;
      }
      if (j < end && bytes[j] == 0x3d) {
        var k = j + 1;
        while (k < end && bytes[k] != 0x2c && bytes[k] != 0x3b) {
          k += 1;
        }
        final value = String.fromCharCodes(bytes, j + 1, k);
        switch (key) {
          case 0x61: // a
            hasAction = true;
            actionIsTransmit = value == 't' || value == 'T';
            hasOtherKey = true;
          case 0x69: // i — explicit image id
          case 0x49: // I — image number
            return false;
          case 0x6d: // m — continuation flag
            hasContinuation = true;
          default:
            hasOtherKey = true;
        }
        i = k;
        continue;
      }
      i = j;
    }
    if (hasContinuation && !hasOtherKey) return false;
    return !hasAction || actionIsTransmit;
  }

  /// Returns the replacement bytes for a complete DCS string, or null to
  /// keep the original (non-sixel DCS, or undecodable sixel).
  Uint8List? _rewriteDcs(Uint8List bytes) {
    // bytes = ESC P <params> q <data> ESC \
    final qIndex = _dcsFinalIndex(bytes);
    if (qIndex < 0) return null;
    final payload = Uint8List.sublistView(bytes, qIndex + 1, bytes.length - 2);
    final image = SixelDecoder.decode(payload);
    if (image == null) return null;

    final id = nextImageId();
    final rgbaB64 = base64Encode(image.rgba);
    final transmit = utf8.encode(
      '\x1b_Ga=t,f=32,t=d,i=$id,s=${image.width},v=${image.height};$rgbaB64\x1b\\',
    );
    final display = utf8.encode('\x1b_Ga=p,i=$id\x1b\\');
    final result = Uint8List(transmit.length + display.length);
    result.setRange(0, transmit.length, transmit);
    result.setRange(transmit.length, result.length, display);
    return result;
  }

  /// Index of the DCS final byte `q`, or -1 when this is not a sixel
  /// (or any recognized) DCS string. Params are digits/`;`/`"`/`?`.
  int _dcsFinalIndex(Uint8List bytes) {
    var i = 2; // after ESC P
    final end = bytes.length - 2;
    while (i < end) {
      final c = bytes[i];
      if (c == 0x71) return i; // 'q'
      final validParam =
          (c >= 0x30 && c <= 0x39) || c == 0x3b || c == 0x22 || c == 0x3f;
      if (!validParam) return -1;
      i += 1;
    }
    return -1;
  }
}

enum _State {
  plain,
  esc,
  osc,
  oscEsc,
  oscPassthrough,
  oscPassthroughEsc,
  string,
  stringEsc,
  passthrough,
  passthroughEsc,
}
