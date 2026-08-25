import 'package:flutter/foundation.dart' show internal;
import 'package:maidterm/src/foundation/terminal_theme.dart'
    show HyperlinkStyle;
import 'package:maidterm/src/links/link_match.dart';
import 'package:maidterm/src/links/link_path_resolver.dart';
import 'package:maidterm/src/links/link_settings.dart';
import 'package:maidterm/src/links/terminal_logical_line.dart';
import 'package:maidterm/src/links/text_link_patterns.dart';

/// Detects built-in text links and user-defined regex links.
///
/// Built-in detection normalizes the matched text into URI or file data.
/// Custom detection preserves regex capture groups in the link data.
@internal
final class TextLinkDetector {
  /// Returns built-in URL, URI, and file path matches.
  ///
  /// The detector scans logical-line text with [TextLinkPatterns.link], trims
  /// prose punctuation, then normalizes the match into URI or file data.
  Iterable<LinkMatch> builtInMatches(
    List<TerminalLogicalLine> lines, {
    required String? cwd,
    required bool includeFilePaths,
  }) sync* {
    for (final line in lines) {
      if (line.text.isEmpty ||
          line.text.length > TextLinkPatterns.maxLineLength) {
        continue;
      }
      var count = 0;
      for (final match in TextLinkPatterns.link.allMatches(line.text)) {
        if (count++ >= TextLinkPatterns.maxMatchesPerLine) break;
        final text = LinkPathResolver.trimTextLink(match.group(0)!);
        final uri = LinkPathResolver.parseTextUri(text);
        if (!includeFilePaths && uri == null) continue;
        final file = includeFilePaths
            ? LinkPathResolver.parseFile(text, cwd)
            : null;
        if (uri == null && file == null) continue;
        final start = match.start;
        final end = start + text.length;
        yield _matchFromOffsets(
          line,
          start,
          end,
          type: .text,
          priority: -1,
          sourceOrder: -1,
          uri: uri,
          file: file,
        );
      }
    }
  }

  /// Returns matches produced by one custom regex rule.
  ///
  /// The rule runs against each logical line. Non-empty matches become custom
  /// links with their regex capture groups.
  Iterable<LinkMatch> customMatches(
    List<TerminalLogicalLine> lines,
    LinkRule rule,
    int sourceOrder,
  ) sync* {
    for (final line in lines) {
      if (line.text.isEmpty ||
          line.text.length > TextLinkPatterns.maxLineLength) {
        continue;
      }

      var count = 0;
      for (final match in rule.pattern.allMatches(line.text)) {
        if (count++ >= TextLinkPatterns.maxMatchesPerLine) break;
        if (match.start == match.end) continue;
        yield _matchFromOffsets(
          line,
          match.start,
          match.end,
          type: .custom,
          id: rule.id,
          priority: rule.priority,
          sourceOrder: sourceOrder,
          captureGroups: [
            for (var i = 1; i <= match.groupCount; i++) match.group(i),
          ],
          hoverOnly: rule.highlightMode == .hover,
          idleStyle: rule.idleStyle,
          highlightedStyle: rule.highlightedStyle,
        );
      }
    }
  }

  LinkMatch _matchFromOffsets(
    TerminalLogicalLine line,
    int start,
    int end, {
    required LinkType type,
    required int priority,
    required int sourceOrder,
    String? id,
    Uri? uri,
    LinkedFile? file,
    List<String?> captureGroups = const [],
    bool hoverOnly = false,
    HyperlinkStyle? idleStyle,
    HyperlinkStyle? highlightedStyle,
  }) {
    final text = line.text.substring(start, end);
    return LinkMatch(
      priority: priority,
      sourceOrder: sourceOrder,
      hoverOnly: hoverOnly,
      idleStyle: idleStyle,
      highlightedStyle: highlightedStyle,
      link: ActivatedLink(
        type: type,
        id: id,
        text: text,
        uri: uri,
        file: file,
        range: line.rangeForOffsets(start, end),
        captureGroups: captureGroups,
      ),
    );
  }
}
