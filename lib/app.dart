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
  final _settingsOpen = ValueNotifier<bool>(false);

  @override
  void dispose() {
    _settingsOpen.dispose();
    super.dispose();
  }

  void _openSettings(BuildContext context) {
    Navigator.of(context).push(
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
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.comma, meta: true): () =>
                _openSettings(context),
            const SingleActivator(LogicalKeyboardKey.keyN, meta: true): () =>
                ref.read(terminalWorkspaceProvider.notifier).openTerminal(),
          },
          child: ValueListenableBuilder<bool>(
            valueListenable: _settingsOpen,
            builder: (context, settingsOpen, _) => MaidTermWindowScaffold(
              title: settingsOpen ? 'Settings' : 'MaidTerm',
              child: MaidTermAppBackground(child: child!),
            ),
          ),
        ),
      ),
      home: const TerminalWorkspacePage(),
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
