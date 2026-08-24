import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:maidterm/maidterm.dart' as maidterm;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:maidterm_app/shell/local_shell_session.dart';
import 'package:maidterm_app/workspace/session_layout.dart';
import 'package:maidterm_app/workspace/terminal_workspace.dart';
import 'package:maidterm_app/settings/background_image.dart';
import 'package:maidterm_app/workspace/terminal_workspace_page.dart';

void main() {
  /// ProviderScope with sessions that never spawn a pty (plugin frameworks
  /// are not linked under `flutter test`).
  Widget buildWorkspace() {
    return ProviderScope(
      overrides: [
        localShellSessionFactoryProvider.overrideWithValue(
          ({String? workingDirectory}) => LocalShellSession(
            workingDirectory: workingDirectory,
            autoStart: false,
          ),
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

  testWidgets('keeps margins until a TUI paints an almost full grid', (
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
    expect(currentTerminal().padding, const EdgeInsets.fromLTRB(1, 2, 3, 4));

    // A TUI canvas fill (explicit background across the grid) switches the
    // pane into its full-screen margins.
    session.session.setVisualFullScreen(true);
    await tester.pump();
    expect(currentTerminal().padding, const EdgeInsets.fromLTRB(5, 6, 7, 8));

    session.controller.write(utf8.encode('\x1b[?1049l'));
    session.session.setVisualFullScreen(false);
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
      const Size(1080, 580),
    );
  });
  testWidgets('terminal pane backing fills the full pane', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(buildWorkspace());
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byKey(const ValueKey('terminal-pane-backdrop'))),
      const Size(1080, 580),
    );
  });

  testWidgets('positions the tab bar from the persisted setting', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1100, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const expectedSizes = {
      'top': Size(1080, 580),
      'bottom': Size(1080, 580),
      'left': Size(900, 620),
      'right': Size(900, 620),
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

  testWidgets('rounds the workspace ground beside a vertical tab bar', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1100, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final clip = find.byKey(const ValueKey('workspace-ground-clip'));
    // Mirrors MaidKit's rounded content sheet: a vertical tab bar clips the
    // ground corner it sits beside; a horizontal bar leaves the ground
    // square against the title bar.
    const cases = {
      'left': BorderRadius.only(topLeft: Radius.circular(12)),
      'right': BorderRadius.only(topRight: Radius.circular(12)),
      'top': null,
      'bottom': null,
    };
    for (final entry in cases.entries) {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      SharedPreferences.setMockInitialValues({
        'terminal.tabBarPosition': entry.key,
      });
      await tester.pumpWidget(buildWorkspace());
      await tester.pumpAndSettle();

      final corner = entry.value;
      if (corner == null) {
        expect(clip, findsNothing, reason: '${entry.key} tab bar');
      } else {
        expect(clip, findsOneWidget, reason: '${entry.key} tab bar');
        final border = tester.widget<ClipRRect>(clip).borderRadius as BorderRadius;
        // BorderRadius does not compare by value; inspect each corner.
        expect(border.topLeft.x, corner.topLeft.x,
            reason: '${entry.key} top-left');
        expect(border.topRight.x, corner.topRight.x,
            reason: '${entry.key} top-right');
        expect(border.bottomLeft.x, 0, reason: '${entry.key} bottom-left');
        expect(border.bottomRight.x, 0, reason: '${entry.key} bottom-right');
      }
    }
  });

  testWidgets('keeps top tab bar expanded at narrow widths', (tester) async {
    await tester.binding.setSurfaceSize(const Size(560, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({'terminal.tabBarPosition': 'top'});

    await tester.pumpWidget(buildWorkspace());
    await tester.pumpAndSettle();

    // The top bar never compacts: every chip keeps its close button.
    expect(
      tester.getSize(find.byKey(const ValueKey('workspace-tab-bar'))).height,
      40,
    );
    expect(find.byTooltip('Close tab'), findsWidgets);
    expect(find.byTooltip('Collapse tab bar'), findsNothing);
  });

  testWidgets('compacts the vertical tab bar while resizing', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({
      'terminal.tabBarPosition': 'left',
      'terminal.tabBarWidth': 240.0,
    });

    await tester.pumpWidget(buildWorkspace());
    await tester.pumpAndSettle();

    final tabBar = find.byKey(const ValueKey('workspace-tab-bar'));
    final container = ProviderScope.containerOf(
      tester.element(find.byType(TerminalWorkspacePage)),
    );
    expect(tester.getSize(tabBar), const Size(240, 640));
    // Non-compact: chips render titles with close buttons.
    expect(find.byTooltip('Close tab'), findsWidgets);

    await tester.drag(
      find.byKey(const ValueKey('tab-bar-resize-handle')),
      const Offset(-500, 0),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(tester.getSize(tabBar), const Size(48, 640));
    // Compact: chips collapse to icon-only, close buttons hidden.
    expect(find.byTooltip('Close tab'), findsNothing);
    container.read(terminalWorkspaceProvider.notifier).openTerminal();
    await tester.pumpAndSettle();

    final tabs = container.read(terminalWorkspaceProvider).tabs;
    final firstTabRect = tester.getRect(
      find.byKey(ValueKey('pane-tab-${tabs.first.focusedPane!.tab.id}')),
    );
    final secondTabRect = tester.getRect(
      find.byKey(ValueKey('pane-tab-${tabs.last.focusedPane!.tab.id}')),
    );
    expect(firstTabRect.top, 10);
    expect(secondTabRect.top - firstTabRect.bottom, 4);

    await tester.drag(
      find.byKey(const ValueKey('tab-bar-resize-handle')),
      const Offset(220, 0),
    );
    await tester.pumpAndSettle();

    expect(tester.getSize(tabBar).width, greaterThan(48));
    expect(find.byTooltip('Close tab'), findsWidgets);
  });

  testWidgets('resizes the vertical tab bar sidebar', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({'terminal.tabBarPosition': 'left'});

    await tester.pumpWidget(buildWorkspace());
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byType(maidterm.TerminalView)),
      const Size(900, 620),
    );

    await tester.drag(
      find.byKey(const ValueKey('tab-bar-resize-handle')),
      const Offset(60, 0),
    );
    await tester.pump();

    expect(
      tester.getSize(find.byType(maidterm.TerminalView)),
      const Size(840, 620),
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
      const Size(840, 620),
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

    final state = container.read(terminalWorkspaceProvider);
    final panes = state.panes.values.toList();
    final pane1 = panes.first;
    final pane2 = panes.last;

    final terminals = find.byType(maidterm.TerminalView);
    await tester.tapAt(tester.getCenter(terminals.at(0)));
    await tester.pumpAndSettle();
    expect(hasFocus(terminals.at(0)), isTrue);
    expect(hasFocus(terminals.at(1)), isFalse);
    // The controller binding drives cursor rendering; it must agree with
    // the focus widget or the unfocused cursor never repaints.
    expect(pane1.tab.session.controller.hasFocus, isTrue);
    expect(pane2.tab.session.controller.hasFocus, isFalse);

    await tester.tapAt(tester.getCenter(terminals.at(1)));
    await tester.pump();
    expect(hasFocus(terminals.at(0)), isFalse);
    expect(hasFocus(terminals.at(1)), isTrue);
    expect(pane1.tab.session.controller.hasFocus, isFalse);
    expect(pane2.tab.session.controller.hasFocus, isTrue);
  });
  testWidgets('keeps transparent background until a TUI paints its canvas', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'terminal.transparentBackground': true,
    });
    await tester.pumpWidget(buildWorkspace());
    await tester.pumpAndSettle();

    maidterm.TerminalView currentTerminal() => tester
        .widget<maidterm.TerminalView>(find.byType(maidterm.TerminalView));
    ColoredBox backdrop() => tester.widget<ColoredBox>(
      find.byKey(const ValueKey('terminal-pane-backdrop')),
    );
    final page = find.byType(TerminalWorkspacePage);
    final container = ProviderScope.containerOf(tester.element(page));
    final session = container
        .read(terminalWorkspaceProvider)
        .selectedTab!
        .session;

    expect(currentTerminal().theme?.backgroundOpacity, 0);
    expect(backdrop().color, Colors.transparent);

    session.controller.write(utf8.encode('\x1b[?1049h'));
    await tester.pump();
    expect(currentTerminal().theme?.backgroundOpacity, 0);
    expect(backdrop().color, Colors.transparent);

    // A TUI canvas fill forces an opaque terminal surface.
    session.session.setVisualFullScreen(true);
    await tester.pump();
    expect(currentTerminal().theme?.backgroundOpacity, 1);
    expect(backdrop().color, const Color(0xFFFAFAFA));
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

  testWidgets('new tabs inherit the selected tab working directory', (
    tester,
  ) async {
    final workingDirectories = <String?>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localShellSessionFactoryProvider.overrideWithValue(({
            String? workingDirectory,
          }) {
            workingDirectories.add(workingDirectory);
            return LocalShellSession(
              workingDirectory: workingDirectory ?? '/tmp/project',
              autoStart: false,
            );
          }),
        ],
        child: const MaterialApp(home: TerminalWorkspacePage()),
      ),
    );
    await tester.pump();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(TerminalWorkspacePage)),
    );
    container.read(terminalWorkspaceProvider.notifier).openTerminal();

    expect(workingDirectories, [null, '/tmp/project']);
  });

  testWidgets('split keeps panes inside the active top-level tab', (
    tester,
  ) async {
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
    expect(state.tabs.length, 1);
    expect(find.byType(maidterm.TerminalView), findsNWidgets(2));
    expect(find.byKey(const ValueKey('workspace-tab-bar')), findsOneWidget);
    for (final pane in state.panes.values) {
      expect(find.byKey(ValueKey('pane-tab-${pane.tab.id}')), findsOneWidget);
    }
  });

  testWidgets('vertical tab entry stacks pane tabs without overflow', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'terminal.tabBarPosition': 'left'});
    await tester.pumpWidget(buildWorkspace());
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(TerminalWorkspacePage)),
    );
    container
        .read(terminalWorkspaceProvider.notifier)
        .split(SplitAxis.horizontal);
    await tester.pumpAndSettle();

    final state = container.read(terminalWorkspaceProvider);
    expect(state.tabs, hasLength(1));
    expect(state.panes, hasLength(2));
    for (final pane in state.panes.values) {
      expect(find.byKey(ValueKey('pane-tab-${pane.tab.id}')), findsOneWidget);
    }
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

  // 1x1 transparent PNG: a real decodable file for the image provider.
  const transparentPng = <int>[
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
    0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
    0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x62, 0x00, 0x01, 0x00, 0x00,
    0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
    0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
  ];

  Widget buildWorkspaceWithImage(File imageFile) {
    return ProviderScope(
      overrides: [
        localShellSessionFactoryProvider.overrideWithValue(
          ({String? workingDirectory}) => LocalShellSession(
            workingDirectory: workingDirectory,
            autoStart: false,
          ),
        ),
        maidTermBackgroundImageProvider.overrideWith((ref) async => imageFile),
      ],
      child: const MaterialApp(home: TerminalWorkspacePage()),
    );
  }

  int imageLayers() => find
      .byWidgetPredicate(
        (widget) =>
            widget is DecoratedBox &&
            (widget.decoration as BoxDecoration?)?.image != null,
      )
      .evaluate()
      .length;

  testWidgets('background image fills the pane layout once, not chrome', (
    tester,
  ) async {
    final imageFile = File(
      '${Directory.systemTemp.path}/maidterm_bg_test.png',
    );
    await tester.binding.setSurfaceSize(const Size(1100, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});
    await tester.runAsync(() => imageFile.writeAsBytes(transparentPng));
    addTearDown(() => tester.runAsync(() => imageFile.delete()));

    await tester.pumpWidget(buildWorkspaceWithImage(imageFile));
    await tester.pumpAndSettle();

    // Exactly one image layer, on the ground that spans the whole layout.
    expect(imageLayers(), 1);
    final ground = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('workspace-ground')),
    );
    final groundImage = (ground.decoration as BoxDecoration).image!;
    expect(groundImage.image, isA<FileImage>());
    expect(groundImage.fit, BoxFit.cover);
    expect(
      tester.getSize(find.byKey(const ValueKey('workspace-ground'))),
      const Size(1100, 600),
    );

    // The terminal stays transparent so the image shows through, and the
    // pane chrome turns translucent over it.
    final terminal = tester.widget<maidterm.TerminalView>(
      find.byType(maidterm.TerminalView),
    );
    expect(terminal.theme?.backgroundOpacity, 0);
    expect(
      tester
          .widget<ColoredBox>(
            find.byKey(const ValueKey('terminal-pane-backdrop')),
          )
          .color,
      Colors.transparent,
    );
    final chrome = tester.widget<Container>(
      find
          .ancestor(
            of: find.byKey(const ValueKey('terminal-pane-backdrop')),
            matching: find.byType(Container),
          )
          .first,
    );
    final chromeColor = (chrome.decoration! as BoxDecoration).color!;
    expect(chromeColor.a, lessThan(1.0));

    // The tab bar stays solid: the image never leaks into chrome.
    final tabBar = tester.widget<Material>(
      find.byKey(const ValueKey('workspace-tab-bar')),
    );
    expect(tabBar.color!.a, 1.0);
  });

  testWidgets('split panes share one background image', (tester) async {
    final imageFile = File(
      '${Directory.systemTemp.path}/maidterm_bg_split_test.png',
    );
    await tester.runAsync(() => imageFile.writeAsBytes(transparentPng));
    addTearDown(() => tester.runAsync(() => imageFile.delete()));

    await tester.pumpWidget(buildWorkspaceWithImage(imageFile));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(TerminalWorkspacePage)),
    );
    container
        .read(terminalWorkspaceProvider.notifier)
        .split(SplitAxis.horizontal);
    await tester.pumpAndSettle();

    // Still exactly one image across both panes — no per-pane copies.
    expect(imageLayers(), 1);
    expect(find.byType(maidterm.TerminalView), findsNWidgets(2));
    for (final view in tester.widgetList<maidterm.TerminalView>(
      find.byType(maidterm.TerminalView),
    )) {
      expect(view.theme?.backgroundOpacity, 0);
    }
    for (final backdrop in tester.widgetList<ColoredBox>(
      find.byKey(const ValueKey('terminal-pane-backdrop')),
    )) {
      expect(backdrop.color, Colors.transparent);
    }
  });

  testWidgets('disabled background image keeps chrome opaque', (tester) async {
    SharedPreferences.setMockInitialValues({
      'app.backgroundImageEnabled': false,
    });
    final imageFile = File(
      '${Directory.systemTemp.path}/maidterm_bg_off_test.png',
    );
    await tester.runAsync(() => imageFile.writeAsBytes(transparentPng));
    addTearDown(() => tester.runAsync(() => imageFile.delete()));

    await tester.pumpWidget(buildWorkspaceWithImage(imageFile));
    await tester.pumpAndSettle();

    expect(imageLayers(), 0);
    final terminal = tester.widget<maidterm.TerminalView>(
      find.byType(maidterm.TerminalView),
    );
    expect(terminal.theme?.backgroundOpacity, 1);
    expect(
      tester
          .widget<ColoredBox>(
            find.byKey(const ValueKey('terminal-pane-backdrop')),
          )
          .color,
      const Color(0xFFFAFAFA),
    );
  });

  Widget buildWorkspaceWithRunningPrograms() {
    return ProviderScope(
      overrides: [
        localShellSessionFactoryProvider.overrideWithValue(
          ({String? workingDirectory}) => LocalShellSession(
            workingDirectory: workingDirectory,
            autoStart: false,
            runningPrograms: () => true,
          ),
        ),
      ],
      child: MaterialApp(
        navigatorKey: _confirmNavigatorKey,
        home: const TerminalWorkspacePage(),
      ),
    );
  }

  testWidgets('closing a pane with running programs asks for confirmation', (
    tester,
  ) async {
    IslandUIFoundation.configureNavigator(_confirmNavigatorKey);
    await tester.pumpWidget(buildWorkspaceWithRunningPrograms());
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(TerminalWorkspacePage)),
    );
    container
        .read(terminalWorkspaceProvider.notifier)
        .split(SplitAxis.horizontal);
    await tester.pumpAndSettle();

    final secondPaneId = container
        .read(terminalWorkspaceProvider)
        .panes
        .values
        .last
        .id;
    container.read(terminalWorkspaceProvider.notifier).closePane(secondPaneId);
    await tester.pumpAndSettle();

    // The island_ui_foundation attention modal asks before closing.
    expect(find.text('Close pane?'), findsOneWidget);

    // Cancelling keeps the pane.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(container.read(terminalWorkspaceProvider).panes, hasLength(2));

    // Confirming closes it.
    container.read(terminalWorkspaceProvider.notifier).closePane(secondPaneId);
    await tester.pumpAndSettle();
    expect(find.text('Close pane?'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(container.read(terminalWorkspaceProvider).panes, hasLength(1));
  });

  testWidgets('closing a tab with running panes asks for confirmation', (
    tester,
  ) async {
    IslandUIFoundation.configureNavigator(_confirmNavigatorKey);
    await tester.pumpWidget(buildWorkspaceWithRunningPrograms());
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(TerminalWorkspacePage)),
    );
    container
        .read(terminalWorkspaceProvider.notifier)
        .split(SplitAxis.horizontal);
    await tester.pumpAndSettle();

    container
        .read(terminalWorkspaceProvider.notifier)
        .closeTab(container.read(terminalWorkspaceProvider).selectedTabId!);
    await tester.pumpAndSettle();

    expect(find.text('Close panes?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(container.read(terminalWorkspaceProvider).tabs, hasLength(1));
    expect(container.read(terminalWorkspaceProvider).panes, hasLength(2));

    container
        .read(terminalWorkspaceProvider.notifier)
        .closeTab(container.read(terminalWorkspaceProvider).selectedTabId!);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(container.read(terminalWorkspaceProvider).tabs, isEmpty);
  });
}

final _confirmNavigatorKey = GlobalKey<NavigatorState>();
