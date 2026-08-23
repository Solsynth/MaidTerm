import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:maidterm/maidterm.dart' as maidterm;

import '../settings/settings_page.dart';
import '../settings/terminal_color_scheme.dart';
import '../settings/terminal_settings.dart';
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
    final layout = Expanded(child: _LayoutNode(node: root));
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
  static const _dividerThickness = _tabBarBorderThickness;
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
          ColoredBox(
            color: scheme.outlineVariant.withValues(alpha: 0.6),
            child: SizedBox(
              width: isHorizontal ? _dividerThickness : double.infinity,
              height: isHorizontal ? double.infinity : _dividerThickness,
            ),
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
              left: isHorizontal ? firstExtent - 4 : 0,
              right: isHorizontal ? null : 0,
              top: isHorizontal ? 0 : firstExtent - 4,
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
        : ValueListenableBuilder<bool>(
            valueListenable: selected.session.isFullScreen,
            builder: (context, fullScreen, _) => Stack(
              alignment: Alignment.center,
              children: [
                Positioned.fill(
                  child: ColoredBox(
                    key: const ValueKey('terminal-pane-backdrop'),
                    color: fullScreen || !transparent
                        ? terminalScheme.background
                        : Colors.transparent,
                  ),
                ),
                Listener(
                  onPointerDown: (_) {
                    ref
                        .read(terminalWorkspaceProvider.notifier)
                        .focusPane(paneId);
                    selected.session.controller.requestFocus();
                  },
                  child: TerminalSurface(tab: selected, autofocus: focused),
                ),
              ],
            ),
          );

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () =>
          ref.read(terminalWorkspaceProvider.notifier).focusPane(paneId),
      child: terminal,
    );
  }
}

const _workspaceTabBarHeight = 40.0;
const _workspaceTabBarWidth = 180.0;
const _compactTabBarWidth = 160.0;
const _minWorkspaceTabBarWidth = 36.0;
const _evenlySpacedActionWidth = 260.0;
const _tabBarBorderThickness = 0.5;

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

    final scheme = Theme.of(context).colorScheme;
    final handle = MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        key: const ValueKey('tab-bar-resize-handle'),
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: _onHorizontalDragUpdate,
        onHorizontalDragEnd: (_) => _onDragEnd(),
        onHorizontalDragCancel: _onDragEnd,
        child: ColoredBox(
          color: scheme.outlineVariant.withValues(alpha: 0.42),
          child: const SizedBox(width: 2, height: double.infinity),
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
    return widget.position == TabBarPosition.left
        ? Row(children: [sidebar, handle])
        : Row(children: [handle, sidebar]);
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
    final notifier = ref.read(terminalWorkspaceProvider.notifier);

    void reorderTab(String tabId, {int? toIndex}) {
      notifier.reorderTab(tabId, toIndex ?? workspace.tabs.length);
    }

    Widget actionButton({
      required String tooltip,
      required Widget icon,
      required VoidCallback onPressed,
    }) {
      final controlSize = _vertical
          ? (width ?? _workspaceTabBarWidth)
                .clamp(_minWorkspaceTabBarWidth, _workspaceTabBarHeight)
                .toDouble()
          : _workspaceTabBarHeight;
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
            final pane = focusedPaneId == null
                ? null
                : workspace.panes[focusedPaneId];
            if (pane == null) return;
            for (final tabId in [...pane.tabIds]) {
              notifier.closeTab(tabId);
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
              padding: EdgeInsets.zero,
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
                final paneId = workspace.paneIdForTab(tab.id);
                final selected = tab.id == workspace.selectedTab?.id;
                return _DraggablePaneTab(
                  key: ValueKey(tab.id),
                  tab: tab,
                  selected: selected,
                  index: index,
                  position: position,
                  height: height,
                  compact: compact,
                  onSelect: () {
                    if (paneId == null) return;
                    notifier.selectTab(tab.id, paneId: paneId);
                    tab.session.controller.requestFocus();
                  },
                  onClose: () => notifier.closeTab(tab.id),
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
      color: scheme.surfaceContainerHigh.withValues(alpha: 0.64),
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

class _DraggablePaneTab extends StatelessWidget {
  const _DraggablePaneTab({
    super.key,
    required this.tab,
    required this.selected,
    required this.index,
    required this.position,
    required this.height,
    required this.compact,
    required this.onSelect,
    required this.onClose,
    required this.onAccept,
  });

  final TerminalTab tab;
  final bool selected;
  final int index;
  final TabBarPosition position;
  final double height;
  final bool compact;
  final VoidCallback onSelect;
  final VoidCallback onClose;
  final void Function(_TabDragData data, int insertIndex) onAccept;

  bool get _vertical =>
      position == TabBarPosition.left || position == TabBarPosition.right;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final chip = _PaneTabChip(
      tab: tab,
      selected: selected,
      position: position,
      height: height,
      compact: compact,
      onSelect: onSelect,
      onClose: onClose,
    );
    final dragData = _TabDragData(tabId: tab.id);
    final feedback = Material(
      elevation: 4,
      color: scheme.surfaceContainerHighest,
      child: SizedBox(
        width: _vertical ? _workspaceTabBarWidth : null,
        height: height,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Symbols.terminal, size: 16, color: scheme.onSurfaceVariant),
              if (!compact) ...[
                const SizedBox(width: 6),
                Text(tab.title, style: Theme.of(context).textTheme.labelMedium),
              ],
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
          width: _vertical ? double.infinity : null,
          height: height,
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

class _PaneTabChip extends StatelessWidget {
  const _PaneTabChip({
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
    final selectedBorder = BorderSide(
      color: selected
          ? scheme.primary.withValues(alpha: 0.68)
          : Colors.transparent,
      width: _tabBarBorderThickness,
    );
    final controlSize = height.clamp(0, _workspaceTabBarHeight).toDouble();
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
          onTap: onSelect,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: _vertical
                  ? Border(
                      left: position == TabBarPosition.left
                          ? selectedBorder
                          : BorderSide.none,
                      right: position == TabBarPosition.right
                          ? selectedBorder
                          : BorderSide.none,
                    )
                  : Border(bottom: selectedBorder),
            ),
            child: Align(
              alignment: compact ? Alignment.center : Alignment.centerLeft,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: compact ? 0 : 16),
                child: Row(
                  mainAxisSize: compact
                      ? MainAxisSize.min
                      : _vertical
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
                        fit: _vertical ? FlexFit.tight : FlexFit.loose,
                        child: Text(
                          tab.title,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                color: selected ? scheme.primary : null,
                              ),
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
            ),
          ),
        ),
      ),
    );
    return compact ? Tooltip(message: tab.title, child: chip) : chip;
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
