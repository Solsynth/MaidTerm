// ignore_for_file: invalid_use_of_internal_member, implementation_imports

import 'dart:async';
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
import 'package:flutter/src/widgets/_window.dart' as fw;

import 'settings/settings_page.dart';
import 'settings/terminal_settings.dart';
import 'windows/workspace_windows.dart';
import 'workspace/session_layout.dart';
import 'workspace/terminal_workspace_page.dart';
import 'theme.dart';

/// The root of the single-engine app: one [fw.ViewCollection] holding a
/// window per open workspace.
///
/// Every window renders the same widget tree, so state that used to be copied
/// between engines — terminal sessions above all — is now shared by
/// construction.
class MaidTermWindowsHost extends ConsumerStatefulWidget {
  const MaidTermWindowsHost({super.key});

  @override
  ConsumerState<MaidTermWindowsHost> createState() => _MaidTermWindowsHostState();
}

class _MaidTermWindowsHostState extends ConsumerState<MaidTermWindowsHost> {
  static const _menuChannel = MethodChannel('maidterm/menu');

  @override
  void initState() {
    super.initState();
    _menuChannel.setMethodCallHandler(_handleMenuCall);
    // Opened after the first frame: creating a window hands its first tab to
    // the window's own workspace provider, and Riverpod forbids a provider
    // from modifying another one while it initializes.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(workspaceWindowsProvider).openWindow();
    });
  }

  /// The shell menu is process-wide; its commands land in the focused window.
  Future<void> _handleMenuCall(MethodCall call) async {
    final windows = ref.read(workspaceWindowsProvider);
    final actions = windows.activeActions;
    switch (call.method) {
      case 'newTab':
        actions?.newTab();
      case 'newWindow':
        windows.openWindow();
      case 'splitRight':
        actions?.split(SplitAxis.horizontal);
      case 'splitBelow':
        actions?.split(SplitAxis.vertical);
      case 'closeTab':
        unawaited(actions?.closeSelectedTab());
      case 'closePane':
        unawaited(actions?.closeFocusedPane());
    }
  }

  @override
  Widget build(BuildContext context) {
    final windows = ref.watch(workspaceWindowsProvider);
    // The controller is a stable object, so the tree has to be rebuilt from
    // its notifications rather than from the provider's value.
    return ListenableBuilder(
      listenable: windows,
      builder: (context, _) => ViewCollection(
        views: [
          for (final window in windows.windows)
            if (window.controller != null)
              fw.RegularWindow(
              key: ObjectKey(window.controller),
              controller: window.controller!,
              child: MaidTermWindowApp(windowId: window.id),
            ),
        ],
      ),
    );
  }
}

/// One terminal window: the app routes, key handling and window chrome of a
/// single [WorkspaceWindow].
class MaidTermWindowApp extends ConsumerStatefulWidget {
  const MaidTermWindowApp({super.key, required this.windowId});

  final String windowId;

  @override
  ConsumerState<MaidTermWindowApp> createState() => _MaidTermWindowAppState();
}

class _MaidTermWindowAppState extends ConsumerState<MaidTermWindowApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _settingsOpen = ValueNotifier<bool>(false);
  WorkspaceWindowsController? _windows;

  @override
  void initState() {
    super.initState();
    final windows = ref.read(workspaceWindowsProvider);
    _windows = windows..addListener(_handleWindowsChanged);
    // The attention-modal alert resolves its navigator from this key, so the
    // modal has to follow the window the user is working in.
    IslandUIFoundation.configureNavigator(_navigatorKey);
  }

  @override
  void dispose() {
    _windows?.removeListener(_handleWindowsChanged);
    _settingsOpen.dispose();
    super.dispose();
  }

  void _handleWindowsChanged() {
    if (!mounted) return;
    if (_windows?.activeWindowId == widget.windowId) {
      IslandUIFoundation.configureNavigator(_navigatorKey);
    }
  }

  WorkspaceWindowActions get _actions =>
      ref.read(workspaceWindowsProvider).actionsFor(widget.windowId);

  void _openTerminal() => _actions.newTab();

  void _split(SplitAxis axis) => _actions.split(axis);

  void _selectNextTab() => _actions.selectNextTab();

  void _selectPaneNumber(int number) => _actions.selectPaneNumber(number);

  void _closeSelectedTab() => unawaited(_actions.closeSelectedTab());

  void _closeFocusedPane() => unawaited(_actions.closeFocusedPane());

  void _openNewWindow() => ref.read(workspaceWindowsProvider).openWindow();

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
    final windowTransparency = settings?.windowTransparency ?? 0.0;
    final windowTransparent = windowTransparency > 0;

    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'title'.tr(),
      debugShowCheckedModeBanner: false,
      color: windowTransparent ? Colors.transparent : null,
      theme: createMaidTermTheme(
        Brightness.light,
        seedColor: seedColor,
        windowTransparency: windowTransparency,
      ),
      darkTheme: createMaidTermTheme(
        Brightness.dark,
        seedColor: seedColor,
        windowTransparency: windowTransparency,
      ),
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
              windowId: widget.windowId,
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
          windowId: widget.windowId,
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
    required this.windowId,
    required this.settingsOpen,
    required this.child,
    required this.onNewTab,
    required this.onSplitRight,
    required this.onSplitBelow,
    required this.onCloseTab,
    required this.onClosePane,
    required this.onSettings,
  });

  final String windowId;
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
        windowId: windowId,
        windowTransparency: settings?.windowTransparency ?? 0.0,
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
