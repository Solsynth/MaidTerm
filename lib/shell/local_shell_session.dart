import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_pty/flutter_pty.dart';
import 'package:maidterm/maidterm.dart' as maidterm;

import 'process_title_monitor.dart';

/// Runs a local login shell inside a pty and bridges it to a
/// [maidterm.TerminalController].
///
/// Bytes flow both ways: terminal output is written to the pty, pty output
/// is fed into the controller, and grid resizes are forwarded to the pty so
/// full-screen TUIs and kitty-graphics clients see the real size.
///
/// The display title (see [title]) follows the terminal app's OSC 0/2 title,
/// the foreground process name from [ProcessTitleMonitor], or the working
/// directory (OSC 7, falling back to the spawn directory) for shells.
///
/// Set [autoStart] to false to construct the session without spawning a
/// shell (used by widget tests, where plugin frameworks are not linked).
class LocalShellSession {
  LocalShellSession({
    String? shell,
    bool autoStart = true,
    bool cursorBlink = true,
    maidterm.CursorShape cursorStyle = maidterm.CursorShape.block,
    ProcessTitleMonitor? processMonitor,
  }) : _fallbackTitle = _shellNameOf(shell ?? _defaultShell()),
       _spawnCwd = _defaultWorkingDirectory() {
    _monitor = processMonitor;
    _controller = maidterm.TerminalController(
      config: maidterm.TerminalConfig(
        cursorBlink: cursorBlink,
        cursorStyle: cursorStyle,
        scrollbackLimit: 10_000_000,
      ),
    );
    _displayTitle = ValueNotifier<String>(_fallbackTitle);
    _controller.onOutput = _writeToPty;
    _controller.onResize = _resizePty;
    _controller.onTitleChanged = _onTitleChanged;
    _controller.onPwdChanged = _onPwdChanged;
    if (!autoStart) return;
    final pty = _pty = Pty.start(
      shell ?? _defaultShell(),
      rows: 24,
      columns: 80,
      workingDirectory: _spawnCwd,
      // flutter_pty only forwards a fixed env set; COLORTERM must be opt-in
      // or truecolor clients (fastfetch, vim, bat) silently downgrade.
      environment: const {
        'TERM': 'xterm-256color',
        'COLORTERM': 'truecolor',
      },
    );
    _ptyPid = pty.pid;
    _subscriptions.add(pty.output.listen(_controller.write));
    final monitor = _monitor;
    if (monitor != null) {
      monitor.addListener(_refreshTitle);
      monitor.track(_ptyPid!);
    }
  }

  Pty? _pty;
  int? _ptyPid;
  ProcessTitleMonitor? _monitor;
  late final maidterm.TerminalController _controller;
  final List<StreamSubscription<Object?>> _subscriptions = [];

  /// OSC 0/2 title set by the running program; empty until one is set.
  String _oscTitle = '';

  /// Working directory reported by the shell (OSC 7); empty until reported.
  String _pwd = '';

  /// Directory the session started in, used until OSC 7 arrives.
  final String _spawnCwd;

  /// Shell executable name, shown when nothing better is known.
  final String _fallbackTitle;

  late final ValueNotifier<String> _displayTitle;

  /// The controller bound to this session; pass to [maidterm.TerminalView].
  maidterm.TerminalController get controller => _controller;

  /// Live display title: the terminal app's OSC 0/2 title when set, else the
  /// foreground process name, else the working directory for shells, else
  /// the shell name.
  ValueListenable<String> get title => _displayTitle;

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

  void _onTitleChanged() {
    _oscTitle = _controller.title;
    _refreshTitle();
  }

  void _onPwdChanged() {
    _pwd = _controller.pwd;
    _refreshTitle();
  }

  void _refreshTitle() {
    final appTitle = _oscTitle.trim();
    if (appTitle.isNotEmpty) {
      _displayTitle.value = appTitle;
      return;
    }
    final pid = _ptyPid;
    final foreground = pid == null ? null : _monitor?.foregroundName(pid);
    if (foreground != null && !isShellProcessName(foreground)) {
      _displayTitle.value = foreground.split(RegExp(r'[/\\]')).last;
      return;
    }
    // A shell (or unknown process): show the working directory.
    final pwd = _pwd.trim();
    final cwd = pwd.isEmpty ? _spawnCwd : _stripFileScheme(pwd);
    _displayTitle.value = abbreviateHome(
      cwd,
      Platform.environment['HOME'] ?? '',
    );
  }

  /// OSC 7 payloads are `file://host/path` URLs; keep only the path part.
  static String _stripFileScheme(String raw) {
    const prefix = 'file://';
    if (!raw.startsWith(prefix)) return raw;
    final rest = raw.substring(prefix.length);
    final slash = rest.indexOf('/');
    return slash < 0 ? rest : rest.substring(slash);
  }

  static String _defaultWorkingDirectory() =>
      Platform.environment['HOME'] ?? '/';

  static String _shellNameOf(String shell) {
    var name = shell.split(RegExp(r'[/\\]')).last;
    if (name.endsWith('.exe')) {
      name = name.substring(0, name.length - 4);
    }
    return name;
  }

  Future<void> dispose() async {
    _monitor?.removeListener(_refreshTitle);
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _controller.onOutput = null;
    _controller.onResize = null;
    _controller.onTitleChanged = null;
    _controller.onPwdChanged = null;
    final pid = _ptyPid;
    if (pid != null) _monitor?.untrack(pid);
    final pty = _pty;
    if (pty != null) {
      if (Platform.isWindows) {
        pty.kill();
      }
      await pty.exitCode;
    }
    _displayTitle.dispose();
    _controller.dispose();
  }

  static String _defaultShell() {
    if (Platform.isWindows) return 'powershell.exe';
    return Platform.environment['SHELL'] ?? '/bin/zsh';
  }
}
