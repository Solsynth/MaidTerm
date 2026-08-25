import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_symbols_icons/material_symbols_icons.dart';
import 'package:maidterm_app/app.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dart:convert';
import 'dart:io';

import 'package:maidterm_app/workspace/terminal_workspace.dart';
import 'package:maidterm_app/shell/local_shell_session.dart';

import 'package:maidterm_app/workspace/terminal_workspace_page.dart';
import 'package:maidterm_app/settings/settings_page.dart';

/// Loads the real translation JSON files synchronously from disk.
///
/// easy_localization's default [RootBundleAssetLoader] goes through the
/// platform messenger, which does not progress in the fake-async zone of a
/// widget test once a previous test's EasyLocalization tree has been torn
/// down. Reading the files directly keeps the tests hermetic and real.
class _TestAssetLoader extends AssetLoader {
  final String basePath;
  const _TestAssetLoader(this.basePath);

  @override
  Future<Map<String, dynamic>?> load(String path, Locale locale) async {
    final file = File(
      '$basePath/${locale.toStringWithSeparator(separator: '-')}.json',
    );
    if (!file.existsSync()) return null;
    return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  }
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    EasyLocalization.logger.enableBuildModes = [];
  });

  Widget app() {
    return EasyLocalization(
      supportedLocales: const [Locale('en', 'US')],
      path: 'assets/translations',
      fallbackLocale: const Locale('en', 'US'),
      useFallbackTranslations: true,
      assetLoader: const _TestAssetLoader('assets/translations'),
      child: ProviderScope(
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
  }

  testWidgets('command comma opens settings', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(TerminalWorkspacePage)),
    );
    final session = container
        .read(terminalWorkspaceProvider)
        .selectedTab!
        .session;
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
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
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

    final container = ProviderScope.containerOf(
      tester.element(find.byType(TerminalWorkspacePage)),
    );
    final firstSession = container
        .read(terminalWorkspaceProvider)
        .selectedTab!
        .session;
    final emitted = <int>[];
    firstSession.controller.onOutput = emitted.addAll;
    await press(LogicalKeyboardKey.keyT);
    expect(container.read(terminalWorkspaceProvider).tabs, hasLength(2));
    expect(emitted, isEmpty);

    final secondSession = container
        .read(terminalWorkspaceProvider)
        .selectedTab!
        .session;
    secondSession.controller.onOutput = emitted.addAll;

    await press(LogicalKeyboardKey.keyD);
    await press(LogicalKeyboardKey.keyD, shift: true);
    expect(container.read(terminalWorkspaceProvider).panes, hasLength(3));
    expect(emitted, isEmpty);

    // Cmd+W closes the focused pane, not the whole tab group.
    await press(LogicalKeyboardKey.keyW);
    expect(container.read(terminalWorkspaceProvider).tabs, hasLength(2));
    expect(container.read(terminalWorkspaceProvider).panes, hasLength(2));

    // Cmd+Shift+W closes the entire selected tab.
    await press(LogicalKeyboardKey.keyW, shift: true);
    expect(container.read(terminalWorkspaceProvider).tabs, hasLength(1));
  });

  testWidgets('Ctrl+Tab cycles tabs, Cmd+number selects panes', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(TerminalWorkspacePage)),
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
    final firstTabId = container.read(terminalWorkspaceProvider).tabs.first.id;
    final secondTab = container.read(terminalWorkspaceProvider).selectedTab!;
    final secondTabPaneIds = secondTab.layout.paneIds.toList();

    // Cmd+1 selects the first pane in the selected tab.
    await press(LogicalKeyboardKey.metaLeft, LogicalKeyboardKey.digit1);
    expect(
      container.read(terminalWorkspaceProvider).focusedPaneId,
      secondTabPaneIds.first,
    );

    // Cmd+Tab is intentionally not a navigation shortcut.
    await press(LogicalKeyboardKey.metaLeft, LogicalKeyboardKey.tab);
    expect(
      container.read(terminalWorkspaceProvider).selectedTabId,
      secondTab.id,
    );
    expect(
      container.read(terminalWorkspaceProvider).focusedPaneId,
      secondTabPaneIds.first,
    );

    // Ctrl+Tab switches top-level tabs and preserves each tab's focused pane.
    await press(LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.tab);
    expect(container.read(terminalWorkspaceProvider).selectedTabId, firstTabId);
    expect(
      container.read(terminalWorkspaceProvider).focusedPaneId,
      container.read(terminalWorkspaceProvider).tabs.first.layout.paneIds.first,
    );
    await press(LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.tab);
    expect(
      container.read(terminalWorkspaceProvider).selectedTabId,
      secondTab.id,
    );
    expect(
      container.read(terminalWorkspaceProvider).focusedPaneId,
      secondTabPaneIds.first,
    );

    // Cmd+2 selects the second pane in the selected tab.
    await press(LogicalKeyboardKey.metaLeft, LogicalKeyboardKey.digit2);
    expect(
      container.read(terminalWorkspaceProvider).selectedTabId,
      secondTab.id,
    );
    expect(
      container.read(terminalWorkspaceProvider).focusedPaneId,
      secondTabPaneIds.last,
    );
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
    expect(find.text('menuNewTab'.tr()), findsOneWidget);

    await tester.tap(find.text('menuNewTab'.tr()));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(TerminalWorkspacePage)),
    );
    expect(container.read(terminalWorkspaceProvider).tabs, hasLength(2));
  });
}
