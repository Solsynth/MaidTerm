import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// One row of the process table as reported by `ps`.
final class ProcRow {
  const ProcRow({
    required this.pid,
    required this.ppid,
    required this.tty,
    required this.stat,
    required this.comm,
    this.pgid,
    this.rssKb,
  });

  final int pid;
  final int ppid;
  final int? pgid;

  /// Controlling terminal, e.g. `ttys002` or `pts/3`; `??` when none.
  final String tty;

  /// Process state flags. A trailing `+` marks the foreground process group
  /// of the controlling terminal.
  final String stat;
  final int? rssKb;

  /// Executable name (basename; login shells carry a leading `-`).
  final String comm;
  bool get inForegroundGroup => stat.contains('+');
}

/// Parses `ps -eo pid=,ppid=,pgid=,tty=,stat=,rss=,comm=` output into a
/// pid-keyed table. The legacy five-column shape remains accepted for tests
/// and callers that only need process names.
Map<int, ProcRow> parsePsTable(String output) {
  final table = <int, ProcRow>{};
  for (final line in output.split('\n')) {
    final parts = line.trim().split(RegExp(r'\s+'));
    if (parts.length < 5) continue;
    final pid = int.tryParse(parts[0]);
    final ppid = int.tryParse(parts[1]);
    if (pid == null || ppid == null) continue;
    final extended =
        parts.length >= 7 &&
        int.tryParse(parts[2]) != null &&
        int.tryParse(parts[5]) != null;
    final ttyIndex = extended ? 3 : 2;
    final statIndex = extended ? 4 : 3;
    final commIndex = extended ? 6 : 4;
    table[pid] = ProcRow(
      pid: pid,
      ppid: ppid,
      pgid: extended ? int.tryParse(parts[2]) : null,
      tty: parts[ttyIndex],
      stat: parts[statIndex],
      rssKb: extended ? int.tryParse(parts[5]) : null,
      comm: parts[commIndex],
    );
  }
  return table;
}

/// Resolves the executable name of the foreground process of the session
/// whose shell has [shellPid], or null when the table has no entry for it.
///
/// Foreground = same controlling terminal as the shell and marked `+` in
/// STAT. When a chain such as `sh -c vim` shares one foreground group, the
/// deepest descendant of the shell wins. Falls back to the shell itself when
/// no `+` row is present.
String? foregroundProcessName(Map<int, ProcRow> table, int shellPid) {
  final shell = table[shellPid];
  if (shell == null) return null;
  final tty = shell.tty;
  final candidates = table.values
      .where((row) => row.tty == tty && row.inForegroundGroup)
      .toList();
  final pick = candidates.isEmpty
      ? shell
      : _deepestDescendant(table, candidates, shellPid) ?? shell;
  return pick.comm;
}

/// Resident memory for the foreground process group on the shell's tty.
/// Returns bytes, or null when the process table has no RSS data.
int? foregroundProcessMemoryBytes(Map<int, ProcRow> table, int shellPid) {
  final shell = table[shellPid];
  if (shell == null) return null;
  final foreground = table.values
      .where(
        (row) =>
            row.tty == shell.tty &&
            row.inForegroundGroup &&
            !row.stat.startsWith('Z'),
      )
      .toList();
  if (foreground.isEmpty) return _rssBytes(shell.rssKb);
  final pgid = foreground.first.pgid;
  final rows = pgid == null
      ? foreground
      : table.values.where(
          (row) =>
              row.tty == shell.tty &&
              row.pgid == pgid &&
              !row.stat.startsWith('Z'),
        );
  final rssKb = rows.fold<int>(0, (sum, row) => sum + (row.rssKb ?? 0));
  return rssKb == 0 ? null : rssKb * 1024;
}

int? _rssBytes(int? rssKb) => rssKb == null ? null : rssKb * 1024;

ProcRow? _deepestDescendant(
  Map<int, ProcRow> table,
  List<ProcRow> candidates,
  int shellPid,
) {
  ProcRow? best;
  var bestDepth = -1;
  for (final candidate in candidates) {
    var depth = 0;
    var current = candidate;
    while (current.pid != shellPid) {
      final parent = table[current.ppid];
      if (parent == null) break;
      current = parent;
      depth++;
    }
    if (current.pid == shellPid && depth > bestDepth) {
      best = candidate;
      bestDepth = depth;
    }
  }
  return best;
}

/// Sorted unique executable names of non-shell programs still alive in the
/// session of [shellPid], per [table]. Every process on the shell's
/// controlling terminal belongs to that session, so foreground and
/// background children are both counted; the shell itself, nested shells,
/// and zombies are ignored.
List<String> runningProgramNamesInTable(Map<int, ProcRow> table, int shellPid) {
  final shell = table[shellPid];
  if (shell == null) return const [];
  final names = <String>{};
  for (final row in table.values) {
    if (row.tty != shell.tty || row.pid == shellPid) continue;
    if (row.stat.startsWith('Z')) continue;
    final name = row.comm.split(RegExp(r'[/\\]')).last;
    if (isShellProcessName(name)) continue;
    names.add(name);
  }
  final sorted = names.toList()..sort();
  return sorted;
}

/// Shell executables whose idle presence means the tab should show the
/// working directory instead of the process name.
const _shellNames = {
  'sh',
  'bash',
  'zsh',
  'fish',
  'ksh',
  'csh',
  'tcsh',
  'dash',
  'ash',
  'pwsh',
  'powershell',
  'cmd',
  'nu',
  'elvish',
  'xonsh',
  'oil',
  'ion',
  'mksh',
  'yash',
};

/// Whether [comm] names a shell. Login-shell `-zsh` prefixes, path prefixes,
/// and `.exe` suffixes are tolerated.
bool isShellProcessName(String comm) {
  var name = comm.split(RegExp(r'[/\\]')).last;
  while (name.startsWith('-')) {
    name = name.substring(1);
  }
  if (name.endsWith('.exe')) {
    name = name.substring(0, name.length - 4);
  }
  return _shellNames.contains(name.toLowerCase());
}

/// Abbreviates [path] under [home] to `~`-form.
String abbreviateHome(String path, String home) {
  if (home.isEmpty) return path;
  if (path == home) return '~';
  if (path.startsWith('$home/')) return '~${path.substring(home.length)}';
  return path;
}

/// Shared poller of the process table. Foreground process names are resolved
/// per pty session; the poll runs only while at least one session is
/// tracked.
final class ProcessTitleMonitor {
  /// How often the process table is refreshed while sessions are tracked.
  static const refreshInterval = Duration(seconds: 1);

  ProcessTitleMonitor();

  final revision = ValueNotifier<int>(0);

  Map<int, ProcRow> _table = const {};
  final Set<int> _shellPids = {};
  final _listeners = <void Function()>[];
  Timer? _timer;
  bool _refreshing = false;

  /// `ps` is unavailable on Windows; process-based titles are a no-op there.
  static bool get isSupported => Platform.isLinux || Platform.isMacOS;

  void addListener(void Function() listener) => _listeners.add(listener);

  void removeListener(void Function() listener) => _listeners.remove(listener);

  /// Starts tracking a session whose shell is [shellPid].
  void track(int shellPid) {
    if (!isSupported) return;
    if (!_shellPids.add(shellPid)) return;
    _timer ??= Timer.periodic(refreshInterval, (_) => _refresh());
    unawaited(_refresh());
  }

  /// Stops tracking [shellPid]; the poll stops when nothing is tracked.
  void untrack(int shellPid) {
    _shellPids.remove(shellPid);
    if (_shellPids.isEmpty) {
      _timer?.cancel();
      _timer = null;
    }
  }

  /// Foreground executable name for the session of [shellPid], from the
  /// most recent table refresh.
  String? foregroundName(int shellPid) =>
      foregroundProcessName(_table, shellPid);

  /// RSS for the foreground process group of [shellPid], in bytes.
  int? foregroundMemoryBytes(int shellPid) =>
      foregroundProcessMemoryBytes(_table, shellPid);

  /// Whether the session of [shellPid] still runs non-shell programs per
  /// the most recent table refresh.
  bool sessionHasRunningPrograms(int shellPid) =>
      runningProgramNamesInTable(_table, shellPid).isNotEmpty;

  /// Non-shell program names still alive in the session of [shellPid] per
  /// the most recent table refresh.
  List<String> runningProgramNames(int shellPid) =>
      runningProgramNamesInTable(_table, shellPid);

  Future<void> _refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      final result = await Process.run('ps', const [
        '-eo',
        'pid=,ppid=,pgid=,tty=,stat=,rss=,comm=',
      ]);
      if (result.exitCode != 0) return;
      _table = parsePsTable(result.stdout as String);
      revision.value++;
      for (final listener in List.of(_listeners)) {
        listener();
      }
    } on Object {
      // Keep the last table; a transient `ps` failure is not fatal.
    } finally {
      _refreshing = false;
    }
  }

  void dispose() {
    _timer?.cancel();
    revision.dispose();
  }
}
