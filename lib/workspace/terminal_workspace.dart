import 'package:flutter/foundation.dart';

import 'dart:async';

import 'package:collection/collection.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:maidterm/maidterm.dart' as maidterm;
import 'package:uuid/uuid.dart';

import '../settings/terminal_settings.dart';
import '../shell/local_shell_session.dart';
import '../shell/process_title_monitor.dart';
import 'close_confirm.dart';
import 'session_layout.dart';
import '../window_runtime.dart';
import 'window_tab_transfer.dart';

/// Shared poller resolving each tab's foreground process name for titles.
final processTitleMonitorProvider = Provider<ProcessTitleMonitor>(
  (ref) => ProcessTitleMonitor(),
);

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
  return ({String? workingDirectory}) => LocalShellSession(
    shell: shell,
    workingDirectory: workingDirectory,
    cursorBlink: cursorBlink,
    cursorStyle: cursorStyle,
    processMonitor: monitor,
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

final terminalWorkspaceProvider =
    NotifierProvider<TerminalWorkspaceNotifier, TerminalWorkspaceState>(
      TerminalWorkspaceNotifier.new,
    );

/// Holds live terminal workspaces for the entire app lifetime.
class TerminalWorkspaceNotifier extends Notifier<TerminalWorkspaceState> {
  @override
  TerminalWorkspaceState build() {
    final transfer = ref.read(windowLaunchDataProvider).tab;
    final group = transfer == null
        ? _createWorkspaceTab()
        : _createWorkspaceTabFromTransfer(transfer);
    return TerminalWorkspaceState(tabs: [group], selectedTabId: group.id);
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

  TerminalWorkspaceTab _createWorkspaceTabFromTransfer(
    WorkspaceTabTransfer transfer,
  ) {
    final panes = <String, TerminalPane>{};
    for (final paneTransfer in transfer.panes) {
      final tab = _spawnTerminalTab(
        workingDirectory: paneTransfer.workingDirectory,
      );
      panes[paneTransfer.id] = TerminalPane(id: paneTransfer.id, tab: tab);
    }
    final group = TerminalWorkspaceTab(
      id: transfer.id,
      panes: panes,
      layout: WorkspaceTabTransfer.layoutFromJson(transfer.layout),
      focusedPaneId: panes.containsKey(transfer.focusedPaneId)
          ? transfer.focusedPaneId
          : panes.keys.first,
    );
    for (final pane in panes.values) {
      _bindSessionExit(group, pane.id, pane.tab);
    }
    return group;
  }

  TerminalTab _spawnTerminalTab({String? workingDirectory}) {
    final session = ref.read(localShellSessionFactoryProvider)(
      workingDirectory: workingDirectory,
    );
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

  /// Reorders top-level tabs without changing their pane layouts.
  void reorderTab(String tabId, int toIndex) {
    final fromIndex = state.tabs.indexWhere((tab) => tab.id == tabId);
    if (fromIndex < 0) return;
    final nextTabs = [...state.tabs]..removeAt(fromIndex);
    var insertAt = toIndex.clamp(0, state.tabs.length);
    if (fromIndex < insertAt && insertAt < state.tabs.length) insertAt--;
    nextTabs.insert(insertAt.clamp(0, nextTabs.length), state.tabs[fromIndex]);
    state = _rebuild(tabs: nextTabs);
  }

  /// Removes a tab without confirmation so another window can own it.
  ///
  /// The sessions are disposed after the destination has recreated them.
  void detachTab(String tabId, {bool disposeSessions = true}) {
    final index = state.tabs.indexWhere((tab) => tab.id == tabId);
    if (index < 0) return;
    final group = state.tabs[index];
    if (disposeSessions) {
      for (final pane in group.panes.values) {
        unawaited(pane.tab.session.dispose());
      }
    }
    final nextTabs = [...state.tabs]..removeAt(index);
    final nextSelected = nextTabs.isEmpty
        ? null
        : state.selectedTabId == tabId
        ? nextTabs[(index - 1).clamp(0, nextTabs.length - 1)].id
        : state.selectedTabId;
    state = TerminalWorkspaceState(tabs: nextTabs, selectedTabId: nextSelected);
  }

  /// Recreates a tab received from another Flutter engine.
  void importTab(WorkspaceTabTransfer transfer) {
    if (state.tabs.any((tab) => tab.id == transfer.id)) {
      selectTab(transfer.id);
      return;
    }
    final group = _createWorkspaceTabFromTransfer(transfer);
    state = TerminalWorkspaceState(
      tabs: [...state.tabs, group],
      selectedTabId: group.id,
    );
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
    for (final pane in group.panes.values) {
      unawaited(pane.tab.session.dispose());
    }

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
    unawaited(current.panes[paneId]!.tab.session.dispose());
    state = _replaceGroup(_withoutPane(current, paneId));
  }

  void setSplitRatio(String splitId, double ratio) {
    final group = state.selectedTab;
    if (group == null) return;
    state = _replaceGroup(
      group.copyWith(layout: applySplitRatio(group.layout, splitId, ratio)),
    );
  }

  Future<void> closeAll() async {
    for (final group in state.tabs) {
      for (final pane in group.panes.values) {
        await pane.tab.session.dispose();
      }
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
