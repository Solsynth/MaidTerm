import 'dart:async';
import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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

  void dragEnded(WorkspaceTabTransfer tab, {required bool wasAccepted}) {
    unawaited(_finishDrag(tab, wasAccepted: wasAccepted));
  }

  Future<void> _finishDrag(
    WorkspaceTabTransfer tab, {
    required bool wasAccepted,
  }) async {
    // A drop in another Flutter engine reaches that engine first, then calls
    // back into this engine. Leave a small ordering window before tearing out.
    await Future<void>.delayed(const Duration(milliseconds: 180));
    if (wasAccepted) {
      await _cancelDragOnOtherWindows();
      return;
    }
    if (_externallyAccepted.remove(tab.id)) {
      await _cancelDragOnOtherWindows();
      return;
    }
    await tearOut(tab);
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
    _externallyAccepted.add(transfer.id);
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
    await _cancelDragOnOtherWindows();
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
      await window.invokeMethod<bool>('window_drag_cancelled');
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
