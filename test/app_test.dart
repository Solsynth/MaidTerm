import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_symbols_icons/material_symbols_icons.dart';
import 'package:maidterm_app/app.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:maidterm_app/workspace/terminal_workspace.dart';
import 'package:maidterm_app/shell/local_shell_session.dart';

import 'package:maidterm_app/workspace/terminal_workspace_page.dart';
import 'package:maidterm_app/settings/settings_page.dart';

void main() {
  Widget app() {
    return ProviderScope(
      overrides: [
        localShellSessionFactoryProvider.overrideWithValue(
          ({String? workingDirectory}) => LocalShellSession(
            workingDirectory: workingDirectory,
            autoStart: false,
          ),
        ),
      ],
      child: const MaidTermApp(),
    );
  }

  testWidgets('command comma opens settings', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.comma, character: ',');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.comma);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump(const Duration(milliseconds: 500));

    // The frame title also reads "Settings" while the route is open; assert
    // on the page itself.
    expect(find.byType(SettingsPage), findsOneWidget);
  });

  testWidgets('terminal shortcuts manage tabs and panes', (tester) async {
    await tester.pumpWidget(app());
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

  testWidgets('title bar menu opens and acts on the workspace', (tester) async {
    SharedPreferences.setMockInitialValues({
      'terminal.showTitleBarMenuButton': true,
    });
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    // The burger renders above the app routes and its popup has an Overlay
    // (regression: title-bar chrome previously had neither Overlay nor
    // Navigator ancestor).
    expect(find.byIcon(Symbols.menu), findsOneWidget);

    await tester.tap(find.byIcon(Symbols.menu));
    // Let the popup entrance animation complete before settling.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('New Tab'), findsOneWidget);

    await tester.tap(find.text('New Tab'));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(TerminalWorkspacePage)),
    );
    expect(container.read(terminalWorkspaceProvider).tabs, hasLength(2));
  });
}
