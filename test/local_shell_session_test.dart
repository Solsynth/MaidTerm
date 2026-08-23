import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:maidterm_app/shell/local_shell_session.dart';
import 'package:maidterm/maidterm.dart' as maidterm;

void main() {
  /// Feeds bytes into the engine exactly as pty output would arrive, then
  /// asserts the session's live display title.
  LocalShellSession session() => LocalShellSession(autoStart: false);

  test('OSC 2 window title becomes the tab title', () {
    final s = session();
    s.controller.write(utf8.encode('\x1b]2;vim notes\x07'));
    expect(s.title.value, 'vim notes');
    s.dispose();
  });

  test('OSC 0 sets both window and icon title; tab shows it', () {
    final s = session();
    s.controller.write(utf8.encode('\x1b]0;tmux: main\x07'));
    expect(s.title.value, 'tmux: main');
    s.dispose();
  });

  test('clearing the OSC title falls back to the working directory', () {
    final s = session();
    s.controller.write(utf8.encode('\x1b]2;vim notes\x07'));
    expect(s.title.value, 'vim notes');
    // vim restored its title on exit; the shell reports cwd via OSC 7.
    s.controller.write(utf8.encode('\x1b]2;\x07'));
    final home = Platform.environment['HOME']!;
    s.controller.write(utf8.encode('\x1b]7;file://$home/repo\x07'));
    expect(s.title.value, '~/repo');
    s.dispose();
  });

  test('shell-reported path (OSC 7) becomes the tab title', () {
    final s = session();
    s.controller.write(utf8.encode('\x1b]7;file:///tmp/x\x07'));
    expect(s.title.value, '/tmp/x');
    s.dispose();
  });

  test('working directory tracks the shell-reported OSC 7 path', () {
    final s = LocalShellSession(
      workingDirectory: '/tmp/start',
      autoStart: false,
    );
    expect(s.workingDirectory, '/tmp/start');
    s.controller.write(utf8.encode('\x1b]7;file://localhost/tmp/project\x07'));
    expect(s.workingDirectory, '/tmp/project');
    s.dispose();
  });

  test('disposing a session does not report a process exit', () async {
    var exited = false;
    final s = LocalShellSession(autoStart: false)..onExit = () => exited = true;
    await s.dispose();
    expect(exited, isFalse);
  });
  test('OSC 9;4 progress reports update and clear session progress', () {
    final s = session();

    s.controller.write(utf8.encode('\x1b]9;4;1;50\x07'));
    expect(s.progress.value?.state, maidterm.TerminalProgressState.normal);
    expect(s.progress.value?.value, 50);

    s.controller.write(utf8.encode('\x1b]9;4;0\x07'));
    expect(s.progress.value, isNull);
    s.dispose();
  });
}
