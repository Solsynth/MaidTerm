import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:maidterm_app/app.dart';

import 'package:maidterm_app/workspace/terminal_workspace.dart';
import 'package:maidterm_app/shell/local_shell_session.dart';

void main() {
  testWidgets('command comma opens settings', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localShellSessionFactoryProvider.overrideWithValue(
            () => LocalShellSession(autoStart: false),
          ),
        ],
        child: const MaidTermApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.comma, character: ',');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.comma);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Settings'), findsOneWidget);
  });
}
