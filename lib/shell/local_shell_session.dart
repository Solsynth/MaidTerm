import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:maidpty/maidpty.dart';
import 'package:maidterm/maidterm.dart' as maidterm;
import 'package:window_manager/window_manager.dart';

import 'package:maidterm_app/notifications/app_notifications.dart';
import 'package:maidterm_app/shell/process_title_monitor.dart';

/// Delay before showing activity for a sustained output stream.
const _outputActivityDebounce = Duration(milliseconds: 200);

/// Quiet output tolerated when the debounce window expires.
const _outputActivityQuietWindow = Duration(milliseconds: 100);

/// How long the tab stays active after the latest non-empty PTY output.
const _outputActivityDuration = Duration(milliseconds: 500);

/// Ignore PTY output immediately following keyboard input; shells echo the
/// submitted line, which is not program activity.
const _inputEchoSuppression = Duration(milliseconds: 250);

/// Returns the PATH passed to a shell spawned by a packaged desktop app.
///
/// macOS apps launched from Finder do not inherit the user's interactive shell
/// PATH. Keep the inherited order (important for development and custom
/// installations), then add conventional user-tool locations so startup files
/// can resolve tools such as Homebrew-installed `mise` and `atuin`.
String effectiveShellPath({Map<String, String>? environment, bool? isMacOS}) {
  final source = environment ?? Platform.environment;
  final separator = Platform.isWindows ? ';' : ':';
  final entries = <String>[];
  final seen = <String>{};

  void add(String? path) {
    final value = path?.trim() ?? '';
    if (value.isEmpty || !seen.add(value)) return;
    entries.add(value);
  }

  for (final path in (source['PATH'] ?? '').split(separator)) {
    add(path);
  }

  final home = source['HOME']?.trim();
  if (isMacOS ?? Platform.isMacOS) {
    add('/opt/homebrew/bin');
    add('/opt/homebrew/sbin');
    add('/usr/local/bin');
    add('/usr/local/sbin');
  }
  if (home != null && home.isNotEmpty) {
    add('$home/.local/bin');
    add('$home/.cargo/bin');
  }
  return entries.join(separator);
}

Map<String, String> _shellEnvironment() => {
  'TERM': 'xterm-256color',
  'COLORTERM': 'truecolor',
  'TERM_PROGRAM': 'MaidTerm',
  'PATH': effectiveShellPath(),
};

/// Runs a local login shell inside a pty and bridges it to a
/// [maidterm.TerminalController].
///
/// Bytes flow both ways: terminal output is written to the pty, pty output
/// is fed into the controller, and grid resizes are forwarded to the pty so
/// full-screen TUIs and kitty-graphics clients see the real size.
///
/// The display title (see [title]) follows the terminal app's OSC 0/2 title,
/// the foreground process name from [ProcessTitleMonitor], or the working
/// directory (OSC 7, falling back to the spawn directory) for shells. The
/// OSC title is scoped to the program that set it: when that program exits
/// and the shell takes the foreground, the title reverts to the shell's
/// working directory instead of sticking.
///
/// Set [autoStart] to false to construct the session without spawning a
/// shell (used by widget tests, where plugin frameworks are not linked).
class LocalShellSession {
  LocalShellSession({
    String? shell,
    String? workingDirectory,
    int? sessionId,
    bool autoStart = true,
    bool cursorBlink = true,
    maidterm.CursorShape cursorStyle = maidterm.CursorShape.block,
    ProcessTitleMonitor? processMonitor,
    bool Function()? runningPrograms,
    String? Function()? foregroundProgramName,
  }) : _fallbackTitle = _shellNameOf(shell ?? _defaultShell()),
       _spawnCwd = _normalizeWorkingDirectory(workingDirectory),
       _attachedSession = sessionId != null,
       _runningProgramsCheck = runningPrograms,
       _foregroundProgramNameCheck = foregroundProgramName {
    _monitor = processMonitor;
    _controller = maidterm.TerminalController(
      config: maidterm.TerminalConfig(
        cursorBlink: cursorBlink,
        cursorStyle: cursorStyle,
        scrollbackLimit: 10_000_000,
      ),
    );
    _displayTitle = ValueNotifier<String>(_fallbackTitle);
    _outputActive = ValueNotifier<bool>(false);
    _progress = ValueNotifier<maidterm.TerminalProgress?>(null);
    _fullScreen = ValueNotifier<bool>(false);
    _controller.onBell = _handleBell;
    _controller.onNotification = _handleNotification;
    _controller.onProgress = _handleProgress;
    _controller.onOutput = _writeToPty;
    _controller.onResize = _resizePty;
    _controller.onTitleChanged = _onTitleChanged;
    _controller.onPwdChanged = _onPwdChanged;
    if (!autoStart) return;
    final pty = _pty = sessionId == null
        ? Pty.start(
            shell ?? _defaultShell(),
            rows: 24,
            columns: 80,
            workingDirectory: _spawnCwd,
            // maidpty only forwards a fixed env set; COLORTERM must be opt-in
            // or truecolor clients (fastfetch, vim, bat) silently downgrade.
            environment: _shellEnvironment(),
          )
        : Pty.attach(sessionId);
    _ptyPid = pty.pid;
    _subscriptions.add(pty.output.listen(writeOutput));
    unawaited(pty.exitCode.then((_) => _handlePtyExit()));

    final monitor = _monitor;
    if (monitor != null) {
      monitor.addListener(_refreshTitle);
      monitor.track(_ptyPid!);
    }
  }
  Pty? _pty;
  final bool _attachedSession;

  /// Stable native session ID used for cross-window attachment.
  int? get sessionId => _pty?.sessionId;

  /// Re-emits the destination viewport size to an attached PTY.
  void refreshResize() {
    if (_attachedSession) _controller.refreshResize();
  }

  /// Called when the shell process exits on its own.
  VoidCallback? onExit;

  bool _disposed = false;
  bool _exitHandled = false;
  int? _ptyPid;
  ProcessTitleMonitor? _monitor;

  /// Test seam: overrides the live process-table running-programs check.
  final bool Function()? _runningProgramsCheck;
  final String? Function()? _foregroundProgramNameCheck;
  late final maidterm.TerminalController _controller;
  final List<StreamSubscription<Object?>> _subscriptions = [];

  /// OSC 0/2 title set by the running program; empty until one is set.
  String _oscTitle = '';

  /// Foreground program that set [_oscTitle], so the title reverts when that
  /// program exits and the shell takes the foreground. Null while the owner
  /// is unknown or the title came from the shell.
  String? _oscTitleOwner;

  /// Working directory reported by the shell (OSC 7); empty until reported.
  String _pwd = '';

  /// Shell executable name, shown when nothing better is known.
  final String _fallbackTitle;

  /// Directory the session started in, used until OSC 7 arrives.
  final String _spawnCwd;

  late final ValueNotifier<String> _displayTitle;
  late final ValueNotifier<maidterm.TerminalProgress?> _progress;
  late final ValueNotifier<bool> _outputActive;
  late final ValueNotifier<bool> _fullScreen;
  Timer? _outputActivityStartTimer;
  Timer? _outputActivityTimer;
  DateTime? _lastInputAt;
  DateTime? _lastOutputAt;

  /// Visual full-screen state reported by the terminal renderer.
  ValueListenable<bool> get isFullScreen => _fullScreen;

  /// The controller bound to this session; pass to [maidterm.TerminalView].
  maidterm.TerminalController get controller => _controller;

  /// Live display title: the terminal app's OSC 0/2 title when set, else the
  /// foreground process name, else the working directory for shells, else
  /// the shell name.
  ValueListenable<String> get title => _displayTitle;

  /// Current working directory reported by the shell, or the spawn directory
  /// until the shell sends its first OSC 7 update.
  String get workingDirectory {
    final pwd = _pwd.trim();
    return pwd.isEmpty ? _spawnCwd : _stripFileScheme(pwd);
  }

  /// Live OSC 9;4 progress reported by the running program.
  ValueListenable<maidterm.TerminalProgress?> get progress => _progress;

  /// Whether this session emitted terminal output recently.
  ///
  /// A short debounce suppresses the spinner for commands that produce one
  /// brief output burst, while the expiry keeps sustained activity visible.
  ValueListenable<bool> get isOutputActive => _outputActive;

  /// Feeds PTY output into the terminal and records recent output activity.
  ///
  /// Use this instead of calling [controller.write] for backend output.
  void writeOutput(Uint8List bytes) {
    if (_disposed || bytes.isEmpty) return;
    final now = DateTime.now();
    final lastInputAt = _lastInputAt;
    _controller.write(bytes);
    if (lastInputAt != null &&
        now.difference(lastInputAt) <= _inputEchoSuppression) {
      return;
    }
    _lastOutputAt = now;
    if (_outputActive.value) {
      _scheduleOutputActivityExpiry();
    } else {
      _outputActivityStartTimer ??= Timer(
        _outputActivityDebounce,
        _startOutputActivityIfRecent,
      );
    }
  }

  void _startOutputActivityIfRecent() {
    _outputActivityStartTimer = null;
    if (_disposed) return;
    final lastOutputAt = _lastOutputAt;
    if (lastOutputAt == null ||
        DateTime.now().difference(lastOutputAt) > _outputActivityQuietWindow) {
      _lastOutputAt = null;
      return;
    }
    _outputActive.value = true;
    _scheduleOutputActivityExpiry();
  }

  void _scheduleOutputActivityExpiry() {
    _outputActivityTimer?.cancel();
    _outputActivityTimer = Timer(_outputActivityDuration, () {
      _outputActivityTimer = null;
      if (_disposed) return;
      _outputActive.value = false;
      _lastOutputAt = null;
    });
  }

  /// Whether a program other than the idle shell is still running in this
  /// session, per the latest process-table poll.
  bool get hasRunningPrograms {
    final check = _runningProgramsCheck;
    if (check != null) return check();
    final pid = _ptyPid;
    final monitor = _monitor;
    if (pid == null || monitor == null) return false;
    return monitor.sessionHasRunningPrograms(pid);
  }

  /// Names of non-shell programs still alive in this session, from the
  /// latest process-table poll. Empty when the session is idle or the
  /// process table is unavailable.
  List<String> get runningProgramNames {
    final pid = _ptyPid;
    final monitor = _monitor;
    if (pid == null || monitor == null) return const [];
    return monitor.runningProgramNames(pid);
  }

  void _writeToPty(Uint8List bytes) {
    if (bytes.isNotEmpty) _lastInputAt = DateTime.now();
    final pty = _pty;
    if (pty == null) return;
    try {
      pty.write(bytes);
    } on Object {
      // The pty may already be closed while the shell is exiting; nothing
      // useful can be done with the terminal's output at that point.
    }
  }

  void _onPwdChanged() {
    _pwd = _controller.pwd;
    _refreshTitle();
  }

  void _handleBell() {
    unawaited(SystemSound.play(SystemSoundType.alert));
  }

  Future<void> _handleNotification(String title, String body) async {
    if (await windowManager.isFocused()) return;
    await AppNotifications.show(
      title: title.trim().isEmpty ? 'MaidTerm' : title.trim(),
      body: body,
    );
  }

  void _handleProgress(maidterm.TerminalProgress progress) {
    _progress.value = progress.state == .remove ? null : progress;
  }

  void _resizePty(int cols, int rows, int pixelWidth, int pixelHeight) {
    _pty?.resize(rows, cols, pixelWidth: pixelWidth, pixelHeight: pixelHeight);
  }

  /// Updates the visual full-screen state from the rendered terminal frame.
  void setVisualFullScreen(bool value) {
    if (!_disposed) _fullScreen.value = value;
  }

  void _onTitleChanged() {
    _oscTitle = _controller.title;
    // Re-derive ownership from the foreground on the next refresh; a stale
    // process table cannot be trusted in the instant after a title write.
    _oscTitleOwner = null;
    _refreshTitle();
  }

  void _refreshTitle() {
    final foreground = _currentForegroundName();
    final appTitle = _oscTitle.trim();
    if (appTitle.isNotEmpty) {
      if (foreground != null && !isShellProcessName(foreground)) {
        // A non-shell program is the foreground; it owns the OSC title.
        _oscTitleOwner = foreground;
        _displayTitle.value = appTitle;
        return;
      }
      // The foreground is a shell or unknown. A title owned by the shell
      // stays; a title owned by a program that since left is dropped so the
      // fallback (process name / working directory) resumes.
      final owner = _oscTitleOwner;
      if (owner == null || isShellProcessName(owner)) {
        _displayTitle.value = appTitle;
        return;
      }
      _oscTitle = '';
      _oscTitleOwner = null;
    }
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

  /// The foreground program of the session, from the seam when set, else the
  /// most recent process-table poll.
  String? _currentForegroundName() {
    final check = _foregroundProgramNameCheck;
    if (check != null) return check();
    final pid = _ptyPid;
    if (pid == null) return null;
    return _monitor?.foregroundName(pid);
  }

  /// OSC 7 payloads are `file://host/path` URLs; keep only the path part.
  static String _stripFileScheme(String raw) {
    const prefix = 'file://';
    if (!raw.startsWith(prefix)) return raw;
    final rest = raw.substring(prefix.length);
    final slash = rest.indexOf('/');
    return slash < 0 ? rest : rest.substring(slash);
  }

  static String _normalizeWorkingDirectory(String? workingDirectory) {
    final normalized = _stripFileScheme(workingDirectory?.trim() ?? '');
    return normalized.isEmpty ? _defaultWorkingDirectory() : normalized;
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

  void _handlePtyExit() {
    if (_disposed || _exitHandled) return;
    _exitHandled = true;
    onExit?.call();
  }

  /// Detaches this frontend without terminating the shared native session.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _monitor?.removeListener(_refreshTitle);
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _controller.onOutput = null;
    _controller.onResize = null;
    _controller.onTitleChanged = null;
    _controller.onPwdChanged = null;
    _controller.onProgress = null;
    final pid = _ptyPid;
    if (pid != null) _monitor?.untrack(pid);
    _outputActivityStartTimer?.cancel();
    _outputActivityStartTimer = null;
    _outputActivityTimer?.cancel();
    _outputActivityTimer = null;
    _lastInputAt = null;
    _lastOutputAt = null;
    _displayTitle.dispose();
    _progress.dispose();
    _outputActive.dispose();
    _fullScreen.dispose();
    _controller.dispose();
  }

  /// Explicitly terminates the native session before detaching this frontend.
  Future<void> terminate() async {
    if (_disposed) return;
    await _pty?.destroy();
    await dispose();
  }

  static String _defaultShell() {
    if (Platform.isWindows) return 'powershell.exe';
    return Platform.environment['SHELL'] ?? '/bin/zsh';
  }
}
