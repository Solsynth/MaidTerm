/// Axis of a terminal split. [horizontal] places panes left/right;
/// [vertical] places them top/bottom.
enum SplitAxis { horizontal, vertical }

/// Binary tree describing how terminal panes are arranged on screen.
///
/// Leaves reference pane ids. The workspace owns one shared tab strip for all
/// panes.
sealed class PaneLayout {
  const PaneLayout();

  /// Pane ids currently present in this subtree.
  Iterable<String> get paneIds;

  bool containsPane(String paneId) => paneIds.contains(paneId);

  /// Whether this tree has more than one pane.
  bool get isSplit;
}

/// Single pane region.
class PaneLayoutLeaf extends PaneLayout {
  const PaneLayoutLeaf(this.paneId);

  final String paneId;

  @override
  Iterable<String> get paneIds sync* {
    yield paneId;
  }

  @override
  bool get isSplit => false;

  @override
  bool operator ==(Object other) =>
      other is PaneLayoutLeaf && other.paneId == paneId;

  @override
  int get hashCode => paneId.hashCode;
}

/// Two child layouts separated along [axis], with [ratio] of space for
/// [first].
class PaneLayoutSplit extends PaneLayout {
  const PaneLayoutSplit({
    required this.id,
    required this.axis,
    required this.first,
    required this.second,
    this.ratio = 0.5,
  });

  final String id;
  final SplitAxis axis;
  final PaneLayout first;
  final PaneLayout second;

  /// Fraction of the cross-axis space allocated to [first] (0–1).
  final double ratio;

  @override
  Iterable<String> get paneIds sync* {
    yield* first.paneIds;
    yield* second.paneIds;
  }

  @override
  bool get isSplit => true;

  PaneLayoutSplit copyWith({
    SplitAxis? axis,
    PaneLayout? first,
    PaneLayout? second,
    double? ratio,
  }) => PaneLayoutSplit(
    id: id,
    axis: axis ?? this.axis,
    first: first ?? this.first,
    second: second ?? this.second,
    ratio: ratio ?? this.ratio,
  );

  @override
  bool operator ==(Object other) =>
      other is PaneLayoutSplit &&
      other.id == id &&
      other.axis == axis &&
      other.first == first &&
      other.second == second &&
      other.ratio == ratio;

  @override
  int get hashCode => Object.hash(id, axis, first, second, ratio);
}

/// Clamps a split ratio so neither pane collapses.
double clampSplitRatio(double ratio, {double min = 0.15, double max = 0.85}) {
  if (ratio < min) return min;
  if (ratio > max) return max;
  return ratio;
}

/// Replaces the leaf for [focusedPaneId] with a split of that leaf and a new
/// leaf for [newPaneId]. Returns the unchanged tree if the focused leaf is
/// not found.
PaneLayout splitPane({
  required PaneLayout layout,
  required String focusedPaneId,
  required String newPaneId,
  required SplitAxis axis,
  required String splitId,
  double ratio = 0.5,
}) {
  switch (layout) {
    case PaneLayoutLeaf(paneId: final leafId):
      if (leafId != focusedPaneId) return layout;
      return PaneLayoutSplit(
        id: splitId,
        axis: axis,
        first: PaneLayoutLeaf(leafId),
        second: PaneLayoutLeaf(newPaneId),
        ratio: clampSplitRatio(ratio),
      );
    case PaneLayoutSplit(
      id: final splitNodeId,
      axis: final splitAxis,
      first: final first,
      second: final second,
      ratio: final splitRatio,
    ):
      return PaneLayoutSplit(
        id: splitNodeId,
        axis: splitAxis,
        first: splitPane(
          layout: first,
          focusedPaneId: focusedPaneId,
          newPaneId: newPaneId,
          axis: axis,
          splitId: splitId,
          ratio: ratio,
        ),
        second: splitPane(
          layout: second,
          focusedPaneId: focusedPaneId,
          newPaneId: newPaneId,
          axis: axis,
          splitId: splitId,
          ratio: ratio,
        ),
        ratio: splitRatio,
      );
  }
}

/// Sets the ratio on the split node with [splitId].
PaneLayout applySplitRatio(
  PaneLayout layout,
  String splitId,
  double ratio,
) {
  final clamped = clampSplitRatio(ratio);
  switch (layout) {
    case PaneLayoutLeaf():
      return layout;
    case PaneLayoutSplit(
      id: final id,
      axis: final axis,
      first: final first,
      second: final second,
      ratio: final currentRatio,
    ):
      if (id == splitId) {
        return PaneLayoutSplit(
          id: id,
          axis: axis,
          first: first,
          second: second,
          ratio: clamped,
        );
      }
      return PaneLayoutSplit(
        id: id,
        axis: axis,
        first: applySplitRatio(first, splitId, clamped),
        second: applySplitRatio(second, splitId, clamped),
        ratio: currentRatio,
      );
  }
}

/// Removes [paneId] from the tree, collapsing splits that lose a child.
/// Returns null when the tree becomes empty.
PaneLayout? removePaneFromLayout(PaneLayout layout, String paneId) {
  switch (layout) {
    case PaneLayoutLeaf(paneId: final leafId):
      return leafId == paneId ? null : layout;
    case PaneLayoutSplit(:final id, :final axis, :final first, :final second, :final ratio):
      final newFirst = removePaneFromLayout(first, paneId);
      final newSecond = removePaneFromLayout(second, paneId);
      if (newFirst == null) return newSecond;
      if (newSecond == null) return newFirst;
      return PaneLayoutSplit(
        id: id,
        axis: axis,
        first: newFirst,
        second: newSecond,
        ratio: ratio,
      );
  }
}

/// Preferred pane id to focus after [removedPaneId] is closed.
String? fallbackPaneAfterRemove(PaneLayout? before, String removedPaneId) {
  if (before == null) return null;
  final ids = before.paneIds.where((id) => id != removedPaneId).toList();
  return ids.isEmpty ? null : ids.last;
}
