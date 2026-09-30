// ignore_for_file: invalid_use_of_internal_member, implementation_imports

import 'dart:async';
import 'dart:ui' show AppExitType;

import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/src/widgets/_window.dart' as fw;
import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:nativeapi_flutter/nativeapi_flutter.dart' as na;
import 'package:nativeapi_flutter/windowing.dart';
import 'package:uuid/uuid.dart';

import '../workspace/close_confirm.dart';
import 'app_focus.dart';
import '../workspace/session_layout.dart';
import '../workspace/terminal_workspace.dart';
import 'tab_strip_geometry.dart';

const _uuid = Uuid();

/// Preferred size of a window opened without a source window to copy from.
const _defaultWindowSize = Size(1100, 720);
const _minimumWindowSize = Size(480, 320);

/// How far the pointer must travel before a press on a tab becomes a drag.
const _tabDragSlop = 8.0;

/// How far off the strip a dragged tab must go before it is torn off into a
/// window of its own.
const _tabDetachMargin = 28.0;

/// One open terminal window.
///
/// Every window is a view of the single Flutter engine, so the terminal
/// sessions behind its tabs are ordinary Dart objects: moving a tab between
/// windows reparents its widget subtree instead of recreating a shell.
class WorkspaceWindow {
  WorkspaceWindow({required this.id, this.controller});

  final String id;

  /// The framework window backing this view, or null on a host that cannot
  /// create windows.
  final fw.RegularWindowController? controller;

  /// Screen-space geometry of this window's tab strip, filled by the strip.
  final TabStripRegistry strip = TabStripRegistry();

  /// The native window behind [controller]; null once the controller is gone.
  na.Window? native;

  @override
  String toString() => 'WorkspaceWindow($id)';
}

/// Stage of a tab drag, mirroring the pointer's relationship to any strip.
enum TabDragMode {
  /// Pressed on a tab, not moved far enough to start a drag yet.
  pending,

  /// Moving along the strip of [TabDragInfo.windowId].
  inStrip,

  /// The tab owns a whole window that follows the cursor.
  window,
}

/// Where the tab being dragged currently is.
class TabDragInfo {
  const TabDragInfo({
    required this.tabId,
    required this.windowId,
    required this.mode,
    required this.grab,
    required this.chipSize,
    required this.cursor,
  });

  final String tabId;

  /// Window whose strip currently owns the drag.
  final String windowId;
  final TabDragMode mode;

  /// Where the tab was grabbed, relative to its own top-left corner.
  final Offset grab;
  final Size chipSize;

  /// Latest screen position of the cursor.
  final Offset cursor;
}

/// Tab and pane commands bound to one window, for the shell menu, the
/// title-bar menu and the keyboard shortcuts.
class WorkspaceWindowActions {
  WorkspaceWindowActions(this._windows, this.windowId);

  final WorkspaceWindowsController _windows;
  final String windowId;

  TerminalWorkspaceNotifier get _notifier =>
      _windows.workspaceNotifier(windowId);
  TerminalWorkspaceState get _state => _windows.workspaceState(windowId);

  void newTab() => _notifier.openTerminal();

  void split(SplitAxis axis) => _notifier.split(axis);

  void selectNextTab() => _notifier.selectNextTab();

  void selectPaneNumber(int number) => _notifier.selectPaneNumber(number);

  /// Selects [paneId] inside [tabId].
  void selectTabPane(String tabId, String paneId) {
    _notifier.selectTab(tabId);
    _notifier.focusPane(paneId);
  }

  /// Closes the window when its last tab goes away.
  Future<void> closeTab(String tabId) async {
    await _notifier.closeTab(tabId);
    await _windows.closeWindowIfEmpty(windowId);
  }

  Future<void> closeSelectedTab() async {
    final tabId = _state.selectedTab?.id;
    if (tabId != null) await closeTab(tabId);
  }

  Future<void> closePane(String paneId) async {
    await _notifier.closePane(paneId);
    await _windows.closeWindowIfEmpty(windowId);
  }

  /// Closes [paneId] from [tabId].
  Future<void> closePaneInTab(String tabId, String paneId) async {
    await _notifier.closePaneInTab(tabId, paneId);
    await _windows.closeWindowIfEmpty(windowId);
  }

  Future<void> closeFocusedPane() async {
    final paneId = _state.focusedPaneId;
    if (paneId != null) await closePane(paneId);
  }
}

/// Owns every open terminal window and the gesture that moves tabs between
/// them.
///
/// Windows are created from Dart through Flutter's multi-window API; tab drags
/// run on a nativeapi [na.WindowDragSession], which keeps reporting the global
/// cursor while the pointer is over another window's view (where Flutter would
/// otherwise have no pointer to report).
class WorkspaceWindowsController extends ChangeNotifier {
  WorkspaceWindowsController(this._ref) {
    _appFocus = _ref.read(appFocusProvider);
    // Hosts without the native library (tests, platforms without a drag
    // session) simply get no cursor tracking.
    try {
      _session = na.WindowDragSession.create();
    } catch (_) {
      _session = null;
    }
    _dragEventListener = _session?.addListener(_handleDragEvent);
  }

  final Ref _ref;
  late final AppFocus _appFocus;
  final List<WorkspaceWindow> _windows = [];
  final Set<String> _closingWindows = <String>{};
  final Map<String, ProviderSubscription<TerminalWorkspaceState>>
  _workspaceSubscriptions = <String, ProviderSubscription<TerminalWorkspaceState>>{};
  na.WindowDragSession? _session;
  na.ListenerId? _dragEventListener;
  _WorkspaceTabDrag? _drag;
  String? _activeWindowId;

  /// Cleared the first time a session dies without ever reporting a move:
  /// Wayland and similar platforms cannot read the global cursor, so tab
  /// presses fall back to a pointer-driven reorder inside the strip.
  var _sessionTracksCursor = true;

  List<WorkspaceWindow> get windows => List.unmodifiable(_windows);

  String? get activeWindowId => _activeWindowId;

  /// Whether tab drags can follow the cursor across windows on this platform.
  bool get nativeTabDragAvailable => _session != null && _sessionTracksCursor;

  TabDragInfo? get tabDrag {
    final drag = _drag;
    if (drag == null) return null;
    return TabDragInfo(
      tabId: drag.tabId,
      windowId: drag.windowId,
      mode: drag.mode,
      grab: drag.grab,
      chipSize: drag.chipSize,
      cursor: drag.cursor,
    );
  }

  /// Whether any window of this app is focused, used to mute notifications the
  /// user would see arrive anyway.
  bool get anyWindowFocused =>
      _windows.any((window) => window.controller?.isActivated ?? false);

  WorkspaceWindow? windowById(String? windowId) {
    if (windowId == null) return null;
    for (final window in _windows) {
      if (window.id == windowId) return window;
    }
    return null;
  }

  WorkspaceWindowActions actionsFor(String windowId) =>
      WorkspaceWindowActions(this, windowId);

  WorkspaceWindowActions? get activeActions {
    final id = _activeWindowId;
    return id == null ? null : actionsFor(id);
  }

  TerminalWorkspaceNotifier workspaceNotifier(String windowId) =>
      _ref.read(terminalWorkspaceProvider(windowId).notifier);

  TerminalWorkspaceState workspaceState(String windowId) =>
      _ref.read(terminalWorkspaceProvider(windowId));

  // ---------------------------------------------------------------------------
  // Window lifecycle

  /// Opens a window holding one fresh terminal.
  ///
  /// Returns null where no window can be created, which is what a host
  /// without windowing support reports.
  WorkspaceWindow? openWindow({Size? size}) {
    final window = createWindow(size: size);
    if (window == null) return null;
    workspaceNotifier(window.id).openTerminal();
    _activate(window.id);
    window.native?.focus();
    return window;
  }

  /// Opens a window that adopts [tab] instead of spawning a shell, used when a
  /// tab is torn off its strip.
  WorkspaceWindow? _adoptTab(TerminalWorkspaceTab tab, Size size) {
    final window = createWindow(size: size);
    if (window == null) return null;
    workspaceNotifier(window.id).attachTab(tab);
    _activate(window.id);
    return window;
  }

  /// Creates the native window and its workspace scope. Overridable so hosts
  /// that cannot open windows (tests) can drive the rest of the controller.
  @protected
  @visibleForTesting
  WorkspaceWindow? createWindow({Size? size}) {
    final windowSize = size ?? _defaultWindowSize;
    final id = _uuid.v4();
    final controller = fw.RegularWindowController(
      size: windowSize,
      constraints: BoxConstraints(
        minWidth: _minimumWindowSize.width,
        minHeight: _minimumWindowSize.height,
      ),
      title: 'MaidTerm',
      delegate: _WorkspaceWindowDelegate(() => unawaited(closeWindow(id))),
    );
    final window = WorkspaceWindow(id: id, controller: controller);
    final native = nativeWindowOf(controller);
    if (native != null) {
      // Put the strip where the title bar would be, so the traffic lights still
      // work; elsewhere the title bar has to go, and the frame drags instead.
      if (!native.setContentUnderTitleBar(true)) {
        native.titleBarStyle = na.TitleBarStyle.hidden;
      }
      native.contentSize = windowSize.toNative();
      // The tree paints every surface, including the rounded window corners,
      // so the window itself stays clear and non-opaque.
      native.backgroundColor = const Color(0x00000000).toNative();
      window.native = native;
    }
    return registerWindow(window);
  }

  /// Takes ownership of [window]: subscribes to its workspace, tracks its
  /// focus and announces it to the tree.
  @protected
  @visibleForTesting
  WorkspaceWindow registerWindow(WorkspaceWindow window) {
    final id = window.id;
    final controller = window.controller;
    _windows.add(window);
    _workspaceSubscriptions[id] = _ref.listen(
      terminalWorkspaceProvider(id),
      (previous, next) => _handleWorkspaceState(id, previous, next),
    );
    controller?.addListener(() {
      if (controller.isActivated) _activate(id);
      _refreshFocus();
    });
    notifyListeners();
    return window;
  }

  /// Asks before closing a window that still runs programs.
  Future<void> closeWindow(String windowId, {bool confirm = true}) async {
    final window = windowById(windowId);
    if (window == null || !_closingWindows.add(windowId)) return;
    try {
      final sessions = [
        for (final tab in workspaceState(windowId).tabs)
          for (final pane in tab.panes.values) pane.tab.session,
      ];
      if (sessions.isNotEmpty) {
        if (confirm &&
            !await confirmCloseSessions(sessions, id: 'close-window:$windowId')) {
          return;
        }
        await workspaceNotifier(windowId).closeAll();
      }
      _removeWindow(window);
    } finally {
      _closingWindows.remove(windowId);
    }
  }

  /// Closes [windowId] when its last tab is gone and other windows remain, so
  /// the app keeps running with a window to spare.
  Future<void> closeWindowIfEmpty(String windowId) async {
    if (workspaceState(windowId).tabs.isNotEmpty) return;
    if (_windows.length <= 1) return;
    await closeWindow(windowId, confirm: false);
  }

  void _destroyWindow(WorkspaceWindow window) {
    if (!_windows.remove(window)) return;
    _workspaceSubscriptions.remove(window.id)?.close();
    _ref.invalidate(terminalWorkspaceProvider(window.id));
    if (_drag?.windowId == window.id) {
      _drag = null;
      _session?.cancel();
    }
    _closingWindows.remove(window.id);
    if (_activeWindowId == window.id) {
      _activeWindowId = _windows.isEmpty ? null : _windows.first.id;
    }
    notifyListeners();
    // The window can only go once a frame has rendered without its view.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      window.controller?.destroy();
      if (_windows.isEmpty) _quit();
    });
    SchedulerBinding.instance.scheduleFrame();
  }

  void _removeWindow(WorkspaceWindow window) => _destroyWindow(window);

  void _handleWorkspaceState(
    String windowId,
    TerminalWorkspaceState? previous,
    TerminalWorkspaceState next,
  ) {
    // Only a window that had tabs and lost them all closes itself; a window
    // that has not been given its first tab yet must stay.
    if (next.tabs.isNotEmpty || (previous?.tabs.isEmpty ?? true)) return;
    unawaited(closeWindowIfEmpty(windowId));
  }

  void _activate(String windowId) {
    _refreshFocus();
    if (_activeWindowId == windowId) return;
    _activeWindowId = windowId;
    notifyListeners();
  }

  void _refreshFocus() => _appFocus.value = anyWindowFocused;

  void _quit() {
    ServicesBinding.instance.exitApplication(AppExitType.required);
  }

  // ---------------------------------------------------------------------------
  // Tab dragging

  /// Starts a native drag for [tabId]; returns false when the platform cannot
  /// track the cursor, so the strip falls back to reordering on its own.
  bool beginTabDrag({
    required String windowId,
    required String tabId,
    required Offset grab,
    required Offset grabInView,
    required Size chipSize,
    required Offset pointerInView,
  }) {
    final session = _session;
    final window = windowById(windowId);
    final native = window?.native;
    if (session == null ||
        native == null ||
        !_sessionTracksCursor ||
        _drag != null) {
      return false;
    }
    if (!session.start(null, Offset.zero.toNative())) return false;
    _drag = _WorkspaceTabDrag(
      tabId: tabId,
      windowId: windowId,
      grab: grab,
      grabInView: grabInView,
      chipSize: chipSize,
      pressCursor: native.contentBounds.toRect().topLeft + pointerInView,
      cursor: native.contentBounds.toRect().topLeft + pointerInView,
      mode: TabDragMode.pending,
    );
    return true;
  }

  /// Fallback for platforms without a usable native drag session: reorders
  /// within the strip from Flutter pointer positions only.
  void beginLocalTabDrag({
    required String windowId,
    required String tabId,
    required Offset grab,
    required Offset grabInView,
    required Size chipSize,
    required Offset pointerInView,
  }) {
    final native = windowById(windowId)?.native;
    if (_drag != null) return;
    final cursor = (native?.contentBounds.toRect().topLeft ?? Offset.zero) +
        pointerInView;
    _drag = _WorkspaceTabDrag(
      tabId: tabId,
      windowId: windowId,
      grab: grab,
      grabInView: grabInView,
      chipSize: chipSize,
      pressCursor: cursor,
      cursor: cursor,
      mode: TabDragMode.inStrip,
    );
    notifyListeners();
  }

  void updateLocalTabDrag(Offset pointerInView) {
    final drag = _drag;
    final native = windowById(drag?.windowId)?.native;
    if (drag == null || native == null) return;
    drag.cursor = native.contentBounds.toRect().topLeft + pointerInView;
    if (drag.mode == TabDragMode.inStrip) _moveInStrip(drag);
  }

  void endLocalTabDrag() {
    final drag = _drag;
    if (drag == null) return;
    _drag = null;
    notifyListeners();
  }

  void _handleDragEvent(na.WindowDragEvent event) {
    final drag = _drag;
    switch (event) {
      case na.WindowDragMovedEvent(:final cursorPosition):
        if (drag == null) return;
        _handleMove(drag, cursorPosition.toOffset());
      case na.WindowDragEndedEvent():
        if (drag == null) return;
        _drag = null;
        if (drag.mode == TabDragMode.window) {
          windowById(drag.windowId)?.native?.focus();
        }
        notifyListeners();
      case na.WindowDragCancelledEvent():
        if (drag != null && drag.mode == TabDragMode.pending) {
          // No move ever arrived: the platform cannot read the cursor.
          _sessionTracksCursor = false;
        }
        _drag = null;
        notifyListeners();
    }
  }

  void _handleMove(_WorkspaceTabDrag drag, Offset cursor) {
    drag.cursor = cursor;
    switch (drag.mode) {
      case TabDragMode.pending:
        if ((cursor - drag.pressCursor).distance < _tabDragSlop) return;
        drag.mode = TabDragMode.inStrip;
        _moveInStrip(drag);
      case TabDragMode.inStrip:
        _moveInStrip(drag);
      case TabDragMode.window:
        final target = _windowWithStripAt(cursor, excludingId: drag.windowId);
        if (target == null) {
          notifyListeners();
          return;
        }
        _mergeInto(drag, target);
    }
  }

  void _moveInStrip(_WorkspaceTabDrag drag) {
    final window = windowById(drag.windowId);
    final native = window?.native;
    if (window == null || native == null) return;
    final strip = window.strip.stripRect(native);
    if (strip == null) return;

    final axis = window.strip.axis;
    final outside = axis == Axis.horizontal
        ? drag.cursor.dy < strip.top - _tabDetachMargin ||
              drag.cursor.dy > strip.bottom + _tabDetachMargin
        : drag.cursor.dx < strip.left - _tabDetachMargin ||
              drag.cursor.dx > strip.right + _tabDetachMargin;
    if (outside && nativeTabDragAvailable) {
      _tearOff(drag);
      return;
    }

    final tabs = workspaceState(window.id).tabs;
    final tabsInPane = [for (final tab in tabs) tab.id];
    if (!tabsInPane.contains(drag.tabId)) return;
    final index = tabInsertionIndex(
      cursor: drag.cursor,
      axis: axis,
      orderedTabIds: tabsInPane,
      draggedTabId: drag.tabId,
      rectOf: (tabId) => window.strip.tabRect(native, tabId),
    );
    workspaceNotifier(window.id).moveTab(drag.tabId, index);
    notifyListeners();
  }

  void _tearOff(_WorkspaceTabDrag drag) {
    final session = _session;
    final source = windowById(drag.windowId);
    final sourceNative = source?.native;
    if (session == null || source == null || sourceNative == null) return;

    if (workspaceState(source.id).tabs.length <= 1) {
      // Nothing would be left behind: carry the whole window instead.
      session.start(
        sourceNative,
        (sourceNative.contentInset + drag.grabInView).toNative(),
      );
      drag.mode = TabDragMode.window;
      notifyListeners();
      return;
    }

    final size = sourceNative.contentSize.toSize();
    final tab = workspaceNotifier(source.id).takeTab(drag.tabId);
    if (tab == null) return;
    final torn = _adoptTab(tab, size);
    final tornNative = torn?.native;
    if (torn == null) {
      // The window could not be created; put the tab back where it was.
      workspaceNotifier(source.id).attachTab(tab);
      _drag = null;
      session.cancel();
      notifyListeners();
      return;
    }
    if (tornNative == null ||
        !session.start(
          tornNative,
          (tornNative.contentInset + drag.grabInView).toNative(),
        )) {
      // The new window cannot follow the cursor; leave it where it is.
      _drag = null;
      session.cancel();
      notifyListeners();
      return;
    }
    drag
      ..windowId = torn.id
      ..mode = TabDragMode.window;
    tornNative.focus();
    notifyListeners();
  }

  void _mergeInto(_WorkspaceTabDrag drag, WorkspaceWindow target) {
    final session = _session;
    final targetNative = target.native;
    final source = windowById(drag.windowId);
    if (session == null || targetNative == null || source == null) return;

    // Stop moving the dragged window before it goes away; the gesture carries
    // on as a drag along the target's strip.
    session.start(null, Offset.zero.toNative());
    final tab = workspaceNotifier(source.id).takeTab(drag.tabId);
    if (tab == null) return;
    drag
      ..windowId = target.id
      ..mode = TabDragMode.inStrip;
    workspaceNotifier(target.id).attachTab(tab);
    if (workspaceState(source.id).tabs.isEmpty) _destroyWindow(source);
    targetNative.focus();
    _moveInStrip(drag);
    notifyListeners();
  }

  /// The window whose tab strip is under [cursor] and not covered by another
  /// application, looking through the window being dragged.
  WorkspaceWindow? _windowWithStripAt(
    Offset cursor, {
    required String excludingId,
  }) {
    final excluded = windowById(excludingId)?.native?.id ?? 0;
    final hit = na.WindowManager.instance.getWindowAtPoint(
      cursor.toNative(),
      excluded,
    );
    if (hit == null) return null;
    for (final window in _windows) {
      final native = window.native;
      if (window.id == excludingId || native == null || native.id != hit.id) {
        continue;
      }
      final strip = window.strip.stripRect(native);
      return strip != null && strip.contains(cursor) ? window : null;
    }
    return null;
  }

  @override
  void dispose() {
    _session?.cancel();
    final dragEventListener = _dragEventListener;
    if (dragEventListener != null) _session?.removeListener(dragEventListener);
    _session?.dispose();
    for (final subscription in _workspaceSubscriptions.values) {
      subscription.close();
    }
    _workspaceSubscriptions.clear();
    for (final window in [..._windows]) {
      window.controller?.destroy();
    }
    _windows.clear();
    super.dispose();
  }
}

/// Live state of one tab drag.
class _WorkspaceTabDrag {
  _WorkspaceTabDrag({
    required this.tabId,
    required this.windowId,
    required this.grab,
    required this.grabInView,
    required this.chipSize,
    required this.pressCursor,
    required this.cursor,
    required this.mode,
  });

  final String tabId;
  String windowId;

  /// Grab point inside the chip.
  final Offset grab;

  /// Grab point in the coordinates of the window it was pressed in, which is
  /// where a torn-off window puts the pointer back.
  final Offset grabInView;
  final Size chipSize;
  final Offset pressCursor;

  /// Latest cursor position, in screen coordinates.
  Offset cursor;
  TabDragMode mode;
}

class _WorkspaceWindowDelegate with fw.RegularWindowControllerDelegate {
  _WorkspaceWindowDelegate(this._onCloseRequested);

  final VoidCallback _onCloseRequested;

  @override
  void onWindowCloseRequested(fw.RegularWindowController controller) {
    // The window outlives this call while the user confirms.
    _onCloseRequested();
  }
}

/// Every open window, for the root of the widget tree.
final workspaceWindowsProvider = Provider<WorkspaceWindowsController>((ref) {
  final controller = WorkspaceWindowsController(ref);
  ref.onDispose(controller.dispose);
  return controller;
});
