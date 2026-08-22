import 'dart:async';

import 'package:collection/collection.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:maidterm/maidterm.dart' as maidterm;
import 'package:uuid/uuid.dart';

import '../settings/terminal_settings.dart';
import '../shell/local_shell_session.dart';
import '../shell/process_title_monitor.dart';
import 'session_layout.dart';

/// Shared poller resolving each tab's foreground process name for titles.
final processTitleMonitorProvider = Provider<ProcessTitleMonitor>(
  (ref) => ProcessTitleMonitor(),
);

/// Creates a shell session bound to a workspace tab, applying the terminal
/// settings (shell, cursor) at spawn time. Overridable in tests, where
/// plugin frameworks are not linked (`autoStart: false`).
final localShellSessionFactoryProvider = Provider<LocalShellSession Function()>(
  (ref) {
    final settings = ref.watch(terminalSettingsProvider).value;
    final shell = settings?.shellPath;
    final cursorBlink = settings?.cursorBlink ?? true;
    final cursorStyle = settings?.cursorStyle ?? maidterm.CursorShape.block;
    final monitor = ref.watch(processTitleMonitorProvider);
    return () => LocalShellSession(
      shell: shell,
      cursorBlink: cursorBlink,
      cursorStyle: cursorStyle,
      processMonitor: monitor,
    );
  },
);

const _uuid = Uuid();

/// A live local shell, identified for tab management.
class TerminalTab {
  TerminalTab({required this.id, required this.session});

  final String id;
  final LocalShellSession session;

  /// Display title: the terminal app's OSC 0/2 title, else the foreground
  /// process name, else the working directory for shells, else the shell
  /// name. Updates live as the session reports new state.
  String get title => session.title.value;

  @override
  bool operator ==(Object other) => other is TerminalTab && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// A terminal pane owns the selected terminal surface. Tab ordering is shared
/// across the workspace so split panes never need separate tab strips.
class TerminalPane {
  const TerminalPane({
    required this.id,
    this.tabIds = const [],
    this.selectedTabId,
  });

  final String id;
  final List<String> tabIds;
  final String? selectedTabId;

  bool get isEmpty => tabIds.isEmpty;

  TerminalPane copyWith({List<String>? tabIds, String? selectedTabId}) =>
      TerminalPane(
        id: id,
        tabIds: tabIds ?? this.tabIds,
        selectedTabId: selectedTabId ?? this.selectedTabId,
      );

  TerminalPane withTab(String tabId) =>
      TerminalPane(id: id, tabIds: [...tabIds, tabId], selectedTabId: tabId);

  TerminalPane withTabAt(String tabId, int index) {
    final ids = [...tabIds]..remove(tabId);
    final insertAt = index.clamp(0, ids.length);
    ids.insert(insertAt, tabId);
    return TerminalPane(id: id, tabIds: ids, selectedTabId: tabId);
  }

  TerminalPane withoutTab(String tabId) {
    final index = tabIds.indexOf(tabId);
    final nextIds = [...tabIds]..remove(tabId);
    if (nextIds.isEmpty) {
      return TerminalPane(id: id, tabIds: const []);
    }
    final String? nextSelected;
    if (selectedTabId == tabId) {
      nextSelected = nextIds[(index - 1).clamp(0, nextIds.length - 1)];
    } else if (nextIds.contains(selectedTabId)) {
      nextSelected = selectedTabId;
    } else {
      nextSelected = nextIds.last;
    }
    return TerminalPane(id: id, tabIds: nextIds, selectedTabId: nextSelected);
  }
}

class TerminalWorkspaceState {
  const TerminalWorkspaceState({
    this.tabs = const [],
    this.panes = const {},
    this.layout,
    this.focusedPaneId,
  });

  final List<TerminalTab> tabs;
  final Map<String, TerminalPane> panes;

  /// Arrangement of panes. Null when no panes are open.
  final PaneLayout? layout;
  final String? focusedPaneId;

  TerminalPane? get focusedPane =>
      focusedPaneId == null ? null : panes[focusedPaneId];

  /// Tab selected in the focused pane.
  TerminalTab? get selectedTab {
    final tabId = focusedPane?.selectedTabId;
    if (tabId == null) return null;
    for (final tab in tabs) {
      if (tab.id == tabId) return tab;
    }
    return null;
  }

  bool get hasSplits => layout?.isSplit ?? false;

  List<TerminalTab> tabsInPane(String paneId) {
    final pane = panes[paneId];
    if (pane == null) return const [];
    final byId = {for (final tab in tabs) tab.id: tab};
    return [for (final id in pane.tabIds) ?byId[id]];
  }

  TerminalTab? selectedTabInPane(String paneId) {
    final tabId = panes[paneId]?.selectedTabId;
    if (tabId == null) return null;
    for (final tab in tabs) {
      if (tab.id == tabId) return tab;
    }
    return null;
  }

  /// Id of the pane currently holding [tabId], if any.
  String? paneIdForTab(String tabId) {
    for (final pane in panes.values) {
      if (pane.tabIds.contains(tabId)) return pane.id;
    }
    return null;
  }
}

final terminalWorkspaceProvider =
    NotifierProvider<TerminalWorkspaceNotifier, TerminalWorkspaceState>(
      TerminalWorkspaceNotifier.new,
    );

/// Holds live local terminal tabs for the entire app lifetime.
///
/// Deliberately not auto-disposed: terminals keep receiving output while the
/// settings page is open.
class TerminalWorkspaceNotifier extends Notifier<TerminalWorkspaceState> {
  @override
  TerminalWorkspaceState build() {
    // Open with a single terminal, like a real terminal app.
    final tab = _spawnTab();
    final paneId = _uuid.v4();
    return TerminalWorkspaceState(
      tabs: [tab],
      panes: {
        paneId: TerminalPane(
          id: paneId,
          tabIds: [tab.id],
          selectedTabId: tab.id,
        ),
      },
      layout: PaneLayoutLeaf(paneId),
      focusedPaneId: paneId,
    );
  }

  TerminalTab _spawnTab() {
    final session = ref.read(localShellSessionFactoryProvider)();
    final tab = TerminalTab(id: _uuid.v4(), session: session);
    session.title.addListener(_onSessionTitleChanged);
    return tab;
  }

  /// A tab's display title changed; rebuild so the tab strip repaints.
  void _onSessionTitleChanged() {
    state = _rebuild(tabs: [...state.tabs]);
  }

  /// Opens a new terminal tab in the focused pane.
  void openTerminal() {
    final tab = _spawnTab();
    final focusId = state.focusedPaneId;
    if (focusId == null) {
      _openFirstPane(tab);
      return;
    }
    state = _rebuild(
      tabs: [...state.tabs, tab],
      panes: {...state.panes, focusId: state.panes[focusId]!.withTab(tab.id)},
    );
  }

  /// Splits the focused pane along [axis] and opens a fresh terminal there.
  void split(SplitAxis axis) {
    final focusId = state.focusedPaneId;
    if (focusId == null) return;
    final tab = _spawnTab();
    final newPaneId = _uuid.v4();
    final newPane = TerminalPane(
      id: newPaneId,
      tabIds: [tab.id],
      selectedTabId: tab.id,
    );
    final layout = state.layout;
    if (layout == null) {
      _openFirstPane(tab);
      return;
    }
    state = TerminalWorkspaceState(
      tabs: [...state.tabs, tab],
      panes: {...state.panes, newPaneId: newPane},
      layout: splitPane(
        layout: layout,
        focusedPaneId: focusId,
        newPaneId: newPaneId,
        axis: axis,
        splitId: _uuid.v4(),
      ),
      focusedPaneId: newPaneId,
    );
  }

  void focusPane(String paneId) {
    if (state.panes.containsKey(paneId)) {
      state = _rebuild(focusedPaneId: paneId);
    }
  }

  /// Selects [tabId] in [paneId] (defaults to the focused pane).
  void selectTab(String tabId, {String? paneId}) {
    final pane = paneId ?? state.focusedPaneId;
    if (pane == null) return;
    state = _rebuild(
      panes: {
        ...state.panes,
        pane: state.panes[pane]!.copyWith(selectedTabId: tabId),
      },
      focusedPaneId: pane,
    );
  }

  /// Moves [tabId] into [paneId], at [toIndex] when given. Same-pane moves
  /// reorder; cross-pane moves take the tab out of its source pane, collapsing
  /// the source when it empties.
  void moveTab(String tabId, String paneId, {int? toIndex}) {
    final fromPaneId = state.paneIdForTab(tabId);
    if (fromPaneId == null) return;

    if (fromPaneId == paneId) {
      final pane = state.panes[paneId]!;
      state = _rebuild(
        panes: {
          ...state.panes,
          paneId: pane.withTabAt(tabId, toIndex ?? pane.tabIds.length - 1),
        },
      );
      return;
    }

    final target = state.panes[paneId];
    if (target == null) return;
    final source = state.panes[fromPaneId]!;

    var nextPanes = {...state.panes};
    var nextLayout = state.layout;
    var nextFocus = state.focusedPaneId;

    final sourceWithout = source.withoutTab(tabId);
    if (sourceWithout.isEmpty) {
      nextPanes.remove(fromPaneId);
      if (nextLayout != null) {
        nextLayout = removePaneFromLayout(nextLayout, fromPaneId);
        if (nextFocus == fromPaneId) {
          nextFocus = fallbackPaneAfterRemove(state.layout, fromPaneId);
        }
      }
    } else {
      nextPanes[fromPaneId] = sourceWithout;
    }

    nextPanes[paneId] = target.withTabAt(
      tabId,
      toIndex ?? target.tabIds.length,
    );
    state = TerminalWorkspaceState(
      tabs: state.tabs,
      panes: nextPanes,
      layout: nextLayout,
      focusedPaneId: nextFocus,
    );
  }

  /// Reorders the workspace-wide tab strip without changing pane ownership.
  void reorderTab(String tabId, int toIndex) {
    final fromIndex = state.tabs.indexWhere((tab) => tab.id == tabId);
    if (fromIndex < 0) return;

    final nextTabs = [...state.tabs]..removeAt(fromIndex);
    var insertAt = toIndex.clamp(0, state.tabs.length);
    if (fromIndex < insertAt && insertAt < state.tabs.length) {
      insertAt--;
    }
    nextTabs.insert(insertAt.clamp(0, nextTabs.length), state.tabs[fromIndex]);
    state = _rebuild(tabs: nextTabs);
  }

  /// Closes [tabId]; if its pane empties, the pane closes too.
  void closeTab(String tabId) {
    final tab = state.tabs.where((t) => t.id == tabId).firstOrNull;
    if (tab == null) return;
    unawaited(tab.session.dispose());

    var nextTabs = [...state.tabs]..removeWhere((t) => t.id == tabId);
    var nextPanes = {...state.panes};
    String? closedPaneId;
    String? newFocus;
    for (final entry in state.panes.entries) {
      final pane = entry.value;
      if (!pane.tabIds.contains(tabId)) continue;
      final without = pane.withoutTab(tabId);
      if (without.isEmpty) {
        closedPaneId = pane.id;
        nextPanes.remove(pane.id);
      } else {
        nextPanes[pane.id] = without;
      }
      break;
    }
    if (closedPaneId != null) {
      final layout = state.layout;
      final nextLayout = layout == null
          ? null
          : removePaneFromLayout(layout, closedPaneId);
      if (nextLayout == null) {
        nextTabs = const [];
        nextPanes = const {};
        newFocus = null;
      } else {
        newFocus = state.focusedPaneId == closedPaneId
            ? fallbackPaneAfterRemove(layout, closedPaneId)
            : state.focusedPaneId;
      }
      state = TerminalWorkspaceState(
        tabs: nextTabs,
        panes: nextPanes,
        layout: nextLayout,
        focusedPaneId: newFocus,
      );
      return;
    }
    state = _rebuild(tabs: nextTabs, panes: nextPanes);
  }

  void setSplitRatio(String splitId, double ratio) {
    final layout = state.layout;
    if (layout == null) return;
    state = _rebuild(layout: applySplitRatio(layout, splitId, ratio));
  }

  /// Closes the whole workspace (all tabs). Sessions are disposed so shells
  /// do not linger after the app exits.
  Future<void> closeAll() async {
    for (final tab in state.tabs) {
      await tab.session.dispose();
    }
  }

  void _openFirstPane(TerminalTab tab) {
    final paneId = _uuid.v4();
    state = TerminalWorkspaceState(
      tabs: [tab],
      panes: {
        paneId: TerminalPane(
          id: paneId,
          tabIds: [tab.id],
          selectedTabId: tab.id,
        ),
      },
      layout: PaneLayoutLeaf(paneId),
      focusedPaneId: paneId,
    );
  }

  TerminalWorkspaceState _rebuild({
    List<TerminalTab>? tabs,
    Map<String, TerminalPane>? panes,
    PaneLayout? layout,
    String? focusedPaneId,
  }) => TerminalWorkspaceState(
    tabs: tabs ?? state.tabs,
    panes: panes ?? state.panes,
    layout: layout ?? state.layout,
    focusedPaneId: focusedPaneId ?? state.focusedPaneId,
  );
}
