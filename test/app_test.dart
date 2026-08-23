import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:maidterm_app/app.dart';

import 'package:maidterm_app/workspace/terminal_workspace.dart';
import 'package:maidterm_app/shell/local_shell_session.dart';

import 'package:maidterm_app/workspace/terminal_workspace_page.dart';

void main() {
  testWidgets('command comma opens settings', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localShellSessionFactoryProvider.overrideWithValue(
            ({String? workingDirectory}) => LocalShellSession(
              workingDirectory: workingDirectory,
              autoStart: false,
            ),
          ),
        ],
        child: const MaidTermApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.comma, character: ',');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.comma);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('terminal shortcuts manage tabs and panes', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localShellSessionFactoryProvider.overrideWithValue(
            ({String? workingDirectory}) => LocalShellSession(
              workingDirectory: workingDirectory,
              autoStart: false,
            ),
          ),
        ],
        child: const MaidTermApp(),
      ),
    );
    await tester.pumpAndSettle();

    Future<void> press(LogicalKeyboardKey key, {bool shift = false}) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      if (shift) {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      }
      await tester.sendKeyDownEvent(key);
      await tester.sendKeyUpEvent(key);
      if (shift) {
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      }
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    }

    final container = ProviderScope.containerOf(
      tester.element(find.byType(TerminalWorkspacePage)),
    );
    await press(LogicalKeyboardKey.keyT);
    expect(container.read(terminalWorkspaceProvider).tabs, hasLength(2));

    await press(LogicalKeyboardKey.keyD);
    await press(LogicalKeyboardKey.keyD, shift: true);
    expect(container.read(terminalWorkspaceProvider).panes, hasLength(3));

    await press(LogicalKeyboardKey.keyW);
    expect(container.read(terminalWorkspaceProvider).tabs, hasLength(1));
  });
}
