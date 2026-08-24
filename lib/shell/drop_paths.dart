import 'dart:io';

/// Formats OS-dropped file paths for insertion into the terminal as typed
/// text.
///
/// Each path is shell-quoted so it survives as a single command-line
/// argument: single quotes for POSIX shells (macOS, Linux) and double
/// quotes for cmd/PowerShell (Windows). Paths that only contain safe
/// characters are left bare for readability. Multiple paths are joined with
/// a space, and a trailing space is appended so the user can keep typing
/// the next argument (matches Terminal.app, iTerm2, and kitty behavior).

/// Characters that need no quoting in a POSIX shell. Everything else
/// (spaces, quotes, `$`, backticks, globs, `~`, …) forces single-quoting.
final _posixSafe = RegExp(r'^[A-Za-z0-9_./\-]+$');

/// Characters that need no quoting in cmd/PowerShell.
final _windowsSafe = RegExp(r'^[A-Za-z0-9_\-.:\\/]+$');

/// Quotes [path] for the current platform's shell.
String escapeDropPath(String path) {
  if (path.isEmpty) return path;
  if (Platform.isWindows) {
    if (_windowsSafe.hasMatch(path)) return path;
    return '"${path.replaceAll('"', '""')}"';
  }
  if (_posixSafe.hasMatch(path)) return path;
  return "'${path.replaceAll("'", r"'\''")}'";
}

/// Joins [paths] into one insertion string for the terminal input line.
String formatDroppedPaths(List<String> paths) {
  final escaped = paths.map(escapeDropPath).where((p) => p.isNotEmpty);
  final joined = escaped.join(' ');
  if (joined.isEmpty) return '';
  // Trailing space keeps the drop from gluing onto the next argument the
  // user types.
  return '$joined ';
}
