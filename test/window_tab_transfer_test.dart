import 'package:flutter_test/flutter_test.dart';
import 'package:maidterm_app/workspace/session_layout.dart';
import 'package:maidterm_app/workspace/window_tab_transfer.dart';

void main() {
  test('transfer payload preserves native session IDs and layout identity', () {
    final transfer = WorkspaceTabTransfer.fromJson({
      'id': 'group-1',
      'focusedPaneId': 'pane-1',
      'panes': [
        {
          'id': 'pane-1',
          'tabId': 'tab-1',
          'sessionId': 4242,
          'workingDirectory': '/tmp/session',
        },
      ],
      'layout': {'type': 'leaf', 'paneId': 'pane-1'},
    });

    expect(transfer.panes.single.sessionId, 4242);
    expect(transfer.panes.single.tabId, 'tab-1');
    expect(transfer.toJson()['panes'], [
      {
        'id': 'pane-1',
        'tabId': 'tab-1',
        'sessionId': 4242,
        'workingDirectory': '/tmp/session',
      },
    ]);
    expect(
      WorkspaceTabTransfer.layoutFromJson(transfer.layout),
      const PaneLayoutLeaf('pane-1'),
    );
  });

  test(
    'missing session IDs remain explicit and cannot be mistaken for cwd moves',
    () {
      final transfer = WorkspaceTabTransfer.fromJson({
        'id': 'group-1',
        'focusedPaneId': 'pane-1',
        'panes': [
          {
            'id': 'pane-1',
            'tabId': 'tab-1',
            'workingDirectory': '/tmp/session',
          },
        ],
        'layout': {'type': 'leaf', 'paneId': 'pane-1'},
      });

      expect(transfer.panes.single.sessionId, isNull);
      expect(transfer.panes.single.workingDirectory, '/tmp/session');
    },
  );
}
