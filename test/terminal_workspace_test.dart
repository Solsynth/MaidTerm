import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:maidterm/maidterm.dart' as maidterm;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:maidterm_app/shell/local_shell_session.dart';
import 'package:maidterm_app/workspace/session_layout.dart';
import 'package:maidterm_app/workspace/terminal_workspace.dart';
import 'package:maidterm_app/settings/background_image.dart';

import 'support/window_harness.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    EasyLocalization.logger.enableBuildModes = [];
  });

  testWidgets('applies persisted font settings to the startup terminal', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'terminal.fontFamily': 'Fira Code',
      'terminal.fontSize': 18.0,
    });

    await pumpWorkspaceWindow(tester);

    final terminal = tester.widget<maidterm.TerminalView>(
      find.byType(maidterm.TerminalView),
    );
    expect(terminal.theme?.fontFamily, 'Fira Code');
    expect(terminal.theme?.fontSize, 18.0);
  });

  testWidgets('shows output activity in the terminal tab icon', (tester) async {
    final host = await pumpWorkspaceWindow(tester);

    final session = host.focusedTerminal.session;

    expect(find.byIcon(Symbols.terminal), findsOneWidget);
    session.writeOutput(Uint8List.fromList(utf8.encode('output')));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.pump(const Duration(milliseconds: 150));
    session.writeOutput(Uint8List.fromList(utf8.encode('more output')));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byIcon(Symbols.terminal), findsOneWidget);
  });

  testWidgets('keeps margins until a TUI paints an almost full grid', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'terminal.normalPaneMargin': '{"left":1,"top":2,"right":3,"bottom":4}',
      'terminal.fullScreenPaneMargin':
          '{"left":5,"top":6,"right":7,"bottom":8}',
    });

    final host = await pumpWorkspaceWindow(tester);

    final session = host.focusedTerminal.session;
    maidterm.TerminalView currentTerminal() => tester
        .widget<maidterm.TerminalView>(find.byType(maidterm.TerminalView));

    expect(currentTerminal().padding, const EdgeInsets.fromLTRB(1, 2, 3, 4));

    session.controller.write(utf8.encode('\x1b[?1049h'));
    await tester.pump();
    expect(currentTerminal().padding, const EdgeInsets.fromLTRB(1, 2, 3, 4));

    // A TUI canvas fill (explicit background across the grid) switches the
    // pane into its full-screen margins.
    session.setVisualFullScreen(true);
    await tester.pump();
    expect(currentTerminal().padding, const EdgeInsets.fromLTRB(5, 6, 7, 8));

    session.controller.write(utf8.encode('\x1b[?1049l'));
    session.setVisualFullScreen(false);
    await tester.pump();
    expect(currentTerminal().padding, const EdgeInsets.fromLTRB(1, 2, 3, 4));
  });

  testWidgets('terminal surface fills fractional pane remainder', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1100, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpWorkspaceWindow(tester);

    expect(
      tester.getSize(find.byType(maidterm.TerminalView)),
      const Size(1080, 580),
    );
  });
  testWidgets('terminal pane backing fills the full pane', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpWorkspaceWindow(tester);

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
      await pumpWorkspaceWindow(tester);

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
    // Mirrors MaidKit's rounded content sheet: vertical tab bars round the
    // pane-side corners along the full edge they sit beside; a horizontal bar
    // leaves the ground square against the title bar and status bar.
    const cases = {
      'left': BorderRadius.only(
        topLeft: Radius.circular(12),
        bottomLeft: Radius.circular(12),
      ),
      'right': BorderRadius.only(
        topRight: Radius.circular(12),
        bottomRight: Radius.circular(12),
      ),
      'top': null,
      'bottom': null,
    };
    for (final entry in cases.entries) {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      SharedPreferences.setMockInitialValues({
        'terminal.tabBarPosition': entry.key,
      });
      await pumpWorkspaceWindow(tester);

      final corner = entry.value;
      if (corner == null) {
        expect(clip, findsNothing, reason: '${entry.key} tab bar');
      } else {
        expect(clip, findsOneWidget, reason: '${entry.key} tab bar');
        final border =
            tester.widget<ClipRRect>(clip).borderRadius as BorderRadius;
        // BorderRadius does not compare by value; inspect each corner.
        expect(
          border.topLeft.x,
          corner.topLeft.x,
          reason: '${entry.key} top-left',
        );
        expect(
          border.topRight.x,
          corner.topRight.x,
          reason: '${entry.key} top-right',
        );
        expect(
          border.bottomLeft.x,
          corner.bottomLeft.x,
          reason: '${entry.key} bottom-left',
        );
        expect(
          border.bottomRight.x,
          corner.bottomRight.x,
          reason: '${entry.key} bottom-right',
        );
      }
    }
  });

  testWidgets('keeps top tab bar expanded at narrow widths', (tester) async {
    await tester.binding.setSurfaceSize(const Size(560, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({'terminal.tabBarPosition': 'top'});

    await pumpWorkspaceWindow(tester);

    // The top bar never compacts: every chip keeps its close button.
    expect(
      tester.getSize(find.byKey(const ValueKey('workspace-tab-bar'))).height,
      40,
    );
    expect(find.byTooltip('workspaceCloseTab'.tr()), findsWidgets);
    expect(find.byTooltip('Collapse tab bar'), findsNothing);
  });

  testWidgets('compacts the vertical tab bar while resizing', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({
      'terminal.tabBarPosition': 'left',
      'terminal.tabBarWidth': 240.0,
    });

    final host = await pumpWorkspaceWindow(tester);

    final tabBar = find.byKey(const ValueKey('workspace-tab-bar'));
    expect(tester.getSize(tabBar), const Size(240, 640));
    // Non-compact: chips render titles with close buttons.
    expect(find.byTooltip('workspaceCloseTab'.tr()), findsWidgets);

    await tester.drag(
      find.byKey(const ValueKey('tab-bar-resize-handle')),
      const Offset(-500, 0),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(tester.getSize(tabBar), const Size(48, 640));
    // Compact: chips collapse to icon-only, close buttons hidden.
    expect(find.byTooltip('workspaceCloseTab'.tr()), findsNothing);
    host.notifier.openTerminal();
    await tester.pumpAndSettle();

    final tabs = host.tabs;
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
    expect(find.byTooltip('workspaceCloseTab'.tr()), findsWidgets);
  });

  testWidgets('resizes the vertical tab bar sidebar', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({'terminal.tabBarPosition': 'left'});

    await pumpWorkspaceWindow(tester);
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
    await pumpWorkspaceWindow(tester);
    expect(
      tester.getSize(find.byType(maidterm.TerminalView)),
      const Size(840, 620),
    );
  });

  testWidgets('vertical tab bars still focus terminal input', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({'terminal.tabBarPosition': 'left'});

    final host = await pumpWorkspaceWindow(tester);
    final session = host.focusedTerminal.session;
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
    final host = await pumpWorkspaceWindow(tester);

    host.notifier.openTerminal();
    await tester.pumpAndSettle();
    host.notifier.selectTab(host.tabs.first.id);
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

    final host = await pumpWorkspaceWindow(tester);
    host.notifier.split(SplitAxis.horizontal);
    await tester.pumpAndSettle();

    bool hasFocus(Finder view) => find
        .descendant(of: view, matching: find.byType(Focus))
        .evaluate()
        .map((element) => (element.widget as Focus).focusNode)
        .any(
          (node) =>
              node?.debugLabel == 'terminal-input' && (node?.hasFocus ?? false),
        );

    final panes = host.state.panes.values.toList();
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
    final host = await pumpWorkspaceWindow(tester);

    maidterm.TerminalView currentTerminal() => tester
        .widget<maidterm.TerminalView>(find.byType(maidterm.TerminalView));
    ColoredBox backdrop() => tester.widget<ColoredBox>(
      find.byKey(const ValueKey('terminal-pane-backdrop')),
    );
    final session = host.focusedTerminal.session;

    expect(currentTerminal().theme?.backgroundOpacity, 0);
    expect(backdrop().color, Colors.transparent);

    session.controller.write(utf8.encode('\x1b[?1049h'));
    await tester.pump();
    expect(currentTerminal().theme?.backgroundOpacity, 0);
    expect(backdrop().color, Colors.transparent);

    // A TUI canvas fill forces an opaque terminal surface.
    session.setVisualFullScreen(true);
    await tester.pump();
    expect(currentTerminal().theme?.backgroundOpacity, 1);
    expect(backdrop().color, const Color(0xFFFAFAFA));
  });

  testWidgets('starts with one terminal filling the window', (tester) async {
    await pumpWorkspaceWindow(tester);

    expect(find.byType(maidterm.TerminalView), findsOneWidget);
  });

  testWidgets('new tab adds a tab and switches to it', (tester) async {
    final host = await pumpWorkspaceWindow(tester);

    host.notifier.openTerminal();
    await tester.pump();

    final state = host.state;
    expect(state.tabs.length, 2);
    expect(state.selectedTab?.id, state.tabs.last.id);
  });

  testWidgets('new tabs inherit the selected tab working directory', (
    tester,
  ) async {
    final host = await pumpWorkspaceWindow(
      tester,
      workingDirectory: '/tmp/project',
    );

    host.notifier.openTerminal();

    // The second tab inherits the first tab's directory instead of the
    // factory default.
    expect(
      host.tabs.map((tab) => tab.focusedPane!.tab.session.workingDirectory),
      ['/tmp/project', '/tmp/project'],
    );
  });

  testWidgets('split keeps panes inside the active top-level tab', (
    tester,
  ) async {
    final host = await pumpWorkspaceWindow(tester);

    host.notifier.split(SplitAxis.horizontal);
    await tester.pump();

    final state = host.state;
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
    final host = await pumpWorkspaceWindow(tester);

    host.notifier.split(SplitAxis.horizontal);
    await tester.pumpAndSettle();

    final state = host.state;
    expect(state.tabs, hasLength(1));
    expect(state.panes, hasLength(2));
    for (final pane in state.panes.values) {
      expect(find.byKey(ValueKey('pane-tab-${pane.tab.id}')), findsOneWidget);
    }
  });
  testWidgets('closing the last tab shows the empty state', (tester) async {
    final host = await pumpWorkspaceWindow(tester);

    host.notifier.closeTab(host.state.selectedTab!.id);
    await tester.pumpAndSettle();

    expect(find.byType(maidterm.TerminalView), findsNothing);
    expect(find.text('workspaceNewTerminal'.tr()), findsOneWidget);
  });

  // 1x1 transparent PNG: a real decodable file for the image provider.
  const transparentPng = <int>[
    0x89,
    0x50,
    0x4E,
    0x47,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
    0x00,
    0x00,
    0x00,
    0x0D,
    0x49,
    0x48,
    0x44,
    0x52,
    0x00,
    0x00,
    0x00,
    0x01,
    0x00,
    0x00,
    0x00,
    0x01,
    0x08,
    0x06,
    0x00,
    0x00,
    0x00,
    0x1F,
    0x15,
    0xC4,
    0x89,
    0x00,
    0x00,
    0x00,
    0x0D,
    0x49,
    0x44,
    0x41,
    0x54,
    0x78,
    0x9C,
    0x62,
    0x00,
    0x01,
    0x00,
    0x00,
    0x05,
    0x00,
    0x01,
    0x0D,
    0x0A,
    0x2D,
    0xB4,
    0x00,
    0x00,
    0x00,
    0x00,
    0x49,
    0x45,
    0x4E,
    0x44,
    0xAE,
    0x42,
    0x60,
    0x82,
  ];

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
    final imageFile = File('${Directory.systemTemp.path}/maidterm_bg_test.png');
    await tester.binding.setSurfaceSize(const Size(1100, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});
    await tester.runAsync(() => imageFile.writeAsBytes(transparentPng));
    addTearDown(() => tester.runAsync(() => imageFile.delete()));

    await pumpWorkspaceWindow(
      tester,
      overrides: [
        maidTermBackgroundImageProvider.overrideWith((ref) async => imageFile),
      ],
    );

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

    // The tab bar paints transparently so the frame's uniform backdrop
    // shows through; the pane-layout image never leaks into it.
    final tabBar = tester.widget<Material>(
      find.byKey(const ValueKey('workspace-tab-bar')),
    );
    expect(tabBar.color, Colors.transparent);
  });

  testWidgets('split panes share one background image', (tester) async {
    final imageFile = File(
      '${Directory.systemTemp.path}/maidterm_bg_split_test.png',
    );
    await tester.runAsync(() => imageFile.writeAsBytes(transparentPng));
    addTearDown(() => tester.runAsync(() => imageFile.delete()));

    final host = await pumpWorkspaceWindow(
      tester,
      overrides: [
        maidTermBackgroundImageProvider.overrideWith((ref) async => imageFile),
      ],
    );

    host.notifier.split(SplitAxis.horizontal);
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

    await pumpWorkspaceWindow(
      tester,
      overrides: [
        maidTermBackgroundImageProvider.overrideWith((ref) async => imageFile),
      ],
    );

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

  testWidgets('closing a pane with running programs asks for confirmation', (
    tester,
  ) async {
    // The attention modal resolves its navigator from the mounted window app.
    final host = await _pumpBusyWindow(tester);
    final secondPaneId = host.state.panes.values.last.id;

    host.notifier.closePane(secondPaneId);
    await tester.pumpAndSettle();

    // The island_ui_foundation attention modal asks before closing.
    expect(find.text('closeConfirmTitleSingle'.tr()), findsOneWidget);

    // Cancelling keeps the pane.
    await tester.tap(find.text('commonCancel'.tr()));
    await tester.pumpAndSettle();
    expect(host.state.panes, hasLength(2));

    // Confirming closes it.
    host.notifier.closePane(secondPaneId);
    await tester.pumpAndSettle();
    expect(find.text('closeConfirmTitleSingle'.tr()), findsOneWidget);
    await tester.tap(find.text('commonClose'.tr()));
    await tester.pumpAndSettle();
    expect(host.state.panes, hasLength(1));
  });

  testWidgets('closing a tab with running panes asks for confirmation', (
    tester,
  ) async {
    // See the pane test: the modal needs the window app's navigator.
    final host = await _pumpBusyWindow(tester);

    host.notifier.closeTab(host.state.selectedTabId!);
    await tester.pumpAndSettle();

    expect(find.text('closeConfirmTitleMany'.tr()), findsOneWidget);
    await tester.tap(find.text('commonCancel'.tr()));
    await tester.pumpAndSettle();
    expect(host.state.tabs, hasLength(1));
    expect(host.state.panes, hasLength(2));

    host.notifier.closeTab(host.state.selectedTabId!);
    await tester.pumpAndSettle();
    await tester.tap(find.text('commonClose'.tr()));
    await tester.pumpAndSettle();
    expect(host.state.tabs, isEmpty);
  });
}

/// Pumps the window app with a single two-pane tab whose sessions always
/// report a running program.
///
/// Busy sessions need a session factory the shared harness cannot override,
/// so the tab is built here and adopted through the in-process attach path.
/// The full window app is mounted because the attention modal resolves its
/// navigator from it.
Future<WorkspaceHost> _pumpBusyWindow(WidgetTester tester) async {
  final host = await pumpAppWindow(tester);

  // Drop the harness's idle tab, then adopt a busy split tab.
  host.notifier.closeTab(host.state.selectedTab!.id);
  await tester.pumpAndSettle();
  host.notifier.attachTab(_busySplitTab());
  await tester.pumpAndSettle();
  return host;
}

TerminalWorkspaceTab _busySplitTab() {
  LocalShellSession busySession() => LocalShellSession(
    workingDirectory: null,
    autoStart: false,
    runningPrograms: () => true,
  );
  const firstPaneId = 'busy-pane-1';
  const secondPaneId = 'busy-pane-2';
  return TerminalWorkspaceTab(
    id: 'busy-group',
    panes: {
      firstPaneId: TerminalPane(
        id: firstPaneId,
        tab: TerminalTab(id: 'busy-tab-1', session: busySession()),
      ),
      secondPaneId: TerminalPane(
        id: secondPaneId,
        tab: TerminalTab(id: 'busy-tab-2', session: busySession()),
      ),
    },
    layout: splitPane(
      layout: const PaneLayoutLeaf(firstPaneId),
      focusedPaneId: firstPaneId,
      newPaneId: secondPaneId,
      axis: SplitAxis.horizontal,
      splitId: 'busy-split',
    ),
    focusedPaneId: firstPaneId,
  );
}
