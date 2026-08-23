import 'package:flutter/foundation.dart' show immutable, internal, listEquals;
import 'package:libghostty/libghostty.dart' show Position;
import 'package:maidterm/src/foundation/cell_range.dart';
import 'package:maidterm/src/foundation/terminal_theme.dart'
    show HyperlinkStyle;
import 'package:maidterm/src/links/link_match.dart';

/// Link styling state for the visible viewport.
@internal
@immutable
final class LinkSnapshot {
  static const empty = LinkSnapshot([]);

  final List<LinkMatch> matches;
  final CellRange? highlighted;

  const LinkSnapshot(this.matches, {this.highlighted});

  factory LinkSnapshot.highlighted(CellRange range) {
    return LinkSnapshot(const [], highlighted: range);
  }

  @override
  int get hashCode => Object.hash(Object.hashAll(matches), highlighted);

  bool get isEmpty => matches.isEmpty && highlighted == null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LinkSnapshot &&
          listEquals(matches, other.matches) &&
          highlighted == other.highlighted;

  /// Whether [position] is in a link with idle styling.
  bool contains(Position position) {
    return matches.any((match) => match.visibleAt(position));
  }

  /// Whether [position] should use highlighted link styling.
  bool isHighlighted(Position position) {
    final range = highlighted;
    if (range == null) return false;
    if (!range.contains(position)) return false;
    if (matches.isEmpty) return true;
    return matches.any((match) => match.contains(position));
  }

  /// Rule-specific style for [position], or null to use the theme default.
  ///
  /// [highlighted] selects the highlighted (hover) style; otherwise the idle
  /// style is returned. Hover-only matches never report an idle style.
  HyperlinkStyle? styleAt(Position position, {required bool highlighted}) {
    for (final match in matches) {
      if (!match.contains(position)) continue;
      if (highlighted) {
        if (match.highlightedStyle != null) return match.highlightedStyle;
        continue;
      }
      if (match.hoverOnly) continue;
      if (match.idleStyle != null) return match.idleStyle;
    }
    return null;
  }

  /// Returns this snapshot with a different highlighted range.
  LinkSnapshot withHighlighted(CellRange? range) {
    if (highlighted == range) return this;
    if (matches.isEmpty && range == null) return empty;
    if (matches.isEmpty && range != null) return .highlighted(range);

    return LinkSnapshot(matches, highlighted: range);
  }
}
