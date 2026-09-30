import 'package:flutter/foundation.dart';

import 'dart:async';

import 'package:collection/collection.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:maidterm/maidterm.dart' as maidterm;
import 'package:uuid/uuid.dart';

import '../settings/terminal_settings.dart';
import '../shell/local_shell_session.dart';
import '../shell/process_title_monitor.dart';
import '../windows/app_focus.dart';
import 'close_confirm.dart';
import 'session_layout.dart';

/// Shared poller resolving each tab's foreground process name and RSS.
final processTitleMonitorProvider = Provider<ProcessTitleMonitor>((ref) {
  final monitor = ProcessTitleMonitor();
  ref.onDispose(monitor.dispose);
  return monitor;
});

/// Creates a shell session bound to a terminal pane.
typedef LocalShellSessionFactory = LocalShellSession Function({
  String? workingDirectory,
});

final localShellSessionFactoryProvider = Provider<LocalShellSessionFactory>((
  ref,
) {
  final settings = ref.watch(terminalSettingsProvider).value;
  final shell = settings?.shellPath;
  final cursorBlink = settings?.cursorBlink ?? true;
  final cursorStyle = settings?.cursorStyle ?? maidterm.CursorShape.block;
  final monitor = ref.watch(processTitleMonitorProvider);
  final appFocus = ref.watch(appFocusProvider);
  return ({String? workingDirectory}) => LocalShellSession(
    shell: shell,
    workingDirectory: workingDirectory,
    cursorBlink: cursorBlink,
    cursorStyle: cursorStyle,
    processMonitor: monitor,
    isAppFocused: () => appFocus.value,
  );
});

const _uuid = Uuid();

/// A terminal surface inside a workspace tab.
class TerminalTab {
  TerminalTab({required this.id, required this.session});

  final String id;
  final LocalShellSession session;
  String get title => session.title.value;
  maidterm.TerminalController get controller => session.controller;
  int? get ptyPid => session.ptyPid;
  ValueListenable<maidterm.TerminalProgress?> get progress => session.progress;

  @override
  bool operator ==(Object other) => other is TerminalTab && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// One pane inside a top-level workspace tab.
class TerminalPane {
  TerminalPane({required this.id, required this.tab}) : viewKey = Object();

  final String id;
  final TerminalTab tab;

  /// Identity-stable key for the pane's terminal element, so layout
  /// restructuring (split, close) moves the element instead of recreating it.
  final Object viewKey;

  bool get isEmpty => false;
}

/// A top-level tab owns its complete split-pane layout.
class TerminalWorkspaceTab {
  const TerminalWorkspaceTab({
    required this.id,
    required this.panes,
    required this.layout,
    required this.focusedPaneId,
  });

  final String id;
  final Map<String, TerminalPane> panes;
  final PaneLayout layout;
  final String focusedPaneId;

  TerminalPane? get focusedPane => panes[focusedPaneId];

  /// Compatibility surface for callers that need the active terminal session.
  TerminalTab get session => focusedPane!.tab;

  String get title => session.title;
  maidterm.TerminalController get controller => session.controller;

  ValueListenable<maidterm.TerminalProgress?> get progress => session.progress;

  TerminalWorkspaceTab copyWith({
    Map<String, TerminalPane>? panes,
    PaneLayout? layout,
    String? focusedPaneId,
  }) => TerminalWorkspaceTab(
    id: id,
    panes: panes ?? this.panes,
    layout: layout ?? this.layout,
    focusedPaneId: focusedPaneId ?? this.focusedPaneId,
  );
}

class TerminalWorkspaceState {
  const TerminalWorkspaceState({this.tabs = const [], this.selectedTabId});

  /// Top-level tabs. Each item owns its own pane layout.
  final List<TerminalWorkspaceTab> tabs;
  final String? selectedTabId;

  TerminalWorkspaceTab? get selectedTab => selectedTabId == null
      ? null
      : tabs.firstWhereOrNull((tab) => tab.id == selectedTabId);

  /// Panes belonging to the selected top-level tab.
  Map<String, TerminalPane> get panes => selectedTab?.panes ?? const {};

  PaneLayout? get layout => selectedTab?.layout;

  String? get focusedPaneId => selectedTab?.focusedPaneId;

  TerminalPane? get focusedPane => selectedTab?.focusedPane;

  bool get hasSplits => selectedTab?.layout.isSplit ?? false;

  List<TerminalTab> tabsInPane(String paneId) {
    final pane = panes[paneId];
    return pane == null ? const [] : [pane.tab];
  }

  TerminalTab? selectedTabInPane(String paneId) => panes[paneId]?.tab;

  String? paneIdForTab(String tabId) {
    for (final pane in panes.values) {
      if (pane.tab.id == tabId) return pane.id;
    }
    return null;
  }
}

/// The tabs of one window.
///
/// Every window owns a separate family instance; tabs move between them by
/// handing over the whole [TerminalWorkspaceTab], so their shell sessions keep
/// running across the move.
final terminalWorkspaceProvider =
    NotifierProvider.family<
      TerminalWorkspaceNotifier,
      TerminalWorkspaceState,
      String
    >(TerminalWorkspaceNotifier.new);

/// Holds the live terminal workspaces of one window.
class TerminalWorkspaceNotifier extends Notifier<TerminalWorkspaceState> {
  TerminalWorkspaceNotifier(this.windowId);

  /// The window these tabs belong to.
  final String windowId;

  /// Sessions this window is responsible for terminating. Mirrors the panes in
  /// [state]; a tab handed to another window leaves this list with it.
  final List<LocalShellSession> _ownedSessions = [];

  @override
  TerminalWorkspaceState build() {
    ref.onDispose(() {
      for (final session in _ownedSessions) {
        unawaited(session.terminate());
      }
      _ownedSessions.clear();
    });
    // The window is given its first tab by the windows controller, so a window
    // created to adopt a torn-off tab never spawns a shell of its own.
    return const TerminalWorkspaceState();
  }

  TerminalWorkspaceTab _createWorkspaceTab({String? workingDirectory}) {
    final paneId = _uuid.v4();
    final tab = _spawnTerminalTab(workingDirectory: workingDirectory);
    final group = TerminalWorkspaceTab(
      id: _uuid.v4(),
      panes: {paneId: TerminalPane(id: paneId, tab: tab)},
      layout: PaneLayoutLeaf(paneId),
      focusedPaneId: paneId,
    );
    _bindSessionExit(group, paneId, tab);
    return group;
  }

  TerminalTab _spawnTerminalTab({String? workingDirectory}) {
    final session = ref.read(localShellSessionFactoryProvider)(
      workingDirectory: workingDirectory,
    );
    _ownedSessions.add(session);
    final tab = TerminalTab(id: _uuid.v4(), session: session);
    session.title.addListener(_onSessionTitleChanged);
    return tab;
  }

  void _bindSessionExit(
    TerminalWorkspaceTab group,
    String paneId,
    TerminalTab tab,
  ) {
    tab.session.onExit = () => _onPaneExit(group.id, paneId);
  }

  void _onSessionTitleChanged() {
    state = _rebuild(tabs: [...state.tabs]);
  }

  void _onPaneExit(String groupId, String paneId) {
    final group = state.tabs.firstWhereOrNull((tab) => tab.id == groupId);
    if (group == null || !group.panes.containsKey(paneId)) return;
    if (group.panes.length == 1) {
      // The session already exited on its own; nothing is running to warn
      // about, so skip the confirmation.
      closeTab(groupId, confirm: false);
      return;
    }
    final nextGroup = _withoutPane(group, paneId);
    state = _replaceGroup(nextGroup);
  }

  /// Opens a new top-level tab with one pane.
  void openTerminal({String? workingDirectory}) {
    final cwd =
        workingDirectory ?? state.focusedPane?.tab.session.workingDirectory;
    final group = _createWorkspaceTab(workingDirectory: cwd);
    state = TerminalWorkspaceState(
      tabs: [...state.tabs, group],
      selectedTabId: group.id,
    );
  }

  /// Splits the active top-level tab without creating another top-level tab.
  void split(SplitAxis axis) {
    final group = state.selectedTab;
    if (group == null) return;
    final focusedPane = group.focusedPane;
    if (focusedPane == null) return;

    final paneId = _uuid.v4();
    final tab = _spawnTerminalTab(
      workingDirectory: focusedPane.tab.session.workingDirectory,
    );
    final nextGroup = group.copyWith(
      panes: {
        ...group.panes,
        paneId: TerminalPane(id: paneId, tab: tab),
      },
      layout: splitPane(
        layout: group.layout,
        focusedPaneId: group.focusedPaneId,
        newPaneId: paneId,
        axis: axis,
        splitId: _uuid.v4(),
      ),
      focusedPaneId: paneId,
    );
    _bindSessionExit(nextGroup, paneId, tab);
    state = _replaceGroup(nextGroup);
  }

  void focusPane(String paneId) {
    final group = state.selectedTab;
    if (group == null || !group.panes.containsKey(paneId)) return;
    state = _replaceGroup(group.copyWith(focusedPaneId: paneId));
  }

  /// Selects the next top-level tab and wraps at the end.
  void selectNextTab() {
    if (state.tabs.length < 2) return;
    final currentIndex = state.tabs.indexWhere(
      (tab) => tab.id == state.selectedTabId,
    );
    final nextIndex = (currentIndex + 1) % state.tabs.length;
    state = _rebuild(selectedTabId: state.tabs[nextIndex].id);
  }

  /// Focuses the [number]th pane in the selected tab. Numbers are one-based;
  /// zero selects pane ten, matching the Cmd+1 through Cmd+0 shortcuts.
  void selectPaneNumber(int number) {
    final group = state.selectedTab;
    if (group == null || number < 1 || number > 10) return;
    final paneIds = group.layout.paneIds.toList(growable: false);
    final paneIndex = number == 10 ? 9 : number - 1;
    if (paneIndex >= paneIds.length) return;
    final paneId = paneIds[paneIndex];
    if (paneId == group.focusedPaneId) return;
    state = _replaceGroup(group.copyWith(focusedPaneId: paneId));
  }

  /// Selects a top-level tab. Leaf ids are also accepted for compatibility.
  void selectTab(String tabId, {String? paneId}) {
    final group = state.tabs.firstWhereOrNull((tab) => tab.id == tabId);
    if (group != null) {
      state = _rebuild(selectedTabId: group.id);
      return;
    }
    final active = state.selectedTab;
    final leafPaneId = paneId ?? state.paneIdForTab(tabId);
    if (active == null || leafPaneId == null) return;
    if (active.panes[leafPaneId]?.tab.id != tabId) return;
    state = _replaceGroup(active.copyWith(focusedPaneId: leafPaneId));
  }

  /// Moves [tabId] so that it sits before the tab currently at [insertBefore],
  /// counting the list without the moved tab.
  void moveTab(String tabId, int insertBefore) {
    final fromIndex = state.tabs.indexWhere((tab) => tab.id == tabId);
    if (fromIndex < 0) return;
    final tabs = [...state.tabs];
    final group = tabs.removeAt(fromIndex);
    if (insertBefore == fromIndex) return;
    tabs.insert(insertBefore.clamp(0, tabs.length), group);
    state = _rebuild(tabs: tabs);
  }

  /// Removes [tabId] and hands it to another window, keeping its sessions
  /// running. Returns null when this window does not own the tab.
  TerminalWorkspaceTab? takeTab(String tabId) {
    final index = state.tabs.indexWhere((tab) => tab.id == tabId);
    if (index < 0) return null;
    final group = state.tabs[index];
    final nextTabs = [...state.tabs]..removeAt(index);
    if (nextTabs.isEmpty) {
      state = const TerminalWorkspaceState();
      return group;
    }
    final nextSelected = state.selectedTabId == tabId
        ? nextTabs[(index - 1).clamp(0, nextTabs.length - 1)].id
        : state.selectedTabId;
    state = TerminalWorkspaceState(tabs: nextTabs, selectedTabId: nextSelected);
    return group;
  }

  /// Adds a tab owned by another window and selects it. The sessions keep
  /// running; only their exit callbacks move to this window.
  void attachTab(TerminalWorkspaceTab group, {int? index}) {
    for (final pane in group.panes.values) {
      _bindSessionExit(group, pane.id, pane.tab);
      if (!_ownedSessions.contains(pane.tab.session)) {
        _ownedSessions.add(pane.tab.session);
      }
    }
    final tabs = [...state.tabs]
      ..insert((index ?? state.tabs.length).clamp(0, state.tabs.length), group);
    state = TerminalWorkspaceState(tabs: tabs, selectedTabId: group.id);
  }

  /// Closes a top-level tab and all panes it owns. When any pane still runs
  /// a program the user is asked to confirm first; [confirm] skips that for
  /// sessions that already exited on their own.
  Future<void> closeTab(String tabId, {bool confirm = true}) async {
    final index = state.tabs.indexWhere((tab) => tab.id == tabId);
    if (index < 0) return;
    final group = state.tabs[index];
    if (confirm &&
        !await confirmCloseSessions([
          for (final pane in group.panes.values) pane.tab.session,
        ], id: 'close-running-tab:$tabId')) {
      return;
    }
    final sessions = [for (final pane in group.panes.values) pane.tab.session];

    // Drop the tab from the tree first: key events can still arrive between
    // here and the frame that unmounts the views, and they must not reach a
    // disposed controller whose native handles are already freed.
    _removeTabAt(index, tabId);
    for (final session in sessions) {
      unawaited(session.terminate());
    }
  }

  void _removeTabAt(int index, String tabId) {
    final sessions = [
      for (final pane in state.tabs[index].panes.values) pane.tab.session,
    ];
    _ownedSessions.removeWhere(sessions.contains);
    final nextTabs = [...state.tabs]..removeAt(index);
    if (nextTabs.isEmpty) {
      state = const TerminalWorkspaceState();
      return;
    }
    final nextSelected = state.selectedTabId == tabId
        ? nextTabs[(index - 1).clamp(0, nextTabs.length - 1)].id
        : state.selectedTabId;
    state = TerminalWorkspaceState(tabs: nextTabs, selectedTabId: nextSelected);
  }

  /// Closes one pane in the active top-level tab.
  Future<void> closePane(String paneId) async {
    final groupId = state.selectedTabId;
    if (groupId != null) await closePaneInTab(groupId, paneId);
  }

  /// Closes [paneId] from any top-level tab.
  Future<void> closePaneInTab(String groupId, String paneId) async {
    final group = state.tabs.firstWhereOrNull((tab) => tab.id == groupId);
    if (group == null || !group.panes.containsKey(paneId)) return;
    if (group.panes.length == 1) {
      await closeTab(group.id);
      return;
    }
    final session = group.panes[paneId]!.tab.session;
    if (!await confirmCloseSessions([
      session,
    ], id: 'close-running-pane:$paneId')) {
      return;
    }
    // The layout may have changed while the modal was open.
    final current = state.tabs.firstWhereOrNull((tab) => tab.id == groupId);
    if (current == null || !current.panes.containsKey(paneId)) return;
    if (current.panes.length == 1) {
      await closeTab(current.id);
      return;
    }
    state = _replaceGroup(_withoutPane(current, paneId));
    _ownedSessions.remove(session);
    unawaited(session.terminate());
  }

  void setSplitRatio(String splitId, double ratio) {
    final group = state.selectedTab;
    if (group == null) return;
    state = _replaceGroup(
      group.copyWith(layout: applySplitRatio(group.layout, splitId, ratio)),
    );
  }

  Future<void> closeAll() async {
    final sessions = [
      for (final group in state.tabs)
        for (final pane in group.panes.values) pane.tab.session,
    ];
    _ownedSessions.clear();
    state = const TerminalWorkspaceState();
    for (final session in sessions) {
      unawaited(session.terminate());
    }
  }

  TerminalWorkspaceTab _withoutPane(TerminalWorkspaceTab group, String paneId) {
    final nextLayout = removePaneFromLayout(group.layout, paneId);
    if (nextLayout == null) return group;
    final nextPanes = {...group.panes}..remove(paneId);
    final nextFocus = group.focusedPaneId == paneId
        ? fallbackPaneAfterRemove(group.layout, paneId) ?? nextPanes.keys.first
        : group.focusedPaneId;
    return group.copyWith(
      panes: nextPanes,
      layout: nextLayout,
      focusedPaneId: nextFocus,
    );
  }

  TerminalWorkspaceState _replaceGroup(TerminalWorkspaceTab group) =>
      TerminalWorkspaceState(
        tabs: [for (final tab in state.tabs) tab.id == group.id ? group : tab],
        selectedTabId: state.selectedTabId,
      );

  TerminalWorkspaceState _rebuild({
    List<TerminalWorkspaceTab>? tabs,
    String? selectedTabId,
  }) => TerminalWorkspaceState(
    tabs: tabs ?? state.tabs,
    selectedTabId: selectedTabId ?? state.selectedTabId,
  );
}
