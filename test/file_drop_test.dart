import 'dart:convert';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:maidterm/maidterm.dart' as maidterm;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:maidterm_app/shell/drop_paths.dart';
import 'package:maidterm_app/shell/local_shell_session.dart';
import 'package:maidterm_app/workspace/terminal_workspace.dart';
import 'package:maidterm_app/workspace/terminal_workspace_page.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    EasyLocalization.logger.enableBuildModes = [];
  });

  /// ProviderScope with sessions that never spawn a pty (plugin frameworks
  /// are not linked under `flutter test`).
  Widget buildWorkspace() {
    return EasyLocalization(
      supportedLocales: const [Locale('en', 'US')],
      path: 'assets/translations',
      fallbackLocale: const Locale('en', 'US'),
      useFallbackTranslations: true,
      child: ProviderScope(
        overrides: [
          localShellSessionFactoryProvider.overrideWithValue(
            ({String? workingDirectory}) => LocalShellSession(
              workingDirectory: workingDirectory,
              autoStart: false,
            ),
          ),
        ],
        child: const MaterialApp(home: TerminalWorkspacePage()),
      ),
    );
  }

  group('escapeDropPath', () {
    test('leaves safe absolute paths bare', () {
      expect(
        escapeDropPath('/Users/me/project/src/main.dart'),
        '/Users/me/project/src/main.dart',
      );
    });

    test('single-quotes paths containing spaces', () {
      expect(
        escapeDropPath('/Users/me/My Documents/file.txt'),
        "'/Users/me/My Documents/file.txt'",
      );
    });

    test('escapes embedded single quotes', () {
      expect(
        escapeDropPath("/Users/me/it's/a.txt"),
        r"'/Users/me/it'\''s/a.txt'",
      );
    });

    test('quotes shell metacharacters', () {
      expect(
        escapeDropPath(r'/tmp/$(rm -rf ~)/*'),
        r"'/tmp/$(rm -rf ~)/*'",
      );
    });

    test('empty path stays empty', () {
      expect(escapeDropPath(''), '');
    });
  });

  group('formatDroppedPaths', () {
    test('joins paths with a space and appends a trailing space', () {
      expect(
        formatDroppedPaths(['/a/b', '/c d']),
        r"/a/b '/c d' ",
      );
    });

    test('drops empty paths', () {
      expect(formatDroppedPaths(['', '/a']), '/a ');
    });

    test('no paths yields empty string', () {
      expect(formatDroppedPaths([]), '');
      expect(formatDroppedPaths(['']), '');
    });
  });

  testWidgets('OS file drop inserts shell-escaped paths into the terminal', (
    tester,
  ) async {
    await tester.pumpWidget(buildWorkspace());
    await tester.pumpAndSettle();

    final page = find.byType(TerminalWorkspacePage);
    final container = ProviderScope.containerOf(tester.element(page));
    final session = container
        .read(terminalWorkspaceProvider)
        .selectedTab!
        .session;
    final emitted = <int>[];
    session.controller.onOutput = emitted.addAll;

    final dropTarget = tester.widget<DropTarget>(find.byType(DropTarget));
    dropTarget.onDragDone!(
      DropDoneDetails(
        files: [
          DropItemFile('/Users/me/My Documents/a.txt'),
          DropItemFile('/tmp/plain.txt'),
        ],
        localPosition: Offset.zero,
        globalPosition: Offset.zero,
      ),
    );

    expect(
      utf8.decode(emitted),
      "'/Users/me/My Documents/a.txt' /tmp/plain.txt ",
    );
  });

  testWidgets('empty drop inserts nothing', (tester) async {
    await tester.pumpWidget(buildWorkspace());
    await tester.pumpAndSettle();

    final page = find.byType(TerminalWorkspacePage);
    final container = ProviderScope.containerOf(tester.element(page));
    final session = container
        .read(terminalWorkspaceProvider)
        .selectedTab!
        .session;
    final emitted = <int>[];
    session.controller.onOutput = emitted.addAll;

    final dropTarget = tester.widget<DropTarget>(find.byType(DropTarget));
    dropTarget.onDragDone!(
      DropDoneDetails(
        files: const [],
        localPosition: Offset.zero,
        globalPosition: Offset.zero,
      ),
    );

    expect(emitted, isEmpty);
  });

  testWidgets('drag hover shows and hides the drop highlight', (
    tester,
  ) async {
    await tester.pumpWidget(buildWorkspace());
    await tester.pumpAndSettle();

    final dropTarget = tester.widget<DropTarget>(find.byType(DropTarget));
    final highlight = find.byKey(const ValueKey('file-drop-highlight'));
    expect(highlight, findsNothing);

    dropTarget.onDragEntered!(
      DropEventDetails(localPosition: Offset.zero, globalPosition: Offset.zero),
    );
    await tester.pump();
    expect(highlight, findsOneWidget);

    // The outline hugs the pane border: no padding inset, and the same
    // corner radius as the pane backdrop.
    final highlightContainer = tester.widget<Container>(highlight);
    expect(highlightContainer.margin, isNull);
    final decoration =
        highlightContainer.decoration! as BoxDecoration;
    expect(decoration.borderRadius, BorderRadius.circular(14));
    final highlightSize = tester.getSize(highlight);
    final terminalSize = tester.getSize(find.byType(maidterm.TerminalView));
    expect(highlightSize.width, terminalSize.width);
    expect(highlightSize.height, terminalSize.height);

    dropTarget.onDragExited!(
      DropEventDetails(localPosition: Offset.zero, globalPosition: Offset.zero),
    );
    await tester.pump();
    expect(highlight, findsNothing);

    dropTarget.onDragExited!(
      DropEventDetails(localPosition: Offset.zero, globalPosition: Offset.zero),
    );
    await tester.pump();
    expect(highlight, findsNothing);
  });
}
