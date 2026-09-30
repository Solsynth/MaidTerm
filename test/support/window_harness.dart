import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:maidterm_app/app.dart';
import 'package:maidterm_app/shell/local_shell_session.dart';
import 'package:maidterm_app/windows/workspace_windows.dart';
import 'package:maidterm_app/workspace/terminal_workspace.dart';
import 'package:maidterm_app/workspace/terminal_workspace_page.dart';

/// Loads the real translation JSON files synchronously from disk.
///
/// easy_localization's default [RootBundleAssetLoader] goes through the
/// platform messenger, which does not progress in the fake-async zone of a
/// widget test once a previous test's EasyLocalization tree has been torn
/// down. Reading the files directly keeps the tests hermetic and real.
class WorkspaceTestAssetLoader extends AssetLoader {
  const WorkspaceTestAssetLoader([this.basePath = 'assets/translations']);

  final String basePath;

  @override
  Future<Map<String, dynamic>?> load(String path, Locale locale) async {
    final file = File(
      '$basePath/${locale.toStringWithSeparator(separator: '-')}.json',
    );
    if (!file.existsSync()) return null;
    return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  }
}

/// Windows controller for widget tests.
///
/// Windows drive the native multi-window API, which a test has no host for, so
/// [createWindow] hands out window records with no controller and no native
/// window behind them. Everything above — the workspace providers, the tab
/// strip, the window bookkeeping, the drag state machine — stays the real
/// implementation.
class TestWorkspaceWindows extends WorkspaceWindowsController {
  TestWorkspaceWindows(super.ref);

  int _created = 0;

  @override
  WorkspaceWindow? createWindow({Size? size}) =>
      registerWindow(WorkspaceWindow(id: 'window-${++_created}'));
}

/// The window a [pumpWorkspaceWindow] test drives.
const testWindowId = 'test-window';

/// Pumps one terminal window with its first terminal open.
///
/// Opening the first terminal is a host responsibility now, so every test
/// starts from the same point the app does: an empty workspace that the host
/// fills.
Future<WorkspaceHost> pumpWorkspaceWindow(
  WidgetTester tester, {
  String windowId = testWindowId,
  String? workingDirectory,
  List<Object?> overrides = const [],
}) =>
    _pumpWindow(
      tester,
      windowId: windowId,
      workingDirectory: workingDirectory,
      overrides: overrides,
      home: TerminalWorkspacePage(windowId: windowId),
    );

/// Pumps a whole window — title bar, menus and the workspace page — the way
/// the app mounts [MaidTermWindowApp].
Future<WorkspaceHost> pumpAppWindow(
  WidgetTester tester, {
  String windowId = testWindowId,
  String? workingDirectory,
  List<Object?> overrides = const [],
}) =>
    _pumpWindow(
      tester,
      windowId: windowId,
      workingDirectory: workingDirectory,
      overrides: overrides,
      home: MaidTermWindowApp(windowId: windowId),
    );

/// Pumps [child] under the test scope: fake windows, sessions that never
/// spawn a pty, real translations.
Future<ProviderContainer> pumpHarness(
  WidgetTester tester,
  Widget child, {
  List<Object?> overrides = const [],
}) async {
  final container = ProviderContainer(
    overrides: [
      workspaceWindowsProvider.overrideWith(TestWorkspaceWindows.new),
      localShellSessionFactoryProvider.overrideWithValue(
        ({String? workingDirectory}) => LocalShellSession(
          workingDirectory: workingDirectory,
          autoStart: false,
        ),
      ),
      // `cast` pins the element type to the override type the container wants,
      // which riverpod does not export by name.
      ...overrides.cast(),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: EasyLocalization(
        supportedLocales: const [Locale('en', 'US')],
        path: 'assets/translations',
        fallbackLocale: const Locale('en', 'US'),
        useFallbackTranslations: true,
        assetLoader: const WorkspaceTestAssetLoader(),
        child: MaterialApp(home: child),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Future<WorkspaceHost> _pumpWindow(
  WidgetTester tester, {
  required String windowId,
  required Widget home,
  String? workingDirectory,
  List<Object?> overrides = const [],
}) async {
  final container = await pumpHarness(
    tester,
    home,
    overrides: overrides,
  );
  final host = WorkspaceHost(container, windowId);
  host.notifier.openTerminal(workingDirectory: workingDirectory);
  await tester.pumpAndSettle();
  return host;
}

/// A pumped window plus the handles a test needs on its state.
class WorkspaceHost {
  WorkspaceHost(this.container, this.windowId);

  final ProviderContainer container;
  final String windowId;

  TerminalWorkspaceNotifier get notifier =>
      container.read(terminalWorkspaceProvider(windowId).notifier);

  TerminalWorkspaceState get state =>
      container.read(terminalWorkspaceProvider(windowId));

  /// Tabs of this window, in strip order.
  List<TerminalWorkspaceTab> get tabs => state.tabs;

  TerminalWorkspaceTab get selectedTab => state.selectedTab!;

  /// The terminal the selected tab's focused pane runs.
  TerminalTab get focusedTerminal => selectedTab.focusedPane!.tab;
}
