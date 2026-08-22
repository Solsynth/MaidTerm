import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_pty/flutter_pty.dart';
import 'package:maidterm/maidterm.dart' as maidterm;

/// Runs a local login shell inside a pty and bridges it to a
/// [maidterm.TerminalController].
///
/// Bytes flow both ways: terminal output is written to the pty, pty output
/// is fed into the controller, and grid resizes are forwarded to the pty so
/// full-screen TUIs and kitty-graphics clients see the real size.
///
/// Set [autoStart] to false to construct the session without spawning a
/// shell (used by widget tests, where plugin frameworks are not linked).
class LocalShellSession {
  LocalShellSession({
    String? shell,
    bool autoStart = true,
    bool cursorBlink = true,
    maidterm.CursorShape cursorStyle = maidterm.CursorShape.block,
  }) {
    _controller = maidterm.TerminalController(
      config: maidterm.TerminalConfig(
        cursorBlink: cursorBlink,
        cursorStyle: cursorStyle,
        scrollbackLimit: 10_000_000,
      ),
    );
    _controller.onOutput = _writeToPty;
    _controller.onResize = _resizePty;
    if (!autoStart) return;
    final pty = _pty = Pty.start(
      shell ?? _defaultShell(),
      rows: 24,
      columns: 80,
      workingDirectory: Platform.environment['HOME'] ?? '/',
      // flutter_pty only forwards a fixed env set; COLORTERM must be opt-in
      // or truecolor clients (fastfetch, vim, bat) silently downgrade.
      environment: const {
        'TERM': 'xterm-256color',
        'COLORTERM': 'truecolor',
      },
    );
    _subscriptions.add(pty.output.listen(_controller.write));
  }

  Pty? _pty;
  late final maidterm.TerminalController _controller;
  final List<StreamSubscription<Object?>> _subscriptions = [];

  /// The controller bound to this session; pass to [maidterm.TerminalView].
  maidterm.TerminalController get controller => _controller;

  void _writeToPty(Uint8List bytes) {
    final pty = _pty;
    if (pty == null) return;
    try {
      pty.write(bytes);
    } on Object {
      // The pty may already be closed while the shell is exiting; nothing
      // useful can be done with the terminal's output at that point.
    }
  }

  void _resizePty(int cols, int rows, int pixelWidth, int pixelHeight) {
    _pty?.resize(rows, cols);
  }

  Future<void> dispose() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _controller.onOutput = null;
    _controller.onResize = null;
    final pty = _pty;
    if (pty != null) {
      if (Platform.isWindows) {
        pty.kill();
      }
      await pty.exitCode;
    }
    _controller.dispose();
  }

  static String _defaultShell() {
    if (Platform.isWindows) return 'powershell.exe';
    return Platform.environment['SHELL'] ?? '/bin/zsh';
  }
}
