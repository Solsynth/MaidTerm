import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/material_symbols_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:maidterm_app/settings/settings_page.dart';
import 'package:maidterm_app/workspace/terminal_workspace.dart';
import 'package:maidterm_app/workspace/terminal_workspace_page.dart';

import 'support/window_harness.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    EasyLocalization.logger.enableBuildModes = [];
  });

  testWidgets('command comma opens settings', (tester) async {
    final host = await pumpAppWindow(tester);
    final session = host.focusedTerminal.session;
    final emitted = <int>[];
    session.controller.onOutput = emitted.addAll;

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.comma, character: ',');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.comma);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump(const Duration(milliseconds: 500));

    // The frame title also reads "Settings" while the route is open; assert
    // on the page itself.
    expect(find.byType(SettingsPage), findsOneWidget);
    expect(emitted, isEmpty);
  });

  testWidgets('terminal shortcuts manage tabs and panes', (tester) async {
    final host = await pumpAppWindow(tester);
    TerminalWorkspaceState state() => host.container.read(
      terminalWorkspaceProvider(host.windowId),
    );
    expect(find.byType(TerminalWorkspacePage), findsOneWidget);

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

    final firstSession = host.focusedTerminal.session;
    final emitted = <int>[];
    firstSession.controller.onOutput = emitted.addAll;
    await press(LogicalKeyboardKey.keyT);
    expect(state().tabs, hasLength(2));
    expect(emitted, isEmpty);

    final secondSession = host.focusedTerminal.session;
    secondSession.controller.onOutput = emitted.addAll;

    await press(LogicalKeyboardKey.keyD);
    await press(LogicalKeyboardKey.keyD, shift: true);
    expect(state().panes, hasLength(3));
    expect(emitted, isEmpty);

    // Cmd+W closes the focused pane, not the whole tab group.
    await press(LogicalKeyboardKey.keyW);
    expect(state().tabs, hasLength(2));
    expect(state().panes, hasLength(2));

    // Cmd+Shift+W closes the entire selected tab.
    await press(LogicalKeyboardKey.keyW, shift: true);
    expect(state().tabs, hasLength(1));
  });

  testWidgets('Ctrl+Tab cycles tabs, Cmd+number selects panes', (tester) async {
    final host = await pumpAppWindow(tester);
    TerminalWorkspaceState state() => host.container.read(
      terminalWorkspaceProvider(host.windowId),
    );

    Future<void> press(
      LogicalKeyboardKey modifier,
      LogicalKeyboardKey key,
    ) async {
      await tester.sendKeyDownEvent(modifier);
      await tester.sendKeyDownEvent(key);
      await tester.sendKeyUpEvent(key);
      await tester.sendKeyUpEvent(modifier);
      await tester.pump();
    }

    await press(LogicalKeyboardKey.metaLeft, LogicalKeyboardKey.keyT);
    await press(LogicalKeyboardKey.metaLeft, LogicalKeyboardKey.keyD);
    final firstTabId = state().tabs.first.id;
    final secondTab = state().selectedTab!;
    final secondTabPaneIds = secondTab.layout.paneIds.toList();

    // Cmd+1 selects the first pane in the selected tab.
    await press(LogicalKeyboardKey.metaLeft, LogicalKeyboardKey.digit1);
    expect(state().focusedPaneId, secondTabPaneIds.first);

    // Cmd+Tab is intentionally not a navigation shortcut.
    await press(LogicalKeyboardKey.metaLeft, LogicalKeyboardKey.tab);
    expect(state().selectedTabId, secondTab.id);
    expect(state().focusedPaneId, secondTabPaneIds.first);

    // Ctrl+Tab switches top-level tabs and preserves each tab's focused pane.
    await press(LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.tab);
    expect(state().selectedTabId, firstTabId);
    expect(
      state().focusedPaneId,
      state().tabs.first.layout.paneIds.first,
    );
    await press(LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.tab);
    expect(state().selectedTabId, secondTab.id);
    expect(state().focusedPaneId, secondTabPaneIds.first);

    // Cmd+2 selects the second pane in the selected tab.
    await press(LogicalKeyboardKey.metaLeft, LogicalKeyboardKey.digit2);
    expect(state().selectedTabId, secondTab.id);
    expect(state().focusedPaneId, secondTabPaneIds.last);
  });

  testWidgets('title bar menu opens and acts on the workspace', (tester) async {
    SharedPreferences.setMockInitialValues({
      'terminal.showTitleBarMenuButton': true,
    });
    final host = await pumpAppWindow(tester);

    // The burger renders above the app routes and its popup has an Overlay
    // (regression: title-bar chrome previously had neither Overlay nor
    // Navigator ancestor).
    expect(find.byIcon(Symbols.menu), findsOneWidget);

    await tester.tap(find.byIcon(Symbols.menu));
    // Let the popup entrance animation complete before settling.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('menuNewTab'.tr()), findsOneWidget);

    await tester.tap(find.text('menuNewTab'.tr()));
    await tester.pumpAndSettle();

    expect(
      host.container.read(terminalWorkspaceProvider(host.windowId)).tabs,
      hasLength(2),
    );
  });
}
