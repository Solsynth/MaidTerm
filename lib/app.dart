import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:material_symbols_icons/material_symbols_icons.dart';
import 'package:material_ui/material_ui.dart' hide GlobalMaterialLocalizations;
import 'package:material_ui/material_ui.dart'
    as material_ui
    show GlobalMaterialLocalizations;

import 'multi_window.dart';
import 'settings/settings_page.dart';
import 'settings/terminal_settings.dart';
import 'workspace/session_layout.dart';
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
  static const _menuChannel = MethodChannel('maidterm/menu');

  final _navigatorKey = GlobalKey<NavigatorState>();
  final _settingsOpen = ValueNotifier<bool>(false);

  @override
  void initState() {
    super.initState();
    _menuChannel.setMethodCallHandler(_handleMenuCall);
    // The attention-modal alert resolves its navigator from this key.
    IslandUIFoundation.configureNavigator(_navigatorKey);
  }

  Future<void> _handleMenuCall(MethodCall call) async {
    switch (call.method) {
      case 'newTab':
        _openTerminal();
      case 'newWindow':
        _openNewWindow();
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

  void _selectNextTab() {
    ref.read(terminalWorkspaceProvider.notifier).selectNextTab();
  }

  void _selectPaneNumber(int number) {
    ref.read(terminalWorkspaceProvider.notifier).selectPaneNumber(number);
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

  void _openNewWindow() {
    ref.read(multiWindowCoordinatorProvider).openNewWindow();
  }

  void _openSettings() {
    _navigatorKey.currentState?.push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/settings'),
        builder: (_) => const SettingsPage(),
      ),
    );
  }

  KeyEventResult _handleFocusedTerminalKeyEvent(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    if (!keyboard.isMetaPressed ||
        keyboard.isControlPressed ||
        keyboard.isAltPressed) {
      return KeyEventResult.ignored;
    }

    VoidCallback? action;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.comma when !keyboard.isShiftPressed:
        action = _openSettings;
      case LogicalKeyboardKey.keyN when !keyboard.isShiftPressed:
        action = _openNewWindow;
      case LogicalKeyboardKey.keyT when !keyboard.isShiftPressed:
        action = _openTerminal;
      case LogicalKeyboardKey.keyD:
        action = keyboard.isShiftPressed
            ? () => _split(SplitAxis.vertical)
            : () => _split(SplitAxis.horizontal);
      case LogicalKeyboardKey.keyW:
        action = keyboard.isShiftPressed
            ? _closeSelectedTab
            : _closeFocusedPane;
      default:
        return KeyEventResult.ignored;
    }
    if (event is KeyDownEvent) action();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(terminalSettingsProvider).value;
    final themeMode = settings?.themeMode ?? ThemeMode.dark;
    final seedColor = settings?.seedColor ?? const Color(0xFF0F766E);

    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'title'.tr(),
      debugShowCheckedModeBanner: false,
      theme: createMaidTermTheme(Brightness.light, seedColor: seedColor),
      darkTheme: createMaidTermTheme(Brightness.dark, seedColor: seedColor),
      themeMode: themeMode,
      localizationsDelegates: [
        ...context.localizationDelegates,
        ...material_ui.GlobalMaterialLocalizations.delegates,
      ],
      locale: context.locale,
      supportedLocales: context.supportedLocales,
      navigatorObservers: [_SettingsTitleObserver(_settingsOpen)],
      // The frame is the single page of an outer Navigator so its chrome —
      // the burger tooltip and popup menu — have an Overlay and Navigator
      // above the app routes; the app's own navigator stays inside the
      // frame as the page's child.
      // ignore: deprecated_member_use
      builder: (context, child) => MaterialUiCompatibilityBridge(
        child: Navigator(
          onGenerateRoute: (settings) => PageRouteBuilder<void>(
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
            pageBuilder: (context, animation, secondaryAnimation) => _FramePage(
              settingsOpen: _settingsOpen,
              onNewTab: _openTerminal,
              onSplitRight: () => _split(SplitAxis.horizontal),
              onSplitBelow: () => _split(SplitAxis.vertical),
              onCloseTab: _closeSelectedTab,
              onClosePane: _closeFocusedPane,
              onSettings: _openSettings,
              child: child!,
            ),
          ),
        ),
      ),
      home: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.comma, meta: true): () =>
              _openSettings(),
          const SingleActivator(LogicalKeyboardKey.keyN, meta: true): () =>
              _openNewWindow(),
          const SingleActivator(LogicalKeyboardKey.keyN, control: true): () =>
              _openNewWindow(),
          const SingleActivator(LogicalKeyboardKey.keyT, meta: true): () =>
              _openTerminal(),
          const SingleActivator(LogicalKeyboardKey.keyT, control: true): () =>
              _openTerminal(),
          const SingleActivator(LogicalKeyboardKey.tab, control: true): () =>
              _selectNextTab(),
          const SingleActivator(LogicalKeyboardKey.digit1, meta: true): () =>
              _selectPaneNumber(1),
          const SingleActivator(LogicalKeyboardKey.digit2, meta: true): () =>
              _selectPaneNumber(2),
          const SingleActivator(LogicalKeyboardKey.digit3, meta: true): () =>
              _selectPaneNumber(3),
          const SingleActivator(LogicalKeyboardKey.digit4, meta: true): () =>
              _selectPaneNumber(4),
          const SingleActivator(LogicalKeyboardKey.digit5, meta: true): () =>
              _selectPaneNumber(5),
          const SingleActivator(LogicalKeyboardKey.digit6, meta: true): () =>
              _selectPaneNumber(6),
          const SingleActivator(LogicalKeyboardKey.digit7, meta: true): () =>
              _selectPaneNumber(7),
          const SingleActivator(LogicalKeyboardKey.digit8, meta: true): () =>
              _selectPaneNumber(8),
          const SingleActivator(LogicalKeyboardKey.digit9, meta: true): () =>
              _selectPaneNumber(9),
          const SingleActivator(LogicalKeyboardKey.digit0, meta: true): () =>
              _selectPaneNumber(10),
          const SingleActivator(LogicalKeyboardKey.keyD, meta: true): () =>
              _split(SplitAxis.horizontal),
          const SingleActivator(LogicalKeyboardKey.keyD, control: true): () =>
              _split(SplitAxis.horizontal),
          const SingleActivator(
            LogicalKeyboardKey.keyD,
            meta: true,
            shift: true,
          ): () =>
              _split(SplitAxis.vertical),
          const SingleActivator(LogicalKeyboardKey.keyW, meta: true): () =>
              _closeFocusedPane(),
          const SingleActivator(LogicalKeyboardKey.keyW, control: true): () =>
              _closeFocusedPane(),
          const SingleActivator(
            LogicalKeyboardKey.keyW,
            meta: true,
            shift: true,
          ): () =>
              _closeSelectedTab(),
        },
        child: TerminalWorkspacePage(
          onAppKeyEvent: _handleFocusedTerminalKeyEvent,
          onSelectNextTab: _selectNextTab,
          onSelectPaneNumber: _selectPaneNumber,
        ),
      ),
    );
  }
}

/// The window frame as the outer navigator's single page. Watches the
/// settings provider directly so toggling the title-bar menu button applies
/// live, without re-creating the route.
class _FramePage extends ConsumerWidget {
  const _FramePage({
    required this.settingsOpen,
    required this.child,
    required this.onNewTab,
    required this.onSplitRight,
    required this.onSplitBelow,
    required this.onCloseTab,
    required this.onClosePane,
    required this.onSettings,
  });

  final ValueListenable<bool> settingsOpen;
  final Widget child;
  final VoidCallback onNewTab;
  final VoidCallback onSplitRight;
  final VoidCallback onSplitBelow;
  final VoidCallback onCloseTab;
  final VoidCallback onClosePane;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(terminalSettingsProvider).value;
    final showMenu = settings?.showTitleBarMenuButton ?? false;
    return ValueListenableBuilder<bool>(
      valueListenable: settingsOpen,
      builder: (context, settingsOpen, _) => MaidTermWindowScaffold(
        title: settingsOpen ? 'settingsTitle'.tr() : 'title'.tr(),
        menuButton: showMenu
            ? _TitleBarMenuButton(
                onNewTab: onNewTab,
                onSplitRight: onSplitRight,
                onSplitBelow: onSplitBelow,
                onCloseTab: onCloseTab,
                onClosePane: onClosePane,
                onSettings: onSettings,
              )
            : null,
        child: child,
      ),
    );
  }
}

enum _TitleBarMenuAction {
  newTab,
  splitRight,
  splitBelow,
  closeTab,
  closePane,
  settings,
}

/// The title-bar burger menu: mirrors the macOS Terminal menu and the app
/// shortcuts for platforms without a system menu bar.
class _TitleBarMenuButton extends StatelessWidget {
  const _TitleBarMenuButton({
    required this.onNewTab,
    required this.onSplitRight,
    required this.onSplitBelow,
    required this.onCloseTab,
    required this.onClosePane,
    required this.onSettings,
  });

  final VoidCallback onNewTab;
  final VoidCallback onSplitRight;
  final VoidCallback onSplitBelow;
  final VoidCallback onCloseTab;
  final VoidCallback onClosePane;
  final VoidCallback onSettings;

  static final bool _macOS = Platform.isMacOS;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    PopupMenuItem<_TitleBarMenuAction> item(
      _TitleBarMenuAction action,
      String label,
      IconData icon,
      String? shortcut,
    ) {
      return PopupMenuItem(
        value: action,
        child: Row(
          children: [
            Icon(icon, size: 18, color: scheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(child: Text(label)),
            if (shortcut != null) ...[
              const SizedBox(width: 24),
              Text(
                shortcut,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      );
    }

    return PopupMenuButton<_TitleBarMenuAction>(
      tooltip: 'menuTooltip'.tr(),
      icon: const Icon(Symbols.menu, size: 18),
      position: PopupMenuPosition.under,
      onSelected: (action) {
        switch (action) {
          case _TitleBarMenuAction.newTab:
            onNewTab();
          case _TitleBarMenuAction.splitRight:
            onSplitRight();
          case _TitleBarMenuAction.splitBelow:
            onSplitBelow();
          case _TitleBarMenuAction.closeTab:
            onCloseTab();
          case _TitleBarMenuAction.closePane:
            onClosePane();
          case _TitleBarMenuAction.settings:
            onSettings();
        }
      },
      itemBuilder: (context) => [
        item(
          _TitleBarMenuAction.newTab,
          'menuNewTab'.tr(),
          Symbols.add,
          _macOS ? '⌘T' : null,
        ),
        item(
          _TitleBarMenuAction.splitRight,
          'menuSplitRight'.tr(),
          Symbols.vertical_split,
          _macOS ? '⌘D' : null,
        ),
        item(
          _TitleBarMenuAction.splitBelow,
          'menuSplitBelow'.tr(),
          Symbols.horizontal_split,
          _macOS ? '⌘⇧D' : null,
        ),
        const PopupMenuDivider(),
        item(
          _TitleBarMenuAction.closePane,
          'menuClosePane'.tr(),
          Symbols.splitscreen,
          _macOS ? '⌘W' : null,
        ),
        item(
          _TitleBarMenuAction.closeTab,
          'menuCloseTab'.tr(),
          Symbols.close,
          _macOS ? '⌘⇧W' : null,
        ),
        const PopupMenuDivider(),
        item(
          _TitleBarMenuAction.settings,
          'menuSettings'.tr(),
          Symbols.settings,
          _macOS ? '⌘,' : null,
        ),
      ],
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
