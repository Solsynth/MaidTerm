import 'dart:typed_data';

import 'package:flutter/material.dart' show Color;
import 'package:libghostty/libghostty.dart' show Position;
import 'package:maidterm/src/foundation/cell_range.dart';
import 'package:maidterm/src/foundation/terminal_config.dart';
import 'package:maidterm/src/foundation/terminal_theme.dart'
    show HyperlinkStyle;
import 'package:maidterm/src/links/link_match.dart';
import 'package:maidterm/src/links/link_resolver.dart';
import 'package:maidterm/src/links/link_path_resolver.dart';
import 'package:maidterm/src/links/link_settings.dart';
import 'package:maidterm/src/links/link_snapshot.dart';
import 'package:maidterm/src/widgets/terminal_controller_impl.dart';
import 'package:test/test.dart';

void main() {
  group('LinkRule per-rule styling', () {
    test('styleAt returns the rule idle and highlighted styles', () {
      final rule = LinkRule.regex(
        id: 'todo',
        pattern: RegExp(r'TODO\w+'),
        idleStyle: const HyperlinkStyle(underline: .single),
        highlightedStyle: const HyperlinkStyle(
          underline: .double,
          outlineColor: Color(0xFFFF0000),
        ),
      );
      final snapshot = LinkSnapshot([
        LinkMatch(
          link: ActivatedLink(
            type: .custom,
            id: rule.id,
            text: 'TODOfix',
            range: CellRange(
              start: const Position(row: 0, col: 0),
              end: const Position(row: 0, col: 6),
            ),
          ),
          priority: 1,
          hoverOnly: false,
          sourceOrder: 0,
          idleStyle: rule.idleStyle,
          highlightedStyle: rule.highlightedStyle,
        ),
      ]);

      final at = const Position(row: 0, col: 3);
      expect(
        snapshot.styleAt(at, highlighted: false),
        rule.idleStyle,
      );
      expect(
        snapshot.styleAt(at, highlighted: true),
        rule.highlightedStyle,
      );
      // Theme default is used when the position is outside the link.
      expect(
        snapshot.styleAt(const Position(row: 1, col: 0), highlighted: false),
        isNull,
      );
    });

    test('hover-only rules never report an idle style', () {
      final snapshot = LinkSnapshot([
        LinkMatch(
          link: ActivatedLink(
            type: .custom,
            id: 'hover',
            text: 'HOVER',
            range: CellRange(
              start: const Position(row: 0, col: 0),
              end: const Position(row: 0, col: 4),
            ),
          ),
          priority: 1,
          hoverOnly: true,
          sourceOrder: 0,
          idleStyle: const HyperlinkStyle(underline: .single),
          highlightedStyle: const HyperlinkStyle(outlineColor: Color(0xFF00FF00)),
        ),
      ]);

      const at = Position(row: 0, col: 2);
      expect(snapshot.styleAt(at, highlighted: false), isNull);
      expect(
        snapshot.styleAt(at, highlighted: true),
        const HyperlinkStyle(outlineColor: Color(0xFF00FF00)),
      );
      expect(snapshot.contains(at), isFalse);
      // Hover state is tracked separately; a plain snapshot carries no
      // highlighted range, so isHighlighted stays false outside hover.
      expect(snapshot.isHighlighted(at), isFalse);
    });

    test('isHighlighted with no matches falls back to range containment', () {
      final snapshot = LinkSnapshot.highlighted(
        CellRange(
          start: const Position(row: 0, col: 1),
          end: const Position(row: 0, col: 3),
        ),
      );
      expect(
        snapshot.isHighlighted(const Position(row: 0, col: 2)),
        isTrue,
      );
      expect(
        snapshot.isHighlighted(const Position(row: 0, col: 4)),
        isFalse,
      );
    });
  });

  group('LinkSettings activation routing', () {
    test('rule onActivate overrides the global callback for its links', () {
      ActivatedLink? ruleFired;
      ActivatedLink? globalFired;
      final rule = LinkRule.regex(
        id: 'issue',
        pattern: RegExp(r'#\d+'),
        onActivate: (link) => ruleFired = link,
      );
      final settings = LinkSettings(
        rules: [rule],
        onActivate: (link) => globalFired = link,
      );

      final ruleLink = ActivatedLink(
        type: .custom,
        id: 'issue',
        text: '#42',
        range: CellRange(
          start: const Position(row: 0, col: 0),
          end: const Position(row: 0, col: 2),
        ),
      );
      settings.activationFor(ruleLink)?.call(ruleLink);
      expect(ruleFired, same(ruleLink));
      expect(globalFired, isNull);

      final textLink = ActivatedLink(
        type: .text,
        text: 'https://example.com',
        range: CellRange(
          start: const Position(row: 0, col: 0),
          end: const Position(row: 0, col: 18),
        ),
      );
      settings.activationFor(textLink)?.call(textLink);
      expect(globalFired, same(textLink));
    });

    test('hasActivation is true when only a rule carries a callback', () {
      expect(const LinkSettings().hasActivation, isFalse);
      expect(
        LinkSettings(
          rules: [
            LinkRule.regex(
              id: 'r',
              pattern: RegExp('x'),
              onActivate: (_) {},
            ),
          ],
        ).hasActivation,
        isTrue,
      );
    });
  });

  group('LinkResolver with live terminal', () {
    TerminalControllerImpl controller() {
      final c = TerminalControllerImpl(
        config: const TerminalConfig(cols: 120, rows: 40),
      );
      addTearDown(c.dispose);
      return c;
    }

    test('detects URLs and file paths from visible text', () {
      final c = controller();
      c.terminal.write(
        Uint8List.fromList(
          'https://example.com/foo bar.txt lib/main.dart\n'.codeUnits,
        ),
      );

      final resolver = LinkResolver();
      final settings = const LinkSettings();
      final urlMatch = resolver.linkAt(
        c.terminal,
        const Position(row: 0, col: 0),
        settings,
        rows: 40,
        cols: 120,
        cwd: '/home/user',
      );
      expect(urlMatch, isNotNull);
      expect(urlMatch!.link.type, LinkType.text);
      expect(urlMatch.link.uri, Uri.parse('https://example.com/foo'));

      // 'lib/main.dart' starts at column 32 after 'https://example.com/foo '.
      final pathMatch = resolver.linkAt(
        c.terminal,
        const Position(row: 0, col: 32),
        settings,
        rows: 40,
        cols: 120,
        cwd: '/home/user',
      );
      expect(pathMatch, isNotNull);
      expect(pathMatch!.link.file, isNotNull);
      expect(pathMatch.link.file!.path, 'lib/main.dart');
      expect(pathMatch.link.file!.resolvedPath, '/home/user/lib/main.dart');
    });

    test('requires two path segments before highlighting a file path', () {
      final c = controller();
      c.terminal.write(
        Uint8List.fromList(
          'build output /tmp lib/main.dart report.txt\n/tmp/log.txt\n'
              .codeUnits,
        ),
      );

      final snapshot = LinkResolver().buildSnapshot(
        c.terminal,
        const LinkSettings(),
        rows: 40,
        cols: 120,
      );

      expect(snapshot.matches.map((match) => match.link.text), [
        'lib/main.dart',
        '/tmp/log.txt',
      ]);
      expect(LinkPathResolver.parseFile('/tmp', null), isNull);
      expect(LinkPathResolver.parseFile('/tmp/log.txt', null), isNotNull);
    });
    test('does not consume prose or highlight Go module versions', () {
      final c = controller();
      final text = [
        '/stargate/accounts/me to see',
        r'/Applications/Application\ Support/bin',
        'go install '
            'src.solsynth.dev/solsynth/distribution/cmd/express'
            '@593dfb7a41a9',
      ].join('\n');
      c.terminal.write(Uint8List.fromList('$text\n'.codeUnits));

      final snapshot = LinkResolver().buildSnapshot(
        c.terminal,
        const LinkSettings(),
        rows: 40,
        cols: 120,
      );

      expect(snapshot.matches.map((match) => match.link.text), [
        '/stargate/accounts/me',
        r'/Applications/Application\ Support/bin',
      ]);
      expect(
        LinkPathResolver.parseFile(
          r'/Applications/Application\ Support/bin',
          null,
        )!.resolvedPath,
        '/Applications/Application Support/bin',
      );
      expect(
        LinkPathResolver.parseFile(
          'src.solsynth.dev/solsynth/distribution/cmd/express'
          '@593dfb7a41a9',
          null,
        ),
        isNull,
      );
    });


    test('custom rules carry their styles into resolved matches', () {
      final c = controller();
      c.terminal.write(Uint8List.fromList('meet TODOfix now\n'.codeUnits));

      final rule = LinkRule.regex(
        id: 'todo',
        pattern: RegExp(r'TODO\w+'),
        highlightedStyle: const HyperlinkStyle(
          underline: .single,
          outlineColor: Color(0xFFFFA500),
        ),
      );
      final resolver = LinkResolver();
      final settings = LinkSettings(rules: [rule]);

      final snapshot = resolver.buildSnapshot(
        c.terminal,
        settings,
        rows: 40,
        cols: 120,
      );
      final match = snapshot.matches.single;
      expect(match.link.id, 'todo');
      expect(match.highlightedStyle, rule.highlightedStyle);
      expect(
        snapshot.styleAt(const Position(row: 0, col: 5), highlighted: true),
        rule.highlightedStyle,
      );
      // Hover-only rule: no idle styling.
      expect(
        snapshot.styleAt(const Position(row: 0, col: 5), highlighted: false),
        isNull,
      );
    });
  });
}
