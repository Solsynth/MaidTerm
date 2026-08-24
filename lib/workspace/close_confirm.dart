import 'dart:async';

import 'package:flutter/material.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:easy_localization/easy_localization.dart';

import '../shell/local_shell_session.dart';

/// Asks the user before closing [sessions] that still run programs.
///
/// Returns true when every session is idle or the user confirmed the close,
/// false when any busy session exists and the user cancelled. The alert is
/// the island_ui_foundation attention modal.
Future<bool> confirmCloseSessions(
  List<LocalShellSession> sessions, {
  required String id,
}) async {
  final busy = sessions
      .where((session) => session.hasRunningPrograms)
      .toList();
  if (busy.isEmpty) return true;

  final confirmed = Completer<bool>();
  await showAttentionModal(
    id: id,
    builder: (context, dismiss) => _CloseRunningSessionsDialog(
      sessions: busy,
      onCancel: () {
        confirmed.complete(false);
        dismiss();
      },
      onClose: () {
        confirmed.complete(true);
        dismiss();
      },
    ),
  );
  // The modal can also be dismissed out-of-band (route removal); treat any
  // unconfirmed exit as a cancel.
  return confirmed.isCompleted ? await confirmed.future : false;
}

class _CloseRunningSessionsDialog extends StatelessWidget {
  const _CloseRunningSessionsDialog({
    required this.sessions,
    required this.onCancel,
    required this.onClose,
  });

  final List<LocalShellSession> sessions;
  final VoidCallback onCancel;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final names = <String>{
      for (final session in sessions) ...session.runningProgramNames,
    }.toList();
    final programText = names.isEmpty
        ? null
        : names.take(3).join(', ') + (names.length > 3 ? ', …' : '');
    final single = sessions.length == 1;

    final message = single
        ? programText == null
              ? 'closeConfirmSingle'.tr()
              : 'closeConfirmSingleWithProgram'.tr(
                    args: [programText],
                  )
        : 'closeConfirmMany'.tr(
                args: ['${sessions.length}'],
              );

    return AlertDialog(
      title: Text(single ? 'closeConfirmTitleSingle'.tr() : 'closeConfirmTitleMany'.tr()),
      content: Text(message),
      actions: [
        TextButton(onPressed: onCancel, child: Text('commonCancel'.tr())),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: scheme.error,
            foregroundColor: scheme.onError,
          ),
          onPressed: onClose,
          child: Text('commonClose'.tr()),
        ),
      ],
    );
  }
}
