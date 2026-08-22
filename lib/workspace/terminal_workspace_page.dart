import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../settings/settings_page.dart';
import 'session_layout.dart';
import 'terminal_surface.dart';
import 'terminal_workspace.dart';

/// The main screen: terminal tabs arranged in resizable split panes.
class TerminalWorkspacePage extends ConsumerWidget {
  const TerminalWorkspacePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tabs = ref.watch(terminalWorkspaceProvider);
    if (tabs.tabs.isEmpty) {
      return _EmptyWorkspace();
    }
    final root = tabs.layout;
    if (root == null) return _EmptyWorkspace();
    return _LayoutNode(node: root);
  }
}

class _EmptyWorkspace extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: FilledButton.icon(
        onPressed: () =>
            ref.read(terminalWorkspaceProvider.notifier).openTerminal(),
        icon: const Icon(Symbols.add),
        label: const Text('New Terminal'),
      ),
    );
  }
}

class _LayoutNode extends ConsumerWidget {
  const _LayoutNode({required this.node});

  final PaneLayout node;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    switch (node) {
      case PaneLayoutLeaf(:final paneId):
        return _TerminalPaneView(paneId: paneId);
      case PaneLayoutSplit(
        :final id,
        :final axis,
        :final first,
        :final second,
        :final ratio,
      ):
        return _ResizableSplit(
          axis: axis,
          ratio: ratio,
          onRatioChanged: (value) =>
              ref.read(terminalWorkspaceProvider.notifier).setSplitRatio(id, value),
          first: _LayoutNode(node: first),
          second: _LayoutNode(node: second),
        );
    }
  }
}

class _ResizableSplit extends StatefulWidget {
  const _ResizableSplit({
    required this.axis,
    required this.ratio,
    required this.onRatioChanged,
    required this.first,
    required this.second,
  });

  final SplitAxis axis;
  final double ratio;
  final ValueChanged<double> onRatioChanged;
  final Widget first;
  final Widget second;

  @override
  State<_ResizableSplit> createState() => _ResizableSplitState();
}

class _ResizableSplitState extends State<_ResizableSplit> {
  static const _dividerThickness = 4.0;
  double? _dragRatio;

  double get _ratio => _dragRatio ?? widget.ratio;

  void _onDragUpdate(DragUpdateDetails details, double maxExtent) {
    if (maxExtent <= 0) return;
    final delta = widget.axis == SplitAxis.horizontal
        ? details.delta.dx
        : details.delta.dy;
    final next = clampSplitRatio(_ratio + delta / maxExtent);
    setState(() => _dragRatio = next);
  }

  void _onDragEnd() {
    final ratio = _dragRatio;
    if (ratio != null) {
      widget.onRatioChanged(ratio);
    }
    setState(() => _dragRatio = null);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isHorizontal = widget.axis == SplitAxis.horizontal;

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxExtent = isHorizontal
            ? constraints.maxWidth
            : constraints.maxHeight;
        final available = maxExtent - _dividerThickness;
        final firstExtent = available * _ratio;
        final secondExtent = available - firstExtent;

        final children = <Widget>[
          SizedBox(
            width: isHorizontal ? firstExtent : null,
            height: isHorizontal ? null : firstExtent,
            child: widget.first,
          ),
          MouseRegion(
            cursor: isHorizontal
                ? SystemMouseCursors.resizeColumn
                : SystemMouseCursors.resizeRow,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragUpdate: isHorizontal
                  ? (d) => _onDragUpdate(d, available)
                  : null,
              onHorizontalDragEnd: isHorizontal ? (_) => _onDragEnd() : null,
              onVerticalDragUpdate: isHorizontal
                  ? null
                  : (d) => _onDragUpdate(d, available),
              onVerticalDragEnd: isHorizontal ? null : (_) => _onDragEnd(),
              child: ColoredBox(
                color: scheme.outlineVariant.withValues(alpha: 0.6),
                child: SizedBox(
                  width: isHorizontal ? _dividerThickness : double.infinity,
                  height: isHorizontal ? double.infinity : _dividerThickness,
                ),
              ),
            ),
          ),
          SizedBox(
            width: isHorizontal ? secondExtent : null,
            height: isHorizontal ? null : secondExtent,
            child: widget.second,
          ),
        ];

        return isHorizontal
            ? Row(children: children)
            : Column(children: children);
      },
    );
  }
}

class _TerminalPaneView extends ConsumerWidget {
  const _TerminalPaneView({required this.paneId});

  final String paneId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workspace = ref.watch(terminalWorkspaceProvider);
    final pane = workspace.panes[paneId];
    if (pane == null) return const SizedBox.shrink();

    final paneTabs = workspace.tabsInPane(paneId);
    final focused = workspace.focusedPaneId == paneId;
    final selected = workspace.selectedTabInPane(paneId);

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () =>
          ref.read(terminalWorkspaceProvider.notifier).focusPane(paneId),
      child: Column(
        children: [
          _PaneTabBar(
            paneId: paneId,
            paneTabs: paneTabs,
            selectedTabId: pane.selectedTabId,
            focused: focused,
            showClosePane: workspace.hasSplits,
          ),
          Expanded(
            child: selected == null
                ? const SizedBox.shrink()
                : TerminalSurface(tab: selected),
          ),
        ],
      ),
    );
  }
}

const _paneTabBarHeight = 40.0;

class _TabDragData {
  const _TabDragData({required this.tabId, required this.fromPaneId});

  final String tabId;
  final String fromPaneId;
}

/// Ported from MaidKit's sessions tab bar: focus-tinted surface, 2px primary
/// underline for the active tab, drag-to-reorder with an insert indicator,
/// middle-click to close, and compact pane actions on the right.
class _PaneTabBar extends ConsumerWidget {
  const _PaneTabBar({
    required this.paneId,
    required this.paneTabs,
    required this.selectedTabId,
    required this.focused,
    required this.showClosePane,
  });

  final String paneId;
  final List<TerminalTab> paneTabs;
  final String? selectedTabId;
  final bool focused;
  final bool showClosePane;

  void _acceptTab(WidgetRef ref, _TabDragData data, {int? toIndex}) {
    ref
        .read(terminalWorkspaceProvider.notifier)
        .moveTab(data.tabId, paneId, toIndex: toIndex);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: focused ? scheme.surfaceContainerHigh : scheme.surfaceContainerLow,
      child: SizedBox(
        height: _paneTabBarHeight,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: DragTarget<_TabDragData>(
                onWillAcceptWithDetails: (details) =>
                    details.data.tabId.isNotEmpty,
                onAcceptWithDetails: (details) =>
                    _acceptTab(ref, details.data),
                builder: (context, candidate, rejected) {
                  final hovering = candidate.isNotEmpty;
                  return DecoratedBox(
                    decoration: BoxDecoration(
                      color: hovering
                          ? scheme.primary.withValues(alpha: 0.08)
                          : null,
                    ),
                    child: paneTabs.isEmpty
                        ? Align(
                            alignment: Alignment.centerLeft,
                            child: Padding(
                              padding: const EdgeInsets.only(left: 12),
                              child: Text(
                                hovering ? 'Drop tab here' : 'New terminal',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelMedium
                                    ?.copyWith(color: scheme.onSurfaceVariant),
                              ),
                            ),
                          )
                        : ListView.builder(
                            scrollDirection: Axis.horizontal,
                            padding: EdgeInsets.zero,
                            // Trailing slot so tabs can be dropped after the
                            // last item.
                            itemCount: paneTabs.length + 1,
                            itemBuilder: (context, index) {
                              if (index == paneTabs.length) {
                                return _TabDropTail(
                                  hovering: hovering,
                                  onAccept: (data) =>
                                      _acceptTab(ref, data, toIndex: paneTabs.length),
                                );
                              }
                              final tab = paneTabs[index];
                              final selected = tab.id == selectedTabId;
                              return _DraggablePaneTab(
                                key: ValueKey(tab.id),
                                tab: tab,
                                paneId: paneId,
                                selected: selected,
                                index: index,
                                onSelect: () {
                                  ref
                                      .read(terminalWorkspaceProvider.notifier)
                                      .focusPane(paneId);
                                  ref
                                      .read(terminalWorkspaceProvider.notifier)
                                      .selectTab(tab.id, paneId: paneId);
                                },
                                onClose: () => ref
                                    .read(terminalWorkspaceProvider.notifier)
                                    .closeTab(tab.id),
                                onAccept: (data, insertIndex) =>
                                    _acceptTab(ref, data, toIndex: insertIndex),
                              );
                            },
                          ),
                  );
                },
              ),
            ),
            IconButton(
              tooltip: 'Split right',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(
                minWidth: _paneTabBarHeight,
                minHeight: _paneTabBarHeight,
              ),
              onPressed: () {
                ref.read(terminalWorkspaceProvider.notifier).focusPane(paneId);
                ref
                    .read(terminalWorkspaceProvider.notifier)
                    .split(SplitAxis.horizontal);
              },
              icon: const Icon(Symbols.vertical_split, size: 20),
            ),
            IconButton(
              tooltip: 'Split below',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(
                minWidth: _paneTabBarHeight,
                minHeight: _paneTabBarHeight,
              ),
              onPressed: () {
                ref.read(terminalWorkspaceProvider.notifier).focusPane(paneId);
                ref
                    .read(terminalWorkspaceProvider.notifier)
                    .split(SplitAxis.vertical);
              },
              icon: const Icon(Symbols.horizontal_split, size: 20),
            ),
            IconButton(
              tooltip: 'New tab',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(
                minWidth: _paneTabBarHeight,
                minHeight: _paneTabBarHeight,
              ),
              onPressed: () {
                ref.read(terminalWorkspaceProvider.notifier).focusPane(paneId);
                ref.read(terminalWorkspaceProvider.notifier).openTerminal();
              },
              icon: const Icon(Symbols.add, size: 20),
            ),
            if (showClosePane)
              IconButton(
                tooltip: 'Close pane',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: _paneTabBarHeight,
                  minHeight: _paneTabBarHeight,
                ),
                onPressed: () {
                  final pane = ref.read(terminalWorkspaceProvider).panes[paneId];
                  if (pane == null) return;
                  for (final tabId in pane.tabIds) {
                    ref.read(terminalWorkspaceProvider.notifier).closeTab(tabId);
                  }
                },
                icon: const Icon(Symbols.close, size: 18),
              ),
            IconButton(
              tooltip: 'Settings (Cmd+,)',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(
                minWidth: _paneTabBarHeight,
                minHeight: _paneTabBarHeight,
              ),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const SettingsPage(),
                ),
              ),
              icon: const Icon(Symbols.settings, size: 18),
            ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}

class _DraggablePaneTab extends StatelessWidget {
  const _DraggablePaneTab({
    super.key,
    required this.tab,
    required this.paneId,
    required this.selected,
    required this.index,
    required this.onSelect,
    required this.onClose,
    required this.onAccept,
  });

  final TerminalTab tab;
  final String paneId;
  final bool selected;
  final int index;
  final VoidCallback onSelect;
  final VoidCallback onClose;
  final void Function(_TabDragData data, int insertIndex) onAccept;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final chip = _PaneTabChip(
      tab: tab,
      selected: selected,
      onSelect: onSelect,
      onClose: onClose,
    );
    final dragData = _TabDragData(tabId: tab.id, fromPaneId: paneId);
    final feedback = Material(
      elevation: 4,
      color: scheme.surfaceContainerHighest,
      child: SizedBox(
        height: _paneTabBarHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Symbols.terminal, size: 16, color: scheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(
                tab.title,
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ],
          ),
        ),
      ),
    );
    final isMobile = switch (Theme.of(context).platform) {
      TargetPlatform.android || TargetPlatform.iOS => true,
      _ => false,
    };
    final draggable = isMobile
        ? LongPressDraggable<_TabDragData>(
            data: dragData,
            dragAnchorStrategy: pointerDragAnchorStrategy,
            feedback: feedback,
            childWhenDragging: Opacity(opacity: 0.35, child: chip),
            child: chip,
          )
        : Draggable<_TabDragData>(
            data: dragData,
            dragAnchorStrategy: pointerDragAnchorStrategy,
            feedback: feedback,
            childWhenDragging: Opacity(opacity: 0.35, child: chip),
            child: chip,
          );

    return DragTarget<_TabDragData>(
      onWillAcceptWithDetails: (details) => details.data.tabId != tab.id,
      onAcceptWithDetails: (details) {
        // Insert before this tab for stable reordering.
        onAccept(details.data, index);
      },
      builder: (context, candidate, rejected) {
        final showInsert = candidate.isNotEmpty;
        return SizedBox(
          height: _paneTabBarHeight,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (showInsert)
                Container(
                  width: 2,
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  color: scheme.primary,
                ),
              draggable,
            ],
          ),
        );
      },
    );
  }
}

class _PaneTabChip extends StatelessWidget {
  const _PaneTabChip({
    required this.tab,
    required this.selected,
    required this.onSelect,
    required this.onClose,
  });

  final TerminalTab tab;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: _paneTabBarHeight,
      child: Listener(
        onPointerDown: (event) {
          if (event.buttons & kMiddleMouseButton != 0) {
            onClose();
          }
        },
        child: InkWell(
          onTap: onSelect,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: selected ? scheme.primary : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Symbols.terminal,
                    size: 16,
                    color: selected ? scheme.primary : null,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    tab.title,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: selected ? scheme.primary : null,
                    ),
                  ),
                  const SizedBox(width: 2),
                  IconButton(
                    tooltip: 'Close tab',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 28,
                    ),
                    onPressed: onClose,
                    icon: const Icon(Symbols.close, size: 16),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TabDropTail extends StatelessWidget {
  const _TabDropTail({required this.hovering, required this.onAccept});

  final bool hovering;
  final void Function(_TabDragData data) onAccept;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DragTarget<_TabDragData>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (details) => onAccept(details.data),
      builder: (context, candidate, rejected) {
        final active = candidate.isNotEmpty || hovering;
        return SizedBox(
          width: 28,
          height: _paneTabBarHeight,
          child: active
              ? Align(
                  child: Container(width: 2, height: 20, color: scheme.primary),
                )
              : null,
        );
      },
    );
  }
}
