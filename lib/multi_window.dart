import 'dart:async';
import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'window_runtime.dart';
import 'workspace/terminal_workspace.dart';
import 'workspace/window_tab_transfer.dart';

final multiWindowCoordinatorProvider = Provider<MultiWindowCoordinator>((ref) {
  final coordinator = MultiWindowCoordinator(
    ref,
    ref.read(windowLaunchDataProvider),
  );
  ref.listen<TerminalWorkspaceState>(
    terminalWorkspaceProvider,
    (_, next) => coordinator.handleWorkspaceState(next),
  );
  unawaited(coordinator.initialize());
  ref.onDispose(coordinator.dispose);
  return coordinator;
});

class ExternalWorkspaceDrag {
  const ExternalWorkspaceDrag({
    required this.sourceWindowId,
    required this.tab,
  });

  final String sourceWindowId;
  final WorkspaceTabTransfer tab;
}

/// Coordinates tab transfer between the independent Flutter engines created by
/// desktop_multi_window.
class MultiWindowCoordinator {
  MultiWindowCoordinator(this._ref, this._launch);

  final Ref _ref;
  final WindowLaunchData _launch;
  final externalDrag = ValueNotifier<ExternalWorkspaceDrag?>(null);
  final Set<String> _externallyAccepted = <String>{};
  var _suppressEmptyWindowClose = false;
  var _closingEmptyWindow = false;

  WindowController? get _currentWindow => _launch.window;
  String get windowId => _currentWindow?.windowId ?? '';

  Future<void> initialize() async {
    final current = _currentWindow;
    if (current == null) return;
    await current.setWindowMethodHandler(_handleWindowMethod);
  }

  void handleWorkspaceState(TerminalWorkspaceState state) {
    if (state.tabs.isNotEmpty ||
        _suppressEmptyWindowClose ||
        _closingEmptyWindow ||
        !_launch.isWorkspaceWindow) {
      return;
    }
    _closingEmptyWindow = true;
    unawaited(_closeEmptyWorkspaceWindow());
  }

  Future<void> _closeEmptyWorkspaceWindow() async {
    try {
      if ((await WindowController.getAll()).length > 1) {
        await windowManager.close();
      }
    } finally {
      _closingEmptyWindow = false;
    }
  }

  Future<dynamic> _handleWindowMethod(MethodCall call) async {
    final args = call.arguments is Map
        ? Map<dynamic, dynamic>.from(call.arguments as Map)
        : <dynamic, dynamic>{};
    switch (call.method) {
      case 'window_get_bounds':
        final bounds = await windowManager.getBounds();
        return {
          'left': bounds.left,
          'top': bounds.top,
          'right': bounds.right,
          'bottom': bounds.bottom,
        };
      case 'window_has_active_drag':
        return externalDrag.value != null;
      case 'window_prepare_drag':
        final sourceWindowId = args['sourceWindowId'] as String?;
        final tabJson = args['tab'];
        if (sourceWindowId == null || tabJson is! Map) return false;
        externalDrag.value = ExternalWorkspaceDrag(
          sourceWindowId: sourceWindowId,
          tab: WorkspaceTabTransfer.fromJson(tabJson),
        );
        return true;
      case 'window_drag_cancelled':
        externalDrag.value = null;
        return true;
      case 'window_receive_tab':
        final tabJson = args['tab'];
        if (tabJson is! Map) return false;
        _ref
            .read(terminalWorkspaceProvider.notifier)
            .importTab(WorkspaceTabTransfer.fromJson(tabJson));
        externalDrag.value = null;
        return true;
      case 'window_merge_tab':
        return _mergeIntoWindow(args);
      default:
        return null;
    }
  }

  Future<void> dragStarted(WorkspaceTabTransfer tab) async {
    final current = _currentWindow;
    if (current == null) return;
    final windows = await WindowController.getAll();
    for (final window in windows) {
      if (window.windowId == current.windowId) continue;
      await window.invokeMethod<bool>('window_prepare_drag', {
        'sourceWindowId': current.windowId,
        'tab': tab.toJson(),
      });
    }
  }

  void dragEnded(
    WorkspaceTabTransfer tab, {
    required DraggableDetails details,
  }) {
    unawaited(_finishDrag(tab, details: details));
  }

  Future<void> _finishDrag(
    WorkspaceTabTransfer tab, {
    required DraggableDetails details,
  }) async {
    // A drop in another Flutter engine reaches that engine first, then calls
    // back into this engine. Leave a small ordering window before tearing out.
    try {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (details.wasAccepted) return;
      if (_externallyAccepted.remove(tab.id)) return;
      if (await _mergeAtGlobalOffset(tab, details.offset)) return;
      await tearOut(tab);
    } finally {
      await _cancelDragOnOtherWindows();
    }
  }

  Future<bool> _mergeAtGlobalOffset(
    WorkspaceTabTransfer tab,
    Offset offset,
  ) async {
    final current = _currentWindow;
    if (current == null) return false;
    final windows = await WindowController.getAll();
    final candidates = <WindowController>[];
    for (final window in windows) {
      if (window.windowId == current.windowId) continue;
      var isTarget = false;
      try {
        final bounds = await window.invokeMethod<Map<dynamic, dynamic>>(
          'window_get_bounds',
        );
        if (bounds != null) {
          final rect = Rect.fromLTRB(
            (bounds['left'] as num).toDouble(),
            (bounds['top'] as num).toDouble(),
            (bounds['right'] as num).toDouble(),
            (bounds['bottom'] as num).toDouble(),
          );
          isTarget = rect.contains(offset);
        }
      } on Object {
        // The target may still be registering its window channels.
      }
      if (!isTarget) {
        try {
          isTarget =
              await window.invokeMethod<bool>('window_has_active_drag') == true;
        } on Object {
          continue;
        }
      }
      if (isTarget) candidates.add(window);
    }

    for (final window in candidates) {
      try {
        final accepted = await window.invokeMethod<bool>('window_receive_tab', {
          'tab': tab.toJson(),
        });
        if (accepted == true) {
          _detachTransferredTab(tab.id);
          return true;
        }
      } on Object {
        // Try the next candidate, then fall back to creating a new window.
      }
    }
    return false;
  }

  Future<void> acceptExternalDrag() async {
    final drag = externalDrag.value;
    if (drag == null) return;
    externalDrag.value = null;
    final source = WindowController.fromWindowId(drag.sourceWindowId);
    await source.invokeMethod<bool>('window_merge_tab', {
      'targetWindowId': windowId,
      'tab': drag.tab.toJson(),
    });
  }

  Future<dynamic> _mergeIntoWindow(Map<dynamic, dynamic> args) async {
    final targetId = args['targetWindowId'] as String?;
    final tabJson = args['tab'];
    if (targetId == null || tabJson is! Map) return false;
    final transfer = WorkspaceTabTransfer.fromJson(tabJson);
    final group = _ref
        .read(terminalWorkspaceProvider)
        .tabs
        .firstWhereOrNull((tab) => tab.id == transfer.id);
    if (group == null) return false;

    final target = WindowController.fromWindowId(targetId);
    final accepted = await target.invokeMethod<bool>('window_receive_tab', {
      'tab': transfer.toJson(),
    });
    if (accepted != true) return false;
    _detachTransferredTab(transfer.id);
    return true;
  }

  Future<void> openNewWindow() async {
    if (_currentWindow == null) return;
    final window = await _createWindow();
    await window.show();
  }

  Future<void> tearOut(WorkspaceTabTransfer tab) async {
    if (_currentWindow == null) return;
    final window = await _createWindow(tab: tab);
    await window.show();
    _detachTransferredTab(tab.id);
  }

  void _detachTransferredTab(String tabId) {
    _suppressEmptyWindowClose = true;
    try {
      _ref.read(terminalWorkspaceProvider.notifier).detachTab(tabId);
    } finally {
      _suppressEmptyWindowClose = false;
    }
  }

  Future<WindowController> _createWindow({WorkspaceTabTransfer? tab}) {
    return WindowController.create(
      WindowConfiguration(
        hiddenAtLaunch: true,
        arguments: jsonEncode({
          'type': maidTermWorkspaceWindow,
          if (tab != null) 'tab': tab.toJson(),
        }),
      ),
    );
  }

  Future<void> _cancelDragOnOtherWindows() async {
    final current = _currentWindow;
    if (current == null) return;
    final windows = await WindowController.getAll();
    for (final window in windows) {
      if (window.windowId == current.windowId) continue;
      try {
        await window.invokeMethod<bool>('window_drag_cancelled');
      } on Object {
        // A window can disappear while the drag is finishing.
      }
    }
  }

  void dispose() {
    externalDrag.dispose();
  }
}

extension on List<TerminalWorkspaceTab> {
  TerminalWorkspaceTab? firstWhereOrNull(
    bool Function(TerminalWorkspaceTab tab) test,
  ) {
    for (final tab in this) {
      if (test(tab)) return tab;
    }
    return null;
  }
}
