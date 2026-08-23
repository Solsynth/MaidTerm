import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:maidterm/maidterm.dart' as maidterm;

import '../settings/settings_page.dart';
import '../settings/terminal_color_scheme.dart';
import '../settings/terminal_settings.dart';
import '../settings/background_image.dart';

import 'session_layout.dart';
import 'terminal_surface.dart';
import 'terminal_workspace.dart';

/// The main screen: one workspace-wide tab strip around resizable split panes.
class TerminalWorkspacePage extends ConsumerWidget {
  const TerminalWorkspacePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workspace = ref.watch(terminalWorkspaceProvider);
    if (workspace.tabs.isEmpty) {
      return _EmptyWorkspace();
    }
    final root = workspace.layout;
    if (root == null) return _EmptyWorkspace();

    final settings = ref.watch(terminalSettingsProvider).value;
    final tabBarPosition = settings?.tabBarPosition ?? TabBarPosition.top;
    final tabBar = _ResizableTabBar(
      position: tabBarPosition,
      initialWidth: settings?.tabBarWidth ?? _workspaceTabBarWidth,
      onWidthChanged: (width) {
        if (settings != null) {
          ref.read(terminalSettingsProvider.notifier).setTabBarWidth(width);
        }
      },
      builder: (width, height) => _WorkspaceTabBar(
        workspace: workspace,
        position: tabBarPosition,
        width: width,
        height: height,
      ),
    );
    final layout = Expanded(
      child: _WorkspaceGround(child: _LayoutNode(node: root)),
    );
    final vertical =
        tabBarPosition == TabBarPosition.left ||
        tabBarPosition == TabBarPosition.right;
    final tabBarFirst =
        tabBarPosition == TabBarPosition.top ||
        tabBarPosition == TabBarPosition.left;

    return vertical
        ? Row(children: tabBarFirst ? [tabBar, layout] : [layout, tabBar])
        : Column(children: tabBarFirst ? [tabBar, layout] : [layout, tabBar]);
  }
}

class _EmptyWorkspace extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _WorkspaceGround(
      child: Center(
        child: FilledButton.icon(
          onPressed: () =>
              ref.read(terminalWorkspaceProvider.notifier).openTerminal(),
          icon: const Icon(Symbols.add),
          label: const Text('New Terminal'),
        ),
      ),
    );
  }
}

/// The workspace ground: a `surfaceContainer` field (or the subdued
/// background image) that the floating pane lands sit on. Panes float above
/// it with a ring of ground visible around every edge.
class _WorkspaceGround extends ConsumerWidget {
  const _WorkspaceGround({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final backgroundImage = ref
        .watch(maidTermBackgroundImageProvider)
        .asData
        ?.value;
    final backgroundImageEnabled =
        ref.watch(maidTermBackgroundImageEnabledProvider).asData?.value ?? true;
    final hasBackgroundImage =
        backgroundImageEnabled && backgroundImage != null;
    return DecoratedBox(
      key: const ValueKey('workspace-ground'),
      decoration: BoxDecoration(
        color: hasBackgroundImage
            ? scheme.surfaceContainer.withValues(alpha: 0.64)
            : scheme.surfaceContainer,
      ),
      child: Padding(
        padding: const EdgeInsets.all(_workspaceGroundPadding),
        child: child,
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
          onRatioChanged: (value) => ref
              .read(terminalWorkspaceProvider.notifier)
              .setSplitRatio(id, value),
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
    final isHorizontal = widget.axis == SplitAxis.horizontal;

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxExtent = isHorizontal
            ? constraints.maxWidth
            : constraints.maxHeight;
        final available = maxExtent - _paneGap;
        final firstExtent = available * _ratio;
        final secondExtent = available - firstExtent;

        final children = <Widget>[
          SizedBox(
            width: isHorizontal ? firstExtent : null,
            height: isHorizontal ? null : firstExtent,
            child: widget.first,
          ),
          // The ground gap between floating lands.
          SizedBox(
            width: isHorizontal ? _paneGap : double.infinity,
            height: isHorizontal ? double.infinity : _paneGap,
          ),
          SizedBox(
            width: isHorizontal ? secondExtent : null,
            height: isHorizontal ? null : secondExtent,
            child: widget.second,
          ),
        ];
        final layout = isHorizontal
            ? Row(children: children)
            : Column(children: children);
        final resizeHandle = MouseRegion(
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
            child: const SizedBox.expand(),
          ),
        );

        return Stack(
          clipBehavior: Clip.none,
          children: [
            layout,
            Positioned(
              left: isHorizontal ? firstExtent + (_paneGap - 8) / 2 : 0,
              right: isHorizontal ? null : 0,
              top: isHorizontal ? 0 : firstExtent + (_paneGap - 8) / 2,
              bottom: isHorizontal ? 0 : null,
              width: isHorizontal ? 8 : null,
              height: isHorizontal ? null : 8,
              child: resizeHandle,
            ),
          ],
        );
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
    if (!workspace.panes.containsKey(paneId)) {
      return const SizedBox.shrink();
    }

    final focused = workspace.focusedPaneId == paneId;
    final selected = workspace.selectedTabInPane(paneId);
    final settings = ref.watch(terminalSettingsProvider).value;
    final brightness = Theme.of(context).brightness;
    final terminalScheme = settings == null
        ? TerminalColorSchemes.defaultScheme
        : brightness == Brightness.light
        ? settings.lightTheme
        : settings.darkTheme;
    final transparent = settings?.transparentBackground ?? false;
    final terminal = selected == null
        ? ColoredBox(
            key: const ValueKey('terminal-pane-backdrop'),
            color: transparent ? Colors.transparent : terminalScheme.background,
          )
        : Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                child: ColoredBox(
                  key: const ValueKey('terminal-pane-backdrop'),
                  color: transparent
                      ? Colors.transparent
                      : terminalScheme.background,
                ),
              ),
              Listener(
                onPointerDown: (_) {
                  ref
                      .read(terminalWorkspaceProvider.notifier)
                      .focusPane(paneId);
                  selected.session.controller.requestFocus();
                },
                child: TerminalSurface(
                  // Stable identity per pane: splitting or closing panes
                  // restructures the layout tree, which would otherwise
                  // destroy and recreate this terminal's element and tear
                  // down the session's focus binding (the cursor would stop
                  // tracking focus).
                  key: GlobalObjectKey(workspace.panes[paneId]!.viewKey),
                  tab: selected,
                  autofocus: focused,
                ),
              ),
            ],
          );

    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () =>
          ref.read(terminalWorkspaceProvider.notifier).focusPane(paneId),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(_paneRadius),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.10),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(_paneRadius),
          child: terminal,
        ),
      ),
    );
  }
}

const _workspaceTabBarHeight = 40.0;
const _workspaceTabBarWidth = 180.0;
const _compactTabBarWidth = 160.0;
const _minWorkspaceTabBarWidth = 48.0;
const _evenlySpacedActionWidth = 260.0;

/// The floating-land chrome: a ring of ground around the whole layout and
/// between split panes, plus the land rounding.
const _workspaceGroundPadding = 10.0;
const _paneGap = 10.0;
const _paneRadius = 14.0;
const _tabBarHandleWidth = 1.0;
const _tabEntryVerticalPadding = 2.0;
const _verticalTabStripTopMargin =
    _workspaceGroundPadding - _tabEntryVerticalPadding;

class _ResizableTabBar extends StatefulWidget {
  const _ResizableTabBar({
    required this.position,
    required this.initialWidth,
    required this.onWidthChanged,
    required this.builder,
  });

  final TabBarPosition position;
  final double initialWidth;
  final ValueChanged<double> onWidthChanged;
  final Widget Function(double? width, double height) builder;

  @override
  State<_ResizableTabBar> createState() => _ResizableTabBarState();
}

class _ResizableTabBarState extends State<_ResizableTabBar> {
  static const _minWidth = _minWorkspaceTabBarWidth;
  static const _maxWidth = 360.0;
  late double _width;
  var _dragging = false;
  var _animateCollapse = false;

  @override
  void initState() {
    super.initState();
    _width = _clampWidth(widget.initialWidth);
  }

  @override
  void didUpdateWidget(_ResizableTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_dragging && oldWidget.initialWidth != widget.initialWidth) {
      _width = _clampWidth(widget.initialWidth);
    }
  }

  bool get _vertical =>
      widget.position == TabBarPosition.left ||
      widget.position == TabBarPosition.right;

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    final delta = widget.position == TabBarPosition.left
        ? details.delta.dx
        : -details.delta.dx;
    final next = _clampWidth(_width + delta);
    final collapse =
        delta < 0 && next > _minWidth && next <= _compactTabBarWidth;
    setState(() {
      _dragging = true;
      _animateCollapse = collapse;
      _width = collapse ? _minWidth : next;
    });
  }

  void _onDragEnd() {
    if (!_dragging) return;
    setState(() {
      _dragging = false;
      _animateCollapse = false;
    });
    if (_vertical) widget.onWidthChanged(_width);
  }

  double _clampWidth(double width) =>
      width.clamp(_minWidth, _maxWidth).toDouble();

  @override
  Widget build(BuildContext context) {
    final tabBar = widget.builder(
      _vertical ? _width : null,
      _workspaceTabBarHeight,
    );
    if (!_vertical) return tabBar;

    // Invisible drag strip: the sidebar and workspace ground share the
    // `surfaceContainer` tone, so no divider line is needed between them.
    final handle = MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        key: const ValueKey('tab-bar-resize-handle'),
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: _onHorizontalDragUpdate,
        onHorizontalDragEnd: (_) => _onDragEnd(),
        onHorizontalDragCancel: _onDragEnd,
        child: const SizedBox(
          width: _tabBarHandleWidth,
          height: double.infinity,
        ),
      ),
    );
    final sidebar = AnimatedContainer(
      duration: _animateCollapse
          ? const Duration(milliseconds: 180)
          : Duration.zero,
      curve: Curves.easeOutCubic,
      width: _width,
      child: tabBar,
    );
    // The drag strip overlays the sidebar's edge instead of reserving a
    // layout column, so no background shows through between the sidebar and
    // the workspace ground (they share the `surfaceContainer` tone).
    return Stack(
      children: [
        sidebar,
        Positioned(
          top: 0,
          bottom: 0,
          width: _tabBarHandleWidth,
          left: widget.position == TabBarPosition.right ? 0 : null,
          right: widget.position == TabBarPosition.left ? 0 : null,
          child: handle,
        ),
      ],
    );
  }
}

class _WorkspaceTabBar extends ConsumerWidget {
  const _WorkspaceTabBar({
    required this.workspace,
    required this.position,
    required this.height,
    this.width,
  });

  final TerminalWorkspaceState workspace;
  final TabBarPosition position;
  final double height;
  final double? width;

  bool get _vertical =>
      position == TabBarPosition.left || position == TabBarPosition.right;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(
      builder: (context, constraints) => _buildTabBar(
        context,
        ref,
        _vertical && (width ?? _workspaceTabBarWidth) <= _compactTabBarWidth,
      ),
    );
  }

  Widget _buildTabBar(BuildContext context, WidgetRef ref, bool compact) {
    final scheme = Theme.of(context).colorScheme;
    final backgroundImage = ref
        .watch(maidTermBackgroundImageProvider)
        .asData
        ?.value;
    final backgroundImageEnabled =
        ref.watch(maidTermBackgroundImageEnabledProvider).asData?.value ?? true;
    final hasBackgroundImage =
        backgroundImageEnabled && backgroundImage != null;
    final notifier = ref.read(terminalWorkspaceProvider.notifier);

    void reorderTab(String tabId, {int? toIndex}) {
      notifier.reorderTab(tabId, toIndex ?? workspace.tabs.length);
    }

    Widget actionButton({
      required String tooltip,
      required Widget icon,
      required VoidCallback onPressed,
    }) {
      const controlSize = _workspaceTabBarHeight;
      return IconButton(
        tooltip: tooltip,
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: BoxConstraints(
          minWidth: controlSize,
          minHeight: controlSize,
        ),
        onPressed: onPressed,
        icon: icon,
      );
    }

    final focusedPaneId = workspace.focusedPaneId;
    final evenlySpaced =
        _vertical &&
        !compact &&
        (width ?? _workspaceTabBarWidth) >= _evenlySpacedActionWidth;
    final actions = <Widget>[
      if (!compact)
        actionButton(
          tooltip: 'Split right',
          icon: const Icon(Symbols.vertical_split, size: 20),
          onPressed: () {
            if (focusedPaneId != null) {
              notifier.split(SplitAxis.horizontal);
            }
          },
        ),
      if (!compact)
        actionButton(
          tooltip: 'Split below',
          icon: const Icon(Symbols.horizontal_split, size: 20),
          onPressed: () {
            if (focusedPaneId != null) {
              notifier.split(SplitAxis.vertical);
            }
          },
        ),
      actionButton(
        tooltip: 'New tab',
        icon: const Icon(Symbols.add, size: 20),
        onPressed: notifier.openTerminal,
      ),

      if (!compact && workspace.hasSplits)
        actionButton(
          tooltip: 'Close pane',
          icon: const Icon(Symbols.close, size: 18),
          onPressed: () {
            if (focusedPaneId != null) {
              notifier.closePane(focusedPaneId);
            }
          },
        ),
      if (evenlySpaced) const Spacer(),
      if (!compact)
        actionButton(
          tooltip: 'Settings (Cmd+,)',
          icon: const Icon(Symbols.settings, size: 18),
          onPressed: () => Navigator.of(
            context,
          ).push(MaterialPageRoute<void>(builder: (_) => const SettingsPage())),
        ),
      const SizedBox(width: 4),
    ];
    final tabStrip = Expanded(
      child: DragTarget<_TabDragData>(
        onWillAcceptWithDetails: (details) => details.data.tabId.isNotEmpty,
        onAcceptWithDetails: (details) => reorderTab(details.data.tabId),
        builder: (context, candidate, rejected) {
          final hovering = candidate.isNotEmpty;
          return DecoratedBox(
            decoration: BoxDecoration(
              color: hovering ? scheme.primary.withValues(alpha: 0.08) : null,
            ),
            child: ListView.builder(
              scrollDirection: _vertical ? Axis.vertical : Axis.horizontal,
              padding: EdgeInsets.only(
                top: _vertical ? _verticalTabStripTopMargin : 0,
              ),
              itemCount: workspace.tabs.length + 1,
              itemBuilder: (context, index) {
                if (index == workspace.tabs.length) {
                  return _TabDropTail(
                    vertical: _vertical,
                    height: height,
                    hovering: hovering,
                    onAccept: (data) =>
                        reorderTab(data.tabId, toIndex: workspace.tabs.length),
                  );
                }
                final tab = workspace.tabs[index];
                final tabEntry = _WorkspaceTabEntry(
                  tab: tab,
                  selected: tab.id == workspace.selectedTab?.id,
                  position: position,
                  height: height,
                  compact: compact,
                  onSelectPane: (paneId) {
                    notifier.selectTab(tab.id);
                    notifier.focusPane(paneId);
                  },
                  onClosePane: (paneId) =>
                      notifier.closePaneInTab(tab.id, paneId),
                );
                return _DraggableWorkspaceTab(
                  key: ValueKey(tab.id),
                  tab: tab,
                  index: index,
                  position: position,
                  height: height,
                  child: tabEntry,
                  onAccept: (data, insertIndex) =>
                      reorderTab(data.tabId, toIndex: insertIndex),
                );
              },
            ),
          );
        },
      ),
    );
    final actionContent = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(mainAxisSize: MainAxisSize.min, children: actions),
    );
    final actionBar = SizedBox(
      height: height,
      child: evenlySpaced
          ? Row(mainAxisSize: MainAxisSize.max, children: actions)
          : _vertical && compact
          ? Center(child: actionContent)
          : actionContent,
    );
    final layout = Flex(
      direction: _vertical ? Axis.vertical : Axis.horizontal,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [tabStrip, actionBar],
    );

    return Material(
      key: const ValueKey('workspace-tab-bar'),
      color: hasBackgroundImage
          ? scheme.surfaceContainer.withValues(alpha: 0.64)
          : scheme.surfaceContainer,
      child: SizedBox(
        width: _vertical ? (width ?? _workspaceTabBarWidth) : null,
        height: _vertical ? null : height,
        child: layout,
      ),
    );
  }
}

class _TabDragData {
  const _TabDragData({required this.tabId});

  final String tabId;
}

class _WorkspaceTabEntry extends StatelessWidget {
  const _WorkspaceTabEntry({
    required this.tab,
    required this.selected,
    required this.position,
    required this.height,
    required this.compact,
    required this.onSelectPane,
    required this.onClosePane,
  });

  final TerminalWorkspaceTab tab;
  final bool selected;
  final TabBarPosition position;
  final double height;
  final bool compact;
  final ValueChanged<String> onSelectPane;
  final ValueChanged<String> onClosePane;
  @override
  Widget build(BuildContext context) {
    final vertical =
        position == TabBarPosition.left || position == TabBarPosition.right;
    final verticalPadding = vertical ? _tabEntryVerticalPadding : 4.0;
    final chipHeight = (height - (verticalPadding * 2))
        .clamp(1, height)
        .toDouble();
    final panes = tab.panes.values.toList();
    if (panes.length < 2) {
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: 4, vertical: verticalPadding),
        child: _PaneTabChip(
          key: ValueKey('pane-tab-${panes.first.tab.id}'),
          tab: panes.first.tab,
          selected: selected && panes.first.id == tab.focusedPaneId,
          position: position,
          height: chipHeight,
          compact: compact,
          onSelect: () => onSelectPane(panes.first.id),
          onClose: () => onClosePane(panes.first.id),
        ),
      );
    }
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 4, vertical: verticalPadding),
      child: _MergedPaneTabPill(
        panes: panes,
        selectedPaneId: selected ? tab.focusedPaneId : null,
        position: position,
        height: chipHeight,
        compact: compact,
        onSelectPane: onSelectPane,
        onClosePane: onClosePane,
      ),
    );
  }
}

class _MergedPaneTabPill extends StatelessWidget {
  const _MergedPaneTabPill({
    required this.panes,
    required this.selectedPaneId,
    required this.position,
    required this.height,
    required this.compact,
    required this.onSelectPane,
    required this.onClosePane,
  });

  final List<TerminalPane> panes;
  final String? selectedPaneId;
  final TabBarPosition position;
  final double height;
  final bool compact;
  final ValueChanged<String> onSelectPane;
  final ValueChanged<String> onClosePane;

  bool get _vertical =>
      position == TabBarPosition.left || position == TabBarPosition.right;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pillRadius = BorderRadius.circular(12);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: selectedPaneId != null
            ? scheme.surfaceContainerHighest
            : scheme.surfaceContainerHigh.withValues(alpha: 0.72),
        borderRadius: pillRadius,
      ),
      child: ClipRRect(
        borderRadius: pillRadius,
        child: Flex(
          direction: _vertical ? Axis.vertical : Axis.horizontal,
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < panes.length; i++)
              _PaneTabSegment(
                key: ValueKey('pane-tab-${panes[i].tab.id}'),
                tab: panes[i].tab,
                selected: panes[i].id == selectedPaneId,
                vertical: _vertical,
                height: height,
                compact: compact,
                onSelect: () => onSelectPane(panes[i].id),
                onClose: () => onClosePane(panes[i].id),
              ),
          ],
        ),
      ),
    );
  }
}

class _DraggableWorkspaceTab extends StatelessWidget {
  const _DraggableWorkspaceTab({
    super.key,
    required this.tab,
    required this.index,
    required this.position,
    required this.height,
    required this.child,
    required this.onAccept,
  });

  final TerminalWorkspaceTab tab;
  final int index;
  final TabBarPosition position;
  final double height;
  final Widget child;
  final void Function(_TabDragData data, int insertIndex) onAccept;

  bool get _vertical =>
      position == TabBarPosition.left || position == TabBarPosition.right;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final groupHeight = _vertical ? height * tab.panes.length : height;
    final dragData = _TabDragData(tabId: tab.id);
    final feedback = Material(
      elevation: 4,
      color: scheme.surfaceContainerHighest,
      child: SizedBox(
        width: _vertical ? _workspaceTabBarWidth : null,
        height: height,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(
            tab.title,
            style: Theme.of(context).textTheme.labelMedium,
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
            childWhenDragging: Opacity(opacity: 0.35, child: child),
            child: child,
          )
        : Draggable<_TabDragData>(
            data: dragData,
            dragAnchorStrategy: pointerDragAnchorStrategy,
            feedback: feedback,
            childWhenDragging: Opacity(opacity: 0.35, child: child),
            child: child,
          );

    return DragTarget<_TabDragData>(
      onWillAcceptWithDetails: (details) => details.data.tabId != tab.id,
      onAcceptWithDetails: (details) => onAccept(details.data, index),
      builder: (context, candidate, rejected) {
        final showInsert = candidate.isNotEmpty;
        return SizedBox(
          width: _vertical ? double.infinity : null,
          height: groupHeight + (showInsert && _vertical ? 2 : 0),
          child: Flex(
            direction: _vertical ? Axis.vertical : Axis.horizontal,
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (showInsert)
                SizedBox(
                  width: _vertical ? double.infinity : 2,
                  height: _vertical ? 2 : null,
                  child: Container(
                    margin: _vertical
                        ? const EdgeInsets.symmetric(horizontal: 8)
                        : const EdgeInsets.symmetric(vertical: 8),
                    color: scheme.primary,
                  ),
                ),
              draggable,
            ],
          ),
        );
      },
    );
  }
}

/// Shared content row for a pane tab: status icon, title, close button.
class _PaneTabContent extends StatelessWidget {
  const _PaneTabContent({
    required this.tab,
    required this.selected,
    required this.vertical,
    required this.height,
    required this.compact,
    required this.onClose,
  });

  final TerminalTab tab;
  final bool selected;
  final bool vertical;
  final double height;
  final bool compact;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final controlSize = height.clamp(0, _workspaceTabBarHeight).toDouble();
    return Align(
      alignment: compact ? Alignment.center : Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: compact ? 0 : 16),
        child: Row(
          mainAxisSize: compact
              ? MainAxisSize.min
              : vertical
              ? MainAxisSize.max
              : MainAxisSize.min,
          children: [
            ValueListenableBuilder<maidterm.TerminalProgress?>(
              valueListenable: tab.session.progress,
              builder: (context, progress, _) {
                final color = switch (progress?.state) {
                  .error => scheme.error,
                  .paused => scheme.tertiary,
                  _ => selected ? scheme.primary : scheme.onSurface,
                };
                if (progress == null ||
                    progress.state == .remove ||
                    progress.state == .paused) {
                  return Icon(
                    progress?.state == .paused
                        ? Symbols.pause_circle
                        : Symbols.terminal,
                    size: 16,
                    color: color,
                  );
                }
                return SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    value: progress.value == null
                        ? null
                        : progress.value! / 100,
                    color: color,
                  ),
                );
              },
            ),
            if (!compact) ...[
              const SizedBox(width: 6),
              Flexible(
                fit: vertical ? FlexFit.tight : FlexFit.loose,
                child: Text(
                  tab.title,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium
                      ?.copyWith(color: selected ? scheme.primary : null),
                ),
              ),
            ],
            if (!compact) ...[
              const SizedBox(width: 2),
              IconButton(
                tooltip: 'Close tab',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: BoxConstraints(
                  minWidth: controlSize,
                  minHeight: controlSize,
                ),
                onPressed: onClose,
                icon: const Icon(Symbols.close, size: 16),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A standalone rounded tab pill (tabs without splits).
class _PaneTabChip extends StatelessWidget {
  const _PaneTabChip({
    super.key,
    required this.tab,
    required this.selected,
    required this.position,
    required this.height,
    required this.compact,
    required this.onSelect,
    required this.onClose,
  });

  final TerminalTab tab;
  final bool selected;
  final TabBarPosition position;
  final double height;
  final bool compact;
  final VoidCallback onSelect;
  final VoidCallback onClose;

  bool get _vertical =>
      position == TabBarPosition.left || position == TabBarPosition.right;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pillRadius = BorderRadius.circular(12);
    final chip = SizedBox(
      width: _vertical ? double.infinity : null,
      height: height,
      child: Listener(
        onPointerDown: (event) {
          if (event.buttons & kMiddleMouseButton != 0) {
            onClose();
          }
        },
        child: InkWell(
          borderRadius: pillRadius,
          onTap: onSelect,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: selected
                  ? scheme.surfaceContainerHighest
                  : scheme.surfaceContainerHigh.withValues(alpha: 0.72),
              borderRadius: pillRadius,
            ),
            child: _PaneTabContent(
              tab: tab,
              selected: selected,
              vertical: _vertical,
              height: height,
              compact: compact,
              onClose: onClose,
            ),
          ),
        ),
      ),
    );
    return compact ? Tooltip(message: tab.title, child: chip) : chip;
  }
}

/// A flat segment inside a merged split pill. No own border or corner
/// rounding; the selected segment is highlighted with a fill tint.
class _PaneTabSegment extends StatelessWidget {
  const _PaneTabSegment({
    super.key,
    required this.tab,
    required this.selected,
    required this.vertical,
    required this.height,
    required this.compact,
    required this.onSelect,
    required this.onClose,
  });

  final TerminalTab tab;
  final bool selected;
  final bool vertical;
  final double height;
  final bool compact;
  final VoidCallback onSelect;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final segment = SizedBox(
      width: vertical ? double.infinity : null,
      height: height,
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
              color: selected ? scheme.primary.withValues(alpha: 0.16) : null,
            ),
            child: _PaneTabContent(
              tab: tab,
              selected: selected,
              vertical: vertical,
              height: height,
              compact: compact,
              onClose: onClose,
            ),
          ),
        ),
      ),
    );
    return compact ? Tooltip(message: tab.title, child: segment) : segment;
  }
}

class _TabDropTail extends StatelessWidget {
  const _TabDropTail({
    required this.vertical,
    required this.height,
    required this.hovering,
    required this.onAccept,
  });

  final bool vertical;
  final double height;
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
          width: vertical ? double.infinity : 28,
          height: vertical ? 28 : height,
          child: active
              ? Align(
                  child: Container(
                    width: vertical ? 20 : 2,
                    height: vertical ? 2 : 20,
                    color: scheme.primary,
                  ),
                )
              : null,
        );
      },
    );
  }
}
