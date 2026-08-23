import 'package:flutter_test/flutter_test.dart';
import 'package:maidterm_app/shell/process_title_monitor.dart';

void main() {
  group('parsePsTable', () {
    test('parses rows and skips malformed lines', () {
      final table = parsePsTable('''
        PID PPID TTY STAT COMM
        100 1 ttys001 Ss -zsh
        101 100 ttys001 S+ vim
        not-a-pid 1 ttys001 Ss x
        200 1 ?? S sleep
      ''');
      expect(table.keys, containsAll([100, 101, 200]));
      expect(table[100]!.comm, '-zsh');
      expect(table[100]!.tty, 'ttys001');
      expect(table[101]!.inForegroundGroup, isTrue);
      expect(table[200]!.inForegroundGroup, isFalse);
    });
  });

  group('foregroundProcessName', () {
    test('returns the foreground process on the same tty', () {
      final table = parsePsTable('''
        100 1 ttys001 Ss -zsh
        101 100 ttys001 S+ vim
        200 1 ttys002 Ss bash
      ''');
      expect(foregroundProcessName(table, 100), 'vim');
    });

    test('deepest descendant wins in a shared foreground group', () {
      final table = parsePsTable('''
        100 1 ttys001 Ss -zsh
        101 100 ttys001 S+ sh
        102 101 ttys001 S+ top
      ''');
      expect(foregroundProcessName(table, 100), 'top');
    });

    test('falls back to the shell itself when idle', () {
      final table = parsePsTable('''
        100 1 ttys001 Ss+ -zsh
        200 1 ttys002 Ss+ bash
      ''');
      expect(foregroundProcessName(table, 100), '-zsh');
    });

    test('ignores background jobs (no + flag)', () {
      final table = parsePsTable('''
        100 1 ttys001 Ss+ -zsh
        101 100 ttys001 S sleep
      ''');
      expect(foregroundProcessName(table, 100), '-zsh');
    });

    test('returns null for an unknown shell pid', () {
      final table = parsePsTable('100 1 ttys001 Ss zsh\n');
      expect(foregroundProcessName(table, 99), isNull);
    });
  });

  group('isShellProcessName', () {
    test('detects shells with login dashes, paths, and exe suffixes', () {
      expect(isShellProcessName('zsh'), isTrue);
      expect(isShellProcessName('-zsh'), isTrue);
      expect(isShellProcessName('/bin/bash'), isTrue);
      expect(isShellProcessName('powershell.exe'), isTrue);
    });

    test('rejects non-shell executables', () {
      expect(isShellProcessName('vim'), isFalse);
      expect(isShellProcessName('node'), isFalse);
      expect(isShellProcessName('htop'), isFalse);
    });
  });

  group('runningProgramNamesInTable', () {
    test('lists non-shell processes on the session tty, deduped and sorted', () {
      final table = parsePsTable('''
        100 1 ttys001 Ss -zsh
        101 100 ttys001 S+ vim
        102 100 ttys001 S sleep
        103 100 ttys001 S node
        104 100 ttys001 S node
        200 1 ttys002 Ss bash
      ''');
      expect(runningProgramNamesInTable(table, 100), ['node', 'sleep', 'vim']);
    });

    test('ignores the shell itself, nested shells, and zombies', () {
      final table = parsePsTable('''
        100 1 ttys001 Ss -zsh
        101 100 ttys001 S+ sh
        102 101 ttys001 Z top
      ''');
      expect(runningProgramNamesInTable(table, 100), isEmpty);
    });

    test('reports background jobs even when the shell is foreground', () {
      final table = parsePsTable('''
        100 1 ttys001 Ss+ -zsh
        101 100 ttys001 S sleep 100
      ''');
      expect(runningProgramNamesInTable(table, 100), ['sleep']);
    });

    test('returns empty for an unknown shell pid', () {
      final table = parsePsTable('100 1 ttys001 Ss zsh\n');
      expect(runningProgramNamesInTable(table, 99), isEmpty);
    });
  });

  group('abbreviateHome', () {
    test('abbreviates paths under home', () {
      expect(abbreviateHome('/Users/me', '/Users/me'), '~');
      expect(abbreviateHome('/Users/me/repo', '/Users/me'), '~/repo');
      expect(abbreviateHome('/tmp/x', '/Users/me'), '/tmp/x');
    });

    test('leaves paths untouched when home is unknown', () {
      expect(abbreviateHome('/tmp/x', ''), '/tmp/x');
    });
  });
}
