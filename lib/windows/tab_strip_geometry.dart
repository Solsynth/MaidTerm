import 'package:flutter/widgets.dart';
import 'package:nativeapi_flutter/nativeapi_flutter.dart' as na;

/// Screen-space geometry of one window's tab strip.
///
/// The strip widget registers its own render objects here, and the windows
/// controller reads them back while a drag is running: a native drag session
/// reports screen positions, so both hit testing and the reorder index have to
/// work in screen space too.
///
/// One registry lives on each [WorkspaceWindow], so the keys survive rebuilds
/// and tab reorders.
class TabStripRegistry {
  /// Key on the widget that spans the whole strip.
  final GlobalKey stripKey = GlobalKey(debugLabel: 'workspaceTabStrip');

  /// Axis the strip lays its tabs out along. The strip writes it on every
  /// build so the controller can map a cursor position to a strip slot without
  /// knowing how the user configured the tab bar.
  Axis axis = Axis.horizontal;

  final Map<String, GlobalKey> _tabKeys = <String, GlobalKey>{};

  /// Stable key for [tabId], so the chip of a live tab can be measured.
  GlobalKey keyFor(String tabId) => _tabKeys.putIfAbsent(
    tabId,
    () => GlobalKey(debugLabel: 'workspaceTab($tabId)'),
  );

  /// Forgets the keys of tabs that no longer live in this window.
  void retain(Iterable<String> liveTabIds) {
    if (_tabKeys.length <= liveTabIds.length) return;
    final live = liveTabIds.toSet();
    _tabKeys.removeWhere((tabId, _) => !live.contains(tabId));
  }

  /// Screen rect of the whole strip, or null while it is not laid out.
  Rect? stripRect(na.Window window) => _screenRect(window, stripKey);

  /// Screen rect of [tabId]'s chip, or null when it has no laid-out box.
  Rect? tabRect(na.Window window, String tabId) {
    final key = _tabKeys[tabId];
    return key == null ? null : _screenRect(window, key);
  }

  Rect? _screenRect(na.Window window, GlobalKey key) {
    final object = key.currentContext?.findRenderObject();
    if (object is! RenderBox || !object.hasSize) return null;
    return (window.contentBounds.toRect().topLeft +
            object.localToGlobal(Offset.zero)) &
        object.size;
  }
}

/// Index [draggedTabId] belongs at, given where [cursor] is: the number of
/// other tabs whose center lies before the cursor along [axis].
///
/// Tabs whose box is missing (a strip that has not laid out yet) are skipped
/// rather than guessed at.
int tabInsertionIndex({
  required Offset cursor,
  required Axis axis,
  required List<String> orderedTabIds,
  required String draggedTabId,
  required Rect? Function(String tabId) rectOf,
}) {
  var index = 0;
  for (final tabId in orderedTabIds) {
    if (tabId == draggedTabId) continue;
    final rect = rectOf(tabId);
    if (rect == null) continue;
    final crossed = axis == Axis.horizontal
        ? cursor.dx > rect.center.dx
        : cursor.dy > rect.center.dy;
    if (crossed) index++;
  }
  return index;
}
