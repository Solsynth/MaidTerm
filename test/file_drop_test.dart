import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maidterm/maidterm.dart' as maidterm;
import 'package:nativeapi_flutter/nativeapi_flutter.dart' as na;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:maidterm_app/shell/drop_paths.dart';

import 'support/window_harness.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    EasyLocalization.logger.enableBuildModes = [];
  });

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
      expect(escapeDropPath(r'/tmp/$(rm -rf ~)/*'), r"'/tmp/$(rm -rf ~)/*'");
    });

    test('empty path stays empty', () {
      expect(escapeDropPath(''), '');
    });
  });

  group('formatDroppedPaths', () {
    test('joins paths with a space and appends a trailing space', () {
      expect(formatDroppedPaths(['/a/b', '/c d']), r"/a/b '/c d' ");
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
    final host = await pumpWorkspaceWindow(tester);
    final session = host.focusedTerminal.session;
    final emitted = <int>[];
    session.controller.onOutput = emitted.addAll;

    final dropTarget = tester.widget<na.DropRegion>(find.byType(na.DropRegion));
    dropTarget.onDropped!(
      const na.DropRegionDropDetails(
        localPosition: Offset.zero,
        filePaths: ['/Users/me/My Documents/a.txt', '/tmp/plain.txt'],
        text: null,
      ),
    );

    expect(
      utf8.decode(emitted),
      "'/Users/me/My Documents/a.txt' /tmp/plain.txt ",
    );
  });

  testWidgets('OS file drop preserves bracketed paste for image-aware TUIs', (
    tester,
  ) async {
    final host = await pumpWorkspaceWindow(tester);
    final session = host.focusedTerminal.session;
    final emitted = <int>[];
    session.controller.onOutput = emitted.addAll;
    session.controller.write(utf8.encode('\x1b[?2004h'));

    final dropTarget = tester.widget<na.DropRegion>(find.byType(na.DropRegion));
    dropTarget.onDropped!(
      const na.DropRegionDropDetails(
        localPosition: Offset.zero,
        filePaths: ['/tmp/screenshot.png'],
        text: null,
      ),
    );

    expect(utf8.decode(emitted), '\x1b[200~/tmp/screenshot.png \x1b[201~');
  });

  testWidgets('empty drop inserts nothing', (tester) async {
    final host = await pumpWorkspaceWindow(tester);
    final session = host.focusedTerminal.session;
    final emitted = <int>[];
    session.controller.onOutput = emitted.addAll;

    final dropTarget = tester.widget<na.DropRegion>(find.byType(na.DropRegion));
    dropTarget.onDropped!(
      const na.DropRegionDropDetails(
        localPosition: Offset.zero,
        filePaths: [],
        text: null,
      ),
    );

    expect(emitted, isEmpty);
  });

  testWidgets('drag hover shows and hides the drop highlight', (tester) async {
    await pumpWorkspaceWindow(tester);

    final dropTarget = tester.widget<na.DropRegion>(find.byType(na.DropRegion));
    final highlight = find.byKey(const ValueKey('file-drop-highlight'));
    expect(highlight, findsNothing);

    dropTarget.onDragEntered!(Offset.zero);
    await tester.pump();
    expect(highlight, findsOneWidget);

    // The outline hugs the pane border: no padding inset, and the same
    // corner radius as the pane backdrop.
    final highlightContainer = tester.widget<Container>(highlight);
    expect(highlightContainer.margin, isNull);
    final decoration = highlightContainer.decoration! as BoxDecoration;
    expect(decoration.borderRadius, BorderRadius.circular(14));
    final highlightSize = tester.getSize(highlight);
    final terminalSize = tester.getSize(find.byType(maidterm.TerminalView));
    expect(highlightSize.width, terminalSize.width);
    expect(highlightSize.height, terminalSize.height);

    dropTarget.onDragExited!();
    await tester.pump();
    expect(highlight, findsNothing);

    dropTarget.onDragExited!();
    await tester.pump();
    expect(highlight, findsNothing);
  });
}
