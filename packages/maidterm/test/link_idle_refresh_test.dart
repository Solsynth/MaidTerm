import 'dart:typed_data';

import 'package:flutter/material.dart' show Color;
import 'package:flutter_test/flutter_test.dart';
import 'package:maidterm/maidterm.dart' as maidterm;
import 'package:maidterm/src/rendering/terminal_renderer.dart'
    show TerminalRenderBox, TerminalRenderer;
import 'package:maidterm/src/widgets/terminal_controller_impl.dart';

void main() {
  testWidgets('idle link snapshot refreshes after content change', (
    tester,
  ) async {
    final controller = TerminalControllerImpl(
      config: const maidterm.TerminalConfig(cols: 120, rows: 40),
    );
    addTearDown(controller.dispose);

    final rule = maidterm.LinkRule.regex(
      id: 'kw',
      pattern: RegExp('KEYWORD'),
      highlightMode: maidterm.LinkHighlightMode.always,
    );
    final settings = maidterm.LinkSettings(
      types: {maidterm.LinkType.custom},
      rules: [rule],
    );
    final theme = maidterm.TerminalTheme.dark().copyWith(
      hyperlink: const maidterm.HyperlinkTheme(
        idle: maidterm.HyperlinkStyle(
          underline: maidterm.UnderlineStyle.single,
          underlineColor: Color(0xFF80D8FF),
        ),
      ),
    );

    await tester.pumpWidget(
      maidterm.TerminalView(
        controller: controller,
        theme: theme,
        linkSettings: settings,
      ),
    );
    await tester.pump();

    TerminalRenderBox renderBox() => tester.renderObject<TerminalRenderBox>(
      find.byType(TerminalRenderer),
    );

    // Keyword on screen: idle snapshot carries the match. The rebuild is
    // deferred out of the terminal notification, so pump twice.
    controller.write(Uint8List.fromList('hello KEYWORD\n'.codeUnits));
    await tester.pump();
    await tester.pump();
    final before = renderBox().linkSnapshotForTest;
    expect(before.matches, hasLength(1));

    // Clear the screen (ED2) and move home: content changes, snapshot must
    // be rebuilt so the underline disappears.
    controller.write(Uint8List.fromList('\x1b[H\x1b[2J'.codeUnits));
    await tester.pump();
    await tester.pump();
    final after = renderBox().linkSnapshotForTest;
    expect(after.matches, isEmpty);

    // New keyword lands after clear: detected again.
    controller.write(Uint8List.fromList('KEYWORD again\n'.codeUnits));
    await tester.pump();
    await tester.pump();
    final rebuilt = renderBox().linkSnapshotForTest;
    expect(rebuilt.matches, hasLength(1));
  });
}
