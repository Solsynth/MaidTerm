import 'terminal_workspace.dart';
import 'session_layout.dart';

/// A serializable description of a workspace tab while it moves between
/// Flutter engines. Each pane carries the stable native PTY session ID so the
/// destination attaches to the running process instead of recreating a shell.
class WorkspaceTabTransfer {
  const WorkspaceTabTransfer({
    required this.id,
    required this.focusedPaneId,
    required this.panes,
    required this.layout,
  });

  factory WorkspaceTabTransfer.fromTab(TerminalWorkspaceTab tab) {
    return WorkspaceTabTransfer(
      id: tab.id,
      focusedPaneId: tab.focusedPaneId,
      panes: [
        for (final pane in tab.panes.values)
          WorkspacePaneTransfer(
            id: pane.id,
            tabId: pane.tab.id,
            sessionId: pane.tab.sessionId,
            workingDirectory: pane.tab.session.workingDirectory,
          ),
      ],
      layout: _layoutToJson(tab.layout),
    );
  }

  factory WorkspaceTabTransfer.fromJson(Map<dynamic, dynamic> json) {
    return WorkspaceTabTransfer(
      id: json['id'] as String,
      focusedPaneId: json['focusedPaneId'] as String,
      panes: [
        for (final pane in (json['panes'] as List<dynamic>? ?? const []))
          WorkspacePaneTransfer.fromJson(pane as Map<dynamic, dynamic>),
      ],
      layout: json['layout'] as Map<dynamic, dynamic>,
    );
  }

  final String id;
  final String focusedPaneId;
  final List<WorkspacePaneTransfer> panes;
  final Map<dynamic, dynamic> layout;

  Map<String, dynamic> toJson() => {
    'id': id,
    'focusedPaneId': focusedPaneId,
    'panes': [for (final pane in panes) pane.toJson()],
    'layout': layout,
  };

  static Map<String, dynamic> _layoutToJson(PaneLayout layout) {
    return switch (layout) {
      PaneLayoutLeaf(:final paneId) => {'type': 'leaf', 'paneId': paneId},
      PaneLayoutSplit(
        :final id,
        :final axis,
        :final first,
        :final second,
        :final ratio,
      ) =>
        {
          'type': 'split',
          'id': id,
          'axis': axis.name,
          'first': _layoutToJson(first),
          'second': _layoutToJson(second),
          'ratio': ratio,
        },
    };
  }

  static PaneLayout layoutFromJson(Map<dynamic, dynamic> json) {
    return switch (json['type']) {
      'leaf' => PaneLayoutLeaf(json['paneId'] as String),
      'split' => PaneLayoutSplit(
        id: json['id'] as String,
        axis: SplitAxis.values.byName(json['axis'] as String),
        first: layoutFromJson(json['first'] as Map<dynamic, dynamic>),
        second: layoutFromJson(json['second'] as Map<dynamic, dynamic>),
        ratio: (json['ratio'] as num?)?.toDouble() ?? 0.5,
      ),
      _ => throw FormatException('Unknown pane layout type'),
    };
  }
}

class WorkspacePaneTransfer {
  const WorkspacePaneTransfer({
    required this.id,
    required this.tabId,
    required this.sessionId,
    required this.workingDirectory,
  });

  factory WorkspacePaneTransfer.fromJson(Map<dynamic, dynamic> json) {
    return WorkspacePaneTransfer(
      id: json['id'] as String,
      tabId: json['tabId'] as String,
      sessionId: (json['sessionId'] as num?)?.toInt(),
      workingDirectory: json['workingDirectory'] as String? ?? '',
    );
  }

  final String id;
  final String tabId;
  final int? sessionId;
  final String workingDirectory;

  Map<String, dynamic> toJson() => {
    'id': id,
    'tabId': tabId,
    'sessionId': sessionId,
    'workingDirectory': workingDirectory,
  };
}
