import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart' hide GlobalMaterialLocalizations;
import 'package:material_ui/material_ui.dart'
    as material_ui
    show GlobalMaterialLocalizations;

import 'settings/background_image.dart';
import 'settings/settings_page.dart';
import 'settings/terminal_settings.dart';
import 'workspace/terminal_workspace.dart';
import 'workspace/session_layout.dart';

import 'workspace/terminal_workspace_page.dart';
import 'theme.dart';

/// The window frame wraps the app's entire navigator, so EVERY page —
/// workspace, settings, future routes — renders inside the desktop title bar.
class MaidTermApp extends ConsumerStatefulWidget {
  const MaidTermApp({super.key});

  @override
  ConsumerState<MaidTermApp> createState() => _MaidTermAppState();
}

class _MaidTermAppState extends ConsumerState<MaidTermApp> {
  static const _menuChannel = MethodChannel('maidterm/menu');

  final _navigatorKey = GlobalKey<NavigatorState>();
  final _settingsOpen = ValueNotifier<bool>(false);

  @override
  void initState() {
    super.initState();
    _menuChannel.setMethodCallHandler(_handleMenuCall);
  }

  Future<void> _handleMenuCall(MethodCall call) async {
    switch (call.method) {
      case 'newTab':
        _openTerminal();
      case 'splitRight':
        _split(SplitAxis.horizontal);
      case 'splitBelow':
        _split(SplitAxis.vertical);
      case 'closeTab':
        _closeSelectedTab();
      case 'closePane':
        _closeFocusedPane();
    }
  }

  void _openTerminal() {
    ref.read(terminalWorkspaceProvider.notifier).openTerminal();
  }

  void _split(SplitAxis axis) {
    ref.read(terminalWorkspaceProvider.notifier).split(axis);
  }

  void _closeSelectedTab() {
    final workspace = ref.read(terminalWorkspaceProvider);
    final tabId = workspace.selectedTab?.id;
    if (tabId != null) {
      ref.read(terminalWorkspaceProvider.notifier).closeTab(tabId);
    }
  }

  void _closeFocusedPane() {
    final paneId = ref.read(terminalWorkspaceProvider).focusedPaneId;
    if (paneId != null) {
      ref.read(terminalWorkspaceProvider.notifier).closePane(paneId);
    }
  }

  void _openSettings() {
    _navigatorKey.currentState?.push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/settings'),
        builder: (_) => const SettingsPage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(terminalSettingsProvider).value;
    final themeMode = settings?.themeMode ?? ThemeMode.dark;
    final seedColor = settings?.seedColor ?? const Color(0xFF0F766E);

    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'MaidTerm',
      debugShowCheckedModeBanner: false,
      theme: createMaidTermTheme(Brightness.light, seedColor: seedColor),
      darkTheme: createMaidTermTheme(Brightness.dark, seedColor: seedColor),
      themeMode: themeMode,
      localizationsDelegates: [
        ...material_ui.GlobalMaterialLocalizations.delegates,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      navigatorObservers: [_SettingsTitleObserver(_settingsOpen)],
      // The frame sits above the navigator inside this builder: the whole
      // app (all routes) is its child, so the title bar never disappears.
      // ignore: deprecated_member_use
      builder: (context, child) => MaterialUiCompatibilityBridge(
        child: ValueListenableBuilder<bool>(
          valueListenable: _settingsOpen,
          builder: (context, settingsOpen, _) => MaidTermWindowScaffold(
            title: settingsOpen ? 'Settings' : 'MaidTerm',
            child: MaidTermAppBackground(child: child!),
          ),
        ),
      ),
      home: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.comma, meta: true): () =>
              _openSettings(),
          const SingleActivator(LogicalKeyboardKey.keyN, meta: true): () =>
              _openTerminal(),
          const SingleActivator(LogicalKeyboardKey.keyT, meta: true): () =>
              _openTerminal(),
          const SingleActivator(LogicalKeyboardKey.keyD, meta: true): () =>
              _split(SplitAxis.horizontal),
          const SingleActivator(
            LogicalKeyboardKey.keyD,
            meta: true,
            shift: true,
          ): () =>
              _split(SplitAxis.vertical),
          const SingleActivator(LogicalKeyboardKey.keyW, meta: true): () =>
              _closeSelectedTab(),
          const SingleActivator(
            LogicalKeyboardKey.keyW,
            meta: true,
            shift: true,
          ): () =>
              _closeFocusedPane(),
        },
        child: const TerminalWorkspacePage(),
      ),
    );
  }
}

/// Flips [settingsOpen] when the settings route is pushed/popped so the
/// window frame title reflects the current page.
class _SettingsTitleObserver extends NavigatorObserver {
  _SettingsTitleObserver(this._settingsOpen);

  final ValueNotifier<bool> _settingsOpen;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route.settings.name == '/settings') _settingsOpen.value = true;
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route.settings.name == '/settings') _settingsOpen.value = false;
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route.settings.name == '/settings') _settingsOpen.value = false;
  }
}
