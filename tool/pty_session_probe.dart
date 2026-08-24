import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:maidpty/maidpty.dart';

Future<void> main() async {
  final first = Pty.start(
    '/bin/sh',
    arguments: [
      '-c',
      r'''printf "PID=$$\n"; i=0; while true; do i=$((i+1)); printf "MARK-$i\n"; sleep 0.1; done''',
    ],
  );
  final firstOutput = <String>[];
  final firstSubscription = first.output.listen(
    (data) => firstOutput.add(utf8.decode(data)),
  );
  await Future<void>.delayed(const Duration(milliseconds: 300));
  final second = Pty.attach(first.sessionId);
  if (second.pid != first.pid) {
    throw StateError('PID changed: ${first.pid} -> ${second.pid}');
  }
  final secondOutput = <String>[];
  final secondSubscription = second.output.listen(
    (data) => secondOutput.add(utf8.decode(data)),
  );
  await Future<void>.delayed(const Duration(milliseconds: 300));
  if (!secondOutput.any((chunk) => chunk.contains('MARK-'))) {
    throw StateError('Attached frontend received no retained/live output');
  }
  await first.dispose();
  final markerCount = secondOutput.length;
  await Future<void>.delayed(const Duration(milliseconds: 300));
  if (secondOutput.length <= markerCount) {
    throw StateError('Second frontend stopped after first detach');
  }
  final pid = second.pid;
  await second.destroy();
  if (Process.killPid(pid, ProcessSignal.sigterm)) {
    throw StateError('PTY process $pid survived destroy');
  }
  await firstSubscription.cancel();
  await secondSubscription.cancel();
  stdout.writeln('PTY continuity verified: pid=$pid');
}
