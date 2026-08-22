import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:maidterm/maidterm.dart' as maidterm;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:maidterm_app/shell/local_shell_session.dart';
import 'package:maidterm_app/workspace/session_layout.dart';
import 'package:maidterm_app/workspace/terminal_workspace.dart';
import 'package:maidterm_app/workspace/terminal_workspace_page.dart';

void main() {
  /// ProviderScope with sessions that never spawn a pty (plugin frameworks
  /// are not linked under `flutter test`).
  Widget buildWorkspace() {
    return ProviderScope(
      overrides: [
        localShellSessionFactoryProvider.overrideWithValue(
          () => LocalShellSession(autoStart: false),
        ),
      ],
      child: const MaterialApp(home: TerminalWorkspacePage()),
    );
  }

  testWidgets('applies persisted font settings to the startup terminal', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'terminal.fontFamily': 'Fira Code',
      'terminal.fontSize': 18.0,
    });

    await tester.pumpWidget(buildWorkspace());
    await tester.pumpAndSettle();

    final terminal = tester.widget<maidterm.TerminalView>(
      find.byType(maidterm.TerminalView),
    );
    expect(terminal.theme?.fontFamily, 'Fira Code');
    expect(terminal.theme?.fontSize, 18.0);
  });

  testWidgets('applies separate margins for normal and alternate screens', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'terminal.normalPaneMargin': '{"left":1,"top":2,"right":3,"bottom":4}',
      'terminal.fullScreenPaneMargin':
          '{"left":5,"top":6,"right":7,"bottom":8}',
    });

    await tester.pumpWidget(buildWorkspace());
    await tester.pumpAndSettle();

    final page = find.byType(TerminalWorkspacePage);
    final container = ProviderScope.containerOf(tester.element(page));
    final session = container
        .read(terminalWorkspaceProvider)
        .selectedTab!
        .session;
    maidterm.TerminalView currentTerminal() => tester
        .widget<maidterm.TerminalView>(find.byType(maidterm.TerminalView));

    expect(currentTerminal().padding, const EdgeInsets.fromLTRB(1, 2, 3, 4));

    session.controller.write(utf8.encode('\x1b[?1049h'));
    await tester.pump();
    expect(currentTerminal().padding, const EdgeInsets.fromLTRB(5, 6, 7, 8));

    session.controller.write(utf8.encode('\x1b[?1049l'));
    await tester.pump();
    expect(currentTerminal().padding, const EdgeInsets.fromLTRB(1, 2, 3, 4));
  });

  testWidgets('terminal surface fills fractional pane remainder', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1100, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(buildWorkspace());
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byType(maidterm.TerminalView)),
      const Size(1100, 600),
    );
  });
  testWidgets('terminal pane backing fills the full pane', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(buildWorkspace());
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byKey(const ValueKey('terminal-pane-backdrop'))),
      const Size(1100, 600),
    );
  });

  testWidgets('positions the tab bar from the persisted setting', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1100, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const expectedSizes = {
      'top': Size(1100, 600),
      'bottom': Size(1100, 600),
      'left': Size(916, 640),
      'right': Size(916, 640),
    };
    for (final entry in expectedSizes.entries) {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      SharedPreferences.setMockInitialValues({
        'terminal.tabBarPosition': entry.key,
      });
      await tester.pumpWidget(buildWorkspace());
      await tester.pumpAndSettle();

      expect(
        tester.getSize(find.byType(maidterm.TerminalView)),
        entry.value,
        reason: '${entry.key} tab bar placement',
      );
    }
  });

  testWidgets('resizes the vertical tab bar sidebar', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({'terminal.tabBarPosition': 'left'});

    await tester.pumpWidget(buildWorkspace());
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byType(maidterm.TerminalView)),
      const Size(916, 640),
    );

    await tester.drag(
      find.byKey(const ValueKey('tab-bar-resize-handle')),
      const Offset(60, 0),
    );
    await tester.pump();

    expect(
      tester.getSize(find.byType(maidterm.TerminalView)),
      const Size(856, 640),
    );
    await tester.pumpAndSettle();
    expect(
      (await SharedPreferences.getInstance()).getDouble('terminal.tabBarWidth'),
      240.0,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(buildWorkspace());
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byType(maidterm.TerminalView)),
      const Size(856, 640),
    );
  });

  testWidgets('vertical tab bars still focus terminal input', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({'terminal.tabBarPosition': 'left'});

    await tester.pumpWidget(buildWorkspace());
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(TerminalWorkspacePage)),
    );
    final session = container
        .read(terminalWorkspaceProvider)
        .selectedTab!
        .session;
    final output = <Object>[];
    session.controller.onOutput = output.add;
    final terminal = find.byType(maidterm.TerminalView);
    final initialFocusWidgets = find.descendant(
      of: terminal,
      matching: find.byType(Focus),
    );
    expect(
      initialFocusWidgets.evaluate().any(
        (element) =>
            (element.widget as Focus).focusNode?.debugLabel ==
                'terminal-input' &&
            ((element.widget as Focus).focusNode?.hasFocus ?? false),
      ),
      isTrue,
    );
    await tester.tapAt(tester.getCenter(terminal));
    await tester.pump();

    final focusWidgets = find.descendant(
      of: terminal,
      matching: find.byType(Focus),
    );
    final focusedNodes = focusWidgets.evaluate().map(
      (element) => (element.widget as Focus).focusNode,
    );
    expect(
      focusedNodes.any(
        (node) =>
            node?.debugLabel == 'terminal-input' && (node?.hasFocus ?? false),
      ),
      isTrue,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    expect(output, isNotEmpty);
  });
  testWidgets('switching tabs restores terminal focus', (tester) async {
    SharedPreferences.setMockInitialValues({'terminal.tabBarPosition': 'left'});
    await tester.pumpWidget(buildWorkspace());
    await tester.pumpAndSettle();

    final page = find.byType(TerminalWorkspacePage);
    final container = ProviderScope.containerOf(tester.element(page));
    final notifier = container.read(terminalWorkspaceProvider.notifier);
    notifier.openTerminal();
    await tester.pumpAndSettle();
    final state = container.read(terminalWorkspaceProvider);
    notifier.selectTab(state.tabs.first.id);
    await tester.pumpAndSettle();

    final terminal = find.byType(maidterm.TerminalView);
    final focused = find
        .descendant(of: terminal, matching: find.byType(Focus))
        .evaluate()
        .map((element) => (element.widget as Focus).focusNode)
        .any(
          (node) =>
              node?.debugLabel == 'terminal-input' && (node?.hasFocus ?? false),
        );
    expect(focused, isTrue);
  });

  testWidgets('cursor focus follows the focused terminal pane', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(buildWorkspace());
    await tester.pumpAndSettle();
    final page = find.byType(TerminalWorkspacePage);
    final container = ProviderScope.containerOf(tester.element(page));
    container
        .read(terminalWorkspaceProvider.notifier)
        .split(SplitAxis.horizontal);
    await tester.pumpAndSettle();

    bool hasFocus(Finder view) => find
        .descendant(of: view, matching: find.byType(Focus))
        .evaluate()
        .map((element) => (element.widget as Focus).focusNode)
        .any(
          (node) =>
              node?.debugLabel == 'terminal-input' && (node?.hasFocus ?? false),
        );

    final terminals = find.byType(maidterm.TerminalView);
    await tester.tapAt(tester.getCenter(terminals.at(0)));
    await tester.pumpAndSettle();
    expect(hasFocus(terminals.at(0)), isTrue);
    expect(hasFocus(terminals.at(1)), isFalse);

    await tester.tapAt(tester.getCenter(terminals.at(1)));
    await tester.pump();
    expect(hasFocus(terminals.at(0)), isFalse);
    expect(hasFocus(terminals.at(1)), isTrue);
  });
  testWidgets('ignores transparent background in full-screen mode', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'terminal.transparentBackground': true,
    });
    await tester.pumpWidget(buildWorkspace());
    await tester.pumpAndSettle();

    maidterm.TerminalView currentTerminal() => tester
        .widget<maidterm.TerminalView>(find.byType(maidterm.TerminalView));
    final page = find.byType(TerminalWorkspacePage);
    final container = ProviderScope.containerOf(tester.element(page));
    final session = container
        .read(terminalWorkspaceProvider)
        .selectedTab!
        .session;

    expect(currentTerminal().theme?.backgroundOpacity, 0);
    expect(
      tester
          .widget<ColoredBox>(
            find.byKey(const ValueKey('terminal-pane-backdrop')),
          )
          .color,
      Colors.transparent,
    );

    session.controller.write(utf8.encode('\x1b[?1049h'));
    await tester.pump();

    expect(currentTerminal().theme?.backgroundOpacity, 1);
    expect(
      tester
          .widget<ColoredBox>(
            find.byKey(const ValueKey('terminal-pane-backdrop')),
          )
          .color,
      const Color(0xFFFAFAFA),
    );
  });

  testWidgets('starts with one terminal filling the window', (tester) async {
    await tester.pumpWidget(buildWorkspace());
    await tester.pump();

    expect(find.byType(maidterm.TerminalView), findsOneWidget);
  });

  testWidgets('new tab adds a tab and switches to it', (tester) async {
    await tester.pumpWidget(buildWorkspace());
    await tester.pump();

    final notifier = ProviderScope.containerOf(
      tester.element(find.byType(TerminalWorkspacePage)),
    ).read(terminalWorkspaceProvider.notifier);
    notifier.openTerminal();
    await tester.pump();

    final state = ProviderScope.containerOf(
      tester.element(find.byType(TerminalWorkspacePage)),
    ).read(terminalWorkspaceProvider);
    expect(state.tabs.length, 2);
    expect(state.selectedTab?.id, state.tabs.last.id);
  });

  testWidgets('split creates two panes with two terminals', (tester) async {
    await tester.pumpWidget(buildWorkspace());
    await tester.pump();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(TerminalWorkspacePage)),
    );
    container
        .read(terminalWorkspaceProvider.notifier)
        .split(SplitAxis.horizontal);
    await tester.pump();

    final state = container.read(terminalWorkspaceProvider);
    expect(state.layout?.isSplit, isTrue);
    expect(state.panes.length, 2);
    expect(state.tabs.length, 2);
    expect(find.byType(maidterm.TerminalView), findsNWidgets(2));
    expect(find.byKey(const ValueKey('workspace-tab-bar')), findsOneWidget);
  });
  testWidgets('closing the last tab shows the empty state', (tester) async {
    await tester.pumpWidget(buildWorkspace());
    await tester.pump();

    final notifier = ProviderScope.containerOf(
      tester.element(find.byType(TerminalWorkspacePage)),
    ).read(terminalWorkspaceProvider.notifier);
    notifier.closeTab(notifier.state.selectedTab!.id);
    await tester.pump();

    expect(find.byType(maidterm.TerminalView), findsNothing);
    expect(find.text('New Terminal'), findsOneWidget);
  });
}
