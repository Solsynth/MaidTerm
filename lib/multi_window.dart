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

const windowTransferProtocolVersion = 1;

enum _MergeOutcome { accepted, rejectedTarget, noTarget }

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
    required this.protocol,
    required this.requestId,
    required this.sourceWindowId,
    required this.tab,
  });

  final int protocol;
  final String requestId;
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
  final Map<String, String> _receivedRequests = <String, String>{};
  final Map<String, String> _dragRequests = <String, String>{};
  final Map<String, Future<void>> _dragPreparations = <String, Future<void>>{};
  var _requestCounter = 0;
  var _suppressEmptyWindowClose = false;
  var _closingEmptyWindow = false;

  WindowController? get _currentWindow => _launch.window;
  String get windowId => _currentWindow?.windowId ?? '';

  String _newRequestId() =>
      '$windowId-${DateTime.now().microsecondsSinceEpoch}-${++_requestCounter}';

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

  Map<dynamic, dynamic>? _mapArgs(dynamic arguments) =>
      arguments is Map ? Map<dynamic, dynamic>.from(arguments) : null;

  bool _validProtocol(Map<dynamic, dynamic> args) =>
      args['protocol'] == windowTransferProtocolVersion &&
      args['requestId'] is String &&
      (args['requestId'] as String).isNotEmpty;

  Future<dynamic> _handleWindowMethod(MethodCall call) async {
    final args = _mapArgs(call.arguments);
    if (args == null && call.method != 'window_get_bounds') {
      return {'accepted': false, 'error': 'invalid_arguments'};
    }
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
        if (!_validProtocol(args!) || args['sourceWindowId'] is! String) {
          return {'accepted': false, 'error': 'invalid_prepare_request'};
        }
        final tabJson = args['tab'];
        if (tabJson is! Map) {
          return {'accepted': false, 'error': 'missing_tab'};
        }
        try {
          externalDrag.value = ExternalWorkspaceDrag(
            protocol: windowTransferProtocolVersion,
            requestId: args['requestId'] as String,
            sourceWindowId: args['sourceWindowId'] as String,
            tab: WorkspaceTabTransfer.fromJson(tabJson),
          );
          return {'accepted': true};
        } on Object catch (error) {
          return {'accepted': false, 'error': '$error'};
        }
      case 'window_drag_cancelled':
        if (!_validProtocol(args!)) {
          return {'accepted': false, 'error': 'invalid_cancel_request'};
        }
        if (externalDrag.value?.requestId == args['requestId']) {
          externalDrag.value = null;
        }
        return {'accepted': true};
      case 'window_receive_tab':
        return _receiveTab(args!);
      case 'window_merge_tab':
        return _mergeIntoWindow(args!);
      default:
        return null;
    }
  }

  Future<Map<String, dynamic>> _receiveTab(Map<dynamic, dynamic> args) async {
    if (!_validProtocol(args) || args['sourceWindowId'] is! String) {
      return {'accepted': false, 'error': 'invalid_receive_request'};
    }
    final requestId = args['requestId'] as String;
    final tabJson = args['tab'];
    if (tabJson is! Map) return {'accepted': false, 'error': 'missing_tab'};
    final transfer = WorkspaceTabTransfer.fromJson(tabJson);
    final previousTabId = _receivedRequests[requestId];
    if (previousTabId != null) {
      _ref.read(terminalWorkspaceProvider.notifier).selectTab(previousTabId);
      externalDrag.value = null;
      return {'accepted': true};
    }
    try {
      final imported = _ref
          .read(terminalWorkspaceProvider.notifier)
          .importTab(transfer);
      if (!imported) return {'accepted': false, 'error': 'import_rejected'};
      _receivedRequests[requestId] = transfer.id;
      externalDrag.value = null;
      return {'accepted': true};
    } on Object catch (error) {
      return {'accepted': false, 'error': '$error'};
    }
  }

  Future<void> dragStarted(WorkspaceTabTransfer tab) async {
    final current = _currentWindow;
    if (current == null) return;
    final requestId = _newRequestId();
    _dragRequests[tab.id] = requestId;
    final preparation = _prepareDrag(
      tab,
      requestId: requestId,
      currentWindow: current,
    );
    _dragPreparations[requestId] = preparation;
    await preparation;
  }

  Future<void> _prepareDrag(
    WorkspaceTabTransfer tab, {
    required String requestId,
    required WindowController currentWindow,
  }) async {
    final windows = await WindowController.getAll();
    for (final window in windows) {
      if (window.windowId == currentWindow.windowId) continue;
      try {
        await window.invokeMethod<dynamic>('window_prepare_drag', {
          'protocol': windowTransferProtocolVersion,
          'requestId': requestId,
          'sourceWindowId': currentWindow.windowId,
          'tab': tab.toJson(),
        });
      } on Object {
        // A window can be registering its method handler while the drag starts.
      }
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
    final requestId = _dragRequests[tab.id] ?? _newRequestId();
    final preparation = _dragPreparations[requestId];
    if (preparation != null) {
      await preparation.timeout(const Duration(seconds: 1), onTimeout: () {});
    }
    try {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (details.wasAccepted) return;
      if (_externallyAccepted.remove(requestId)) return;
      final mergeOutcome = await _mergeAtGlobalOffset(
        tab,
        details.offset,
        requestId,
      );
      if (mergeOutcome == _MergeOutcome.accepted ||
          mergeOutcome == _MergeOutcome.rejectedTarget) {
        return;
      }
      await tearOut(tab, requestId: requestId);
    } finally {
      _dragPreparations.remove(requestId);
      _dragRequests.remove(tab.id);
      await _cancelDragOnOtherWindows(requestId);
    }
  }

  Future<List<WindowController>> _findMergeCandidates(Offset offset) async {
    final current = _currentWindow;
    if (current == null) return const [];
    Offset? currentOrigin;
    try {
      final bounds = await windowManager.getBounds();
      currentOrigin = Offset(bounds.left, bounds.top);
    } on Object {
      // The current engine may not expose bounds during window startup.
    }
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
          isTarget =
              rect.contains(offset) ||
              (currentOrigin != null && rect.contains(offset + currentOrigin));
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
    return candidates;
  }

  Future<_MergeOutcome> _mergeAtGlobalOffset(
    WorkspaceTabTransfer tab,
    Offset offset,
    String requestId,
  ) async {
    final current = _currentWindow;
    if (current == null) return _MergeOutcome.noTarget;
    var candidates = <WindowController>[];
    for (var discoveryAttempt = 0; discoveryAttempt < 10; discoveryAttempt++) {
      candidates = await _findMergeCandidates(offset);
      if (candidates.isNotEmpty) break;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (candidates.isEmpty) return _MergeOutcome.noTarget;

    for (final window in candidates) {
      for (var attempt = 0; attempt < 4; attempt++) {
        try {
          final result = await window.invokeMethod<dynamic>(
            'window_receive_tab',
            {
              'protocol': windowTransferProtocolVersion,
              'requestId': requestId,
              'sourceWindowId': current.windowId,
              'tab': tab.toJson(),
            },
          );
          if (result is Map && result['accepted'] == true) {
            _detachTransferredTab(tab.id, suppressEmptyWindowClose: false);
            return _MergeOutcome.accepted;
          }
          if (result is Map && result['error'] != 'invalid_arguments') break;
        } on Object {
          // Retry while the target engine finishes registering its handler.
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
    return _MergeOutcome.rejectedTarget;
  }

  Future<void> acceptExternalDrag() async {
    final drag = externalDrag.value;
    if (drag == null) return;
    final source = WindowController.fromWindowId(drag.sourceWindowId);
    for (var attempt = 0; attempt < 4; attempt++) {
      try {
        final result = await source.invokeMethod<dynamic>('window_merge_tab', {
          'protocol': windowTransferProtocolVersion,
          'requestId': drag.requestId,
          'targetWindowId': windowId,
          'tab': drag.tab.toJson(),
        });
        if (result is Map && result['accepted'] == true) {
          externalDrag.value = null;
          return;
        }
      } on Object {
        // Retry while the source engine finishes the merge handshake.
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  Future<Map<String, dynamic>> _mergeIntoWindow(
    Map<dynamic, dynamic> args,
  ) async {
    if (!_validProtocol(args) || args['targetWindowId'] is! String) {
      return {'accepted': false, 'error': 'invalid_merge_request'};
    }
    final tabJson = args['tab'];
    if (tabJson is! Map) return {'accepted': false, 'error': 'missing_tab'};
    final transfer = WorkspaceTabTransfer.fromJson(tabJson);
    final group = _ref
        .read(terminalWorkspaceProvider)
        .tabs
        .firstWhereOrNull((tab) => tab.id == transfer.id);
    if (group == null) {
      return {'accepted': false, 'error': 'source_tab_missing'};
    }

    final target = WindowController.fromWindowId(
      args['targetWindowId'] as String,
    );
    final result = await target.invokeMethod<dynamic>('window_receive_tab', {
      'protocol': windowTransferProtocolVersion,
      'requestId': args['requestId'],
      'sourceWindowId': windowId,
      'tab': transfer.toJson(),
    });
    if (result is! Map || result['accepted'] != true) {
      return {
        'accepted': false,
        'error': result is Map
            ? result['error'] ?? 'target_rejected'
            : 'target_rejected',
      };
    }
    _externallyAccepted.add(args['requestId'] as String);
    _detachTransferredTab(transfer.id, suppressEmptyWindowClose: false);
    return {'accepted': true};
  }

  Future<void> openNewWindow() async {
    if (_currentWindow == null) return;
    final window = await _createWindow();
    await window.show();
  }

  Future<void> tearOut(
    WorkspaceTabTransfer tab, {
    required String requestId,
  }) async {
    final current = _currentWindow;
    if (current == null) return;
    final window = await _createWindow(
      tab: tab,
      requestId: requestId,
      sourceWindowId: current.windowId,
    );
    await window.show();
    final result = await _waitForReceive(
      window,
      requestId,
      tab,
      current.windowId,
    );
    if (result) _detachTransferredTab(tab.id);
  }

  Future<bool> _waitForReceive(
    WindowController window,
    String requestId,
    WorkspaceTabTransfer tab,
    String sourceWindowId,
  ) async {
    for (var attempt = 0; attempt < 20; attempt++) {
      try {
        final response = await window.invokeMethod<dynamic>(
          'window_receive_tab',
          {
            'protocol': windowTransferProtocolVersion,
            'requestId': requestId,
            'sourceWindowId': sourceWindowId,
            'tab': tab.toJson(),
          },
        );
        if (response is Map && response['accepted'] == true) return true;
      } on Object {
        // Child engine is still registering its method handler.
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return false;
  }

  void _detachTransferredTab(
    String tabId, {
    bool suppressEmptyWindowClose = true,
  }) {
    final notifier = _ref.read(terminalWorkspaceProvider.notifier);
    if (!suppressEmptyWindowClose) {
      notifier.detachTab(tabId, disposeSessions: false);
      return;
    }
    _suppressEmptyWindowClose = true;
    try {
      notifier.detachTab(tabId, disposeSessions: false);
    } finally {
      _suppressEmptyWindowClose = false;
    }
  }

  Future<WindowController> _createWindow({
    WorkspaceTabTransfer? tab,
    String? requestId,
    String? sourceWindowId,
  }) {
    return WindowController.create(
      WindowConfiguration(
        hiddenAtLaunch: true,
        arguments: jsonEncode({
          'protocol': windowTransferProtocolVersion,
          'type': maidTermWorkspaceWindow,
          'hiddenAtLaunch': true,
          'requestId': requestId,
          'sourceWindowId': sourceWindowId,
          if (tab != null) 'tab': tab.toJson(),
        }),
      ),
    );
  }

  Future<void> _cancelDragOnOtherWindows(String requestId) async {
    final current = _currentWindow;
    if (current == null) return;
    final windows = await WindowController.getAll();
    for (final window in windows) {
      if (window.windowId == current.windowId) continue;
      try {
        await window.invokeMethod<dynamic>('window_drag_cancelled', {
          'protocol': windowTransferProtocolVersion,
          'requestId': requestId,
        });
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
