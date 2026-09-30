import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:maidterm/maidterm.dart' as maidterm;

import '../settings/terminal_color_scheme.dart';
import '../settings/terminal_settings.dart';
import '../settings/background_image.dart';
import '../windows/tab_strip_geometry.dart';
import '../windows/workspace_windows.dart';

import 'session_layout.dart';
import 'terminal_surface.dart';
import 'terminal_workspace.dart';
import 'machine_status_bar.dart';

/// The main screen of one window: a tab strip around resizable split panes.
class TerminalWorkspacePage extends ConsumerWidget {
  const TerminalWorkspacePage({
    super.key,
    required this.windowId,
    this.onAppKeyEvent,
    this.onSelectNextTab,
    this.onSelectPaneNumber,
  });

  /// The window whose tabs this page renders.
  final String windowId;
  final FocusOnKeyEventCallback? onAppKeyEvent;
  final VoidCallback? onSelectNextTab;
  final ValueChanged<int>? onSelectPaneNumber;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workspace = ref.watch(terminalWorkspaceProvider(windowId));
    late final Widget workspaceContent;
    if (workspace.tabs.isEmpty) {
      workspaceContent = _EmptyWorkspace(windowId: windowId);
    } else {
      final root = workspace.layout;
      if (root == null) {
        workspaceContent = _EmptyWorkspace(windowId: windowId);
      } else {
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
            windowId: windowId,
            workspace: workspace,
            position: tabBarPosition,
            width: width,
            height: height,
          ),
        );
        final vertical =
            tabBarPosition == TabBarPosition.left ||
            tabBarPosition == TabBarPosition.right;
        final tabBarFirst =
            tabBarPosition == TabBarPosition.top ||
            tabBarPosition == TabBarPosition.left;
        final ground = _WorkspaceGround(
          child: _LayoutNode(
            windowId: windowId,
            node: root,
            onAppKeyEvent: onAppKeyEvent,
            onSelectNextTab: onSelectNextTab,
            onSelectPaneNumber: onSelectPaneNumber,
          ),
        );
        final layout = Expanded(
          child: vertical
              ? ClipRRect(
                  key: const ValueKey('workspace-ground-clip'),
                  borderRadius: BorderRadius.only(
                    topLeft: tabBarPosition == TabBarPosition.left
                        ? const Radius.circular(_workspaceCornerRadius)
                        : Radius.zero,
                    bottomLeft: tabBarPosition == TabBarPosition.left
                        ? const Radius.circular(_workspaceCornerRadius)
                        : Radius.zero,
                    topRight: tabBarPosition == TabBarPosition.right
                        ? const Radius.circular(_workspaceCornerRadius)
                        : Radius.zero,
                    bottomRight: tabBarPosition == TabBarPosition.right
                        ? const Radius.circular(_workspaceCornerRadius)
                        : Radius.zero,
                  ),
                  child: ground,
                )
              : ground,
        );
        workspaceContent = vertical
            ? Row(children: tabBarFirst ? [tabBar, layout] : [layout, tabBar])
            : Column(
                children: tabBarFirst ? [tabBar, layout] : [layout, tabBar],
              );
      }
    }

    return Column(
      children: [
        Expanded(child: workspaceContent),
        MachineStatusBar(windowId: windowId),
      ],
    );
  }
}

class _EmptyWorkspace extends ConsumerWidget {
  const _EmptyWorkspace({required this.windowId});

  final String windowId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _WorkspaceGround(
      child: Center(
        child: FilledButton.icon(
          onPressed: () => ref
              .read(terminalWorkspaceProvider(windowId).notifier)
              .openTerminal(),
          icon: const Icon(Symbols.add),
          label: Text('workspaceNewTerminal'.tr()),
        ),
      ),
    );
  }
}

/// The workspace ground: a `surface` field (or the subdued
/// background image) that the flat pane layout rests on. Ground remains
/// visible around every pane and between split panes.
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
        color: Colors.transparent,
        // One image spans the whole pane layout: split panes share it
        // instead of each rendering their own copy.
        image: hasBackgroundImage
            ? DecorationImage(
                image: FileImage(backgroundImage),
                fit: BoxFit.cover,
                opacity: 0.18,
                colorFilter: ColorFilter.mode(
                  scheme.surface.withValues(alpha: 0.48),
                  BlendMode.srcOver,
                ),
              )
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.all(_workspaceGroundPadding),
        child: child,
      ),
    );
  }
}

class _LayoutNode extends ConsumerWidget {
  const _LayoutNode({
    required this.windowId,
    required this.node,
    this.onAppKeyEvent,
    this.onSelectNextTab,
    this.onSelectPaneNumber,
  });

  final String windowId;
  final PaneLayout node;
  final FocusOnKeyEventCallback? onAppKeyEvent;
  final VoidCallback? onSelectNextTab;
  final ValueChanged<int>? onSelectPaneNumber;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    switch (node) {
      case PaneLayoutLeaf(:final paneId):
        return _TerminalPaneView(
          windowId: windowId,
          paneId: paneId,
          onAppKeyEvent: onAppKeyEvent,
          onSelectNextTab: onSelectNextTab,
          onSelectPaneNumber: onSelectPaneNumber,
        );
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
              .read(terminalWorkspaceProvider(windowId).notifier)
              .setSplitRatio(id, value),
          first: _LayoutNode(
            windowId: windowId,
            node: first,
            onAppKeyEvent: onAppKeyEvent,
            onSelectNextTab: onSelectNextTab,
            onSelectPaneNumber: onSelectPaneNumber,
          ),
          second: _LayoutNode(
            windowId: windowId,
            node: second,
            onAppKeyEvent: onAppKeyEvent,
            onSelectNextTab: onSelectNextTab,
            onSelectPaneNumber: onSelectPaneNumber,
          ),
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
  const _TerminalPaneView({
    required this.windowId,
    required this.paneId,
    this.onAppKeyEvent,
    this.onSelectNextTab,
    this.onSelectPaneNumber,
  });

  final String windowId;
  final String paneId;
  final FocusOnKeyEventCallback? onAppKeyEvent;
  final VoidCallback? onSelectNextTab;
  final ValueChanged<int>? onSelectPaneNumber;

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    final appResult = onAppKeyEvent?.call(node, event);
    if (appResult != null && appResult != KeyEventResult.ignored) {
      return appResult;
    }
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    if (event.logicalKey == LogicalKeyboardKey.tab &&
        keyboard.isControlPressed &&
        !keyboard.isMetaPressed &&
        !keyboard.isAltPressed &&
        !keyboard.isShiftPressed) {
      onSelectNextTab?.call();
      return KeyEventResult.handled;
    }
    final number = _paneNumberForKey(event.logicalKey);
    if (number != null &&
        keyboard.isMetaPressed &&
        !keyboard.isControlPressed &&
        !keyboard.isAltPressed &&
        !keyboard.isShiftPressed) {
      onSelectPaneNumber?.call(number);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workspace = ref.watch(terminalWorkspaceProvider(windowId));
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
    final backgroundImage = ref
        .watch(maidTermBackgroundImageProvider)
        .asData
        ?.value;
    final backgroundImageEnabled =
        ref.watch(maidTermBackgroundImageEnabledProvider).asData?.value ?? true;
    final hasBackgroundImage =
        backgroundImageEnabled && backgroundImage != null;
    final windowTransparency = settings?.windowTransparency ?? 0.0;
    final windowTransparent = windowTransparency > 0;
    final paneBackgroundOpacity = settings?.paneBackgroundOpacity ?? 1.0;
    // An enabled image is the terminal backdrop; the surface stays
    // transparent so the shared pane-layout image shows through. A
    // transparent window makes every surface see-through so the desktop
    // itself shows behind the terminal.
    final transparent =
        (settings?.transparentBackground ?? false) ||
        hasBackgroundImage ||
        windowTransparent;
    final terminal = selected == null
        ? ColoredBox(
            key: const ValueKey('terminal-pane-backdrop'),
            color: transparent
                ? Colors.transparent
                : terminalScheme.background.withValues(
                    alpha: 1.0 - windowTransparency,
                  ),
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
                        .read(terminalWorkspaceProvider(windowId).notifier)
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
                    window: ref
                        .read(workspaceWindowsProvider)
                        .windowById(windowId)
                        ?.native,
                    autofocus: focused,
                    onKeyEvent: _handleKeyEvent,
                  ),
                ),
              ],
            ),
          );

    final scheme = Theme.of(context).colorScheme;
    final paneBorderWidth = 1 / MediaQuery.devicePixelRatioOf(context);
    // A shadow over a transparent terminal darkens the shared image beneath.
    final paneAlpha =
        paneBackgroundOpacity * (1.0 - windowTransparency * 0.64);
    final paneColor = hasBackgroundImage
        ? scheme.surfaceContainerHigh.withValues(alpha: 0.64)
        : windowTransparent
            ? scheme.surfaceContainerHigh.withValues(alpha: paneAlpha)
            : paneBackgroundOpacity < 1.0
                ? scheme.surfaceContainerHigh.withValues(
                    alpha: paneBackgroundOpacity,
                  )
                : scheme.surfaceContainerHigh;
    final showPaneShadow = focused && !transparent;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => ref
          .read(terminalWorkspaceProvider(windowId).notifier)
          .focusPane(paneId),
      child: AnimatedContainer(
        duration: _paneTransitionDuration,
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: focused
              ? paneColor
              : Color.lerp(paneColor, scheme.surface, 0.26),
          borderRadius: BorderRadius.circular(_paneRadius),
          // Inactive panes stay completely flat; transparent panes stay flat
          // too, so the background image remains clean beneath the terminal.
          boxShadow: showPaneShadow
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.22),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ]
              : const [],
        ),
        // Paint the physical-pixel hairline over the pane so it does not
        // steal space from the terminal surface.
        foregroundDecoration: BoxDecoration(
          border: Border.all(
            color: (focused ? scheme.outline : scheme.outlineVariant)
                .withValues(alpha: focused ? 0.72 : 0.46),
            width: paneBorderWidth,
          ),
          borderRadius: BorderRadius.circular(_paneRadius),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(_paneRadius),
          child: TweenAnimationBuilder<double>(
            duration: _paneTransitionDuration,
            curve: Curves.easeOutCubic,
            tween: Tween<double>(end: focused ? 0 : 1),
            builder: (context, inactiveAmount, child) => ColorFiltered(
              colorFilter: ColorFilter.matrix(_paneColorMatrix(inactiveAmount)),
              child: child,
            ),
            child: terminal,
          ),
        ),
      ),
    );
  }
}

int? _paneNumberForKey(LogicalKeyboardKey key) => switch (key) {
  LogicalKeyboardKey.digit1 => 1,
  LogicalKeyboardKey.digit2 => 2,
  LogicalKeyboardKey.digit3 => 3,
  LogicalKeyboardKey.digit4 => 4,
  LogicalKeyboardKey.digit5 => 5,
  LogicalKeyboardKey.digit6 => 6,
  LogicalKeyboardKey.digit7 => 7,
  LogicalKeyboardKey.digit8 => 8,
  LogicalKeyboardKey.digit9 => 9,
  LogicalKeyboardKey.digit0 => 10,
  _ => null,
};

const _workspaceTabBarHeight = 40.0;
const _workspaceTabBarWidth = 180.0;
const _compactTabBarWidth = 160.0;
const _minWorkspaceTabBarWidth = 48.0;

/// The flat ground around the whole layout and between split panes.
const _workspaceGroundPadding = 10.0;

/// The corner that tucks the workspace ground under the title bar beside a
/// vertical (left/right) tab bar, mirroring MaidKit's rounded content sheet.
const _workspaceCornerRadius = 12.0;
const _paneGap = 10.0;
const _paneRadius = 14.0;
const _paneTransitionDuration = Duration(milliseconds: 220);
const _tabBarHandleWidth = 1.0;
const _tabEntryVerticalPadding = 2.0;

/// Space between the stacked pane rows of one tab in a vertical strip.
const _paneTabGap = 4.0;

List<double> _paneColorMatrix(double inactiveAmount) {
  // Keep inactive panes readable, but make focus unmistakable at a glance.
  final saturation = 1 - (0.62 * inactiveAmount);
  final grayscale = 1 - saturation;
  final brightness = 1 - (0.16 * inactiveAmount);
  return [
    brightness * (0.2126 * grayscale + saturation),
    brightness * (0.7152 * grayscale),
    brightness * (0.0722 * grayscale),
    0,
    0,
    brightness * (0.2126 * grayscale),
    brightness * (0.7152 * grayscale + saturation),
    brightness * (0.0722 * grayscale),
    0,
    0,
    brightness * (0.2126 * grayscale),
    brightness * (0.7152 * grayscale),
    brightness * (0.0722 * grayscale + saturation),
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ];
}

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
    required this.windowId,
    required this.workspace,
    required this.position,
    required this.width,
    required this.height,
  });

  final String windowId;
  final TerminalWorkspaceState workspace;
  final TabBarPosition position;
  final double? width;
  final double height;

  bool get _vertical =>
      position == TabBarPosition.left || position == TabBarPosition.right;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final windows = ref.watch(workspaceWindowsProvider);
    final registry = windows.windowById(windowId)?.strip;
    if (registry != null) {
      // The drag controller measures this strip and reorders from it, so it
      // has to know both its axis and its live tab set.
      registry.axis = _vertical ? Axis.vertical : Axis.horizontal;
      registry.retain([for (final tab in workspace.tabs) tab.id]);
    }
    return LayoutBuilder(
      builder: (context, constraints) => _buildTabBar(
        context,
        ref,
        windows,
        registry,
        _vertical && (width ?? _workspaceTabBarWidth) <= _compactTabBarWidth,
      ),
    );
  }

  Widget _buildTabBar(
    BuildContext context,
    WidgetRef ref,
    WorkspaceWindowsController windows,
    TabStripRegistry? registry,
    bool compact,
  ) {
    final drag = windows.tabDrag;
    final draggingHere = drag != null && drag.windowId == windowId;
    final overlay = draggingHere && drag.mode == TabDragMode.inStrip
        ? _buildDragOverlay(context, ref, windows, drag, compact)
        : null;

    final tabs = SingleChildScrollView(
      scrollDirection: _vertical ? Axis.vertical : Axis.horizontal,
      padding: EdgeInsets.only(
        top: _vertical ? _verticalTabStripTopMargin : 0,
        left: 4,
        right: 4,
      ),
      child: Flex(
        direction: _vertical ? Axis.vertical : Axis.horizontal,
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final tab in workspace.tabs)
            _buildTabSlot(context, ref, windows, registry, tab, compact),
          // Room to drop past the last tab, matching the old strip tail.
          SizedBox(
            width: _vertical ? double.infinity : 28,
            height: _vertical ? 28 : height,
          ),
        ],
      ),
    );

    return Material(
      key: const ValueKey('workspace-tab-bar'),
      color: Colors.transparent,
      child: SizedBox(
        key: registry?.stripKey,
        width: _vertical ? (width ?? _workspaceTabBarWidth) : null,
        height: _vertical ? null : height,
        child: Stack(
          children: [
            Positioned.fill(child: tabs),
            ?overlay,
          ],
        ),
      ),
    );
  }

  Widget _buildTabSlot(
    BuildContext context,
    WidgetRef ref,
    WorkspaceWindowsController windows,
    TabStripRegistry? registry,
    TerminalWorkspaceTab tab,
    bool compact,
  ) {
    final drag = windows.tabDrag;
    final dragged =
        drag != null && drag.tabId == tab.id && drag.windowId == windowId;
    final actions = windows.actionsFor(windowId);

    return _TabDragSlot(
      // Measured while the drag runs to place the tab under the cursor.
      key: registry?.keyFor(tab.id),
      windowId: windowId,
      tabId: tab.id,
      placeholder: dragged && drag.mode == TabDragMode.inStrip,
      placeholderSize: drag?.chipSize ?? Size.zero,
      onActivate: () {
        final notifier = ref.read(
          terminalWorkspaceProvider(windowId).notifier,
        );
        notifier.selectTab(tab.id);
        notifier.focusPane(tab.focusedPaneId);
      },
      child: _WorkspaceTabEntry(
        tab: tab,
        selected: tab.id == workspace.selectedTab?.id,
        position: position,
        height: height,
        compact: compact,
        onSelectPane: (paneId) {
          final notifier = ref.read(
            terminalWorkspaceProvider(windowId).notifier,
          );
          notifier.selectTab(tab.id);
          notifier.focusPane(paneId);
        },
        onClosePane: (paneId) =>
            unawaited(actions.closePaneInTab(tab.id, paneId)),
      ),
    );
  }

  /// The chip that follows the cursor while a tab is dragged. Its slot in the
  /// strip renders as a gap instead, so the strip's layout stays measurable.
  Widget? _buildDragOverlay(
    BuildContext context,
    WidgetRef ref,
    WorkspaceWindowsController windows,
    TabDragInfo drag,
    bool compact,
  ) {
    TerminalWorkspaceTab? draggedTab;
    for (final tab in workspace.tabs) {
      if (tab.id == drag.tabId) draggedTab = tab;
    }
    if (draggedTab == null) return null;
    final registry = windows.windowById(windowId)?.strip;
    final stripBox = registry?.stripKey.currentContext?.findRenderObject();
    if (stripBox is! RenderBox || !stripBox.hasSize) return null;
    final origin = stripBox.globalToLocal(drag.cursor - drag.grab);
    final actions = windows.actionsFor(windowId);

    return Positioned(
      left: origin.dx,
      top: origin.dy,
      width: drag.chipSize.width,
      height: drag.chipSize.height,
      child: IgnorePointer(
        child: Material(
          color: Colors.transparent,
          child: _WorkspaceTabEntry(
            tab: draggedTab,
            selected: true,
            position: position,
            height: height,
            compact: compact,
            onSelectPane: (paneId) => actions.selectTabPane(draggedTab!.id, paneId),
            onClosePane: (paneId) =>
                unawaited(actions.closePaneInTab(draggedTab!.id, paneId)),
          ),
        ),
      ),
    );
  }
}

/// Hosts one tab's chip and starts the drag that moves it between windows.
///
/// The press is handed to a native drag session, which keeps reporting the
/// cursor while the tab crosses into another window's view; where that is not
/// possible the same slot falls back to reordering from Flutter's own pointer.
class _TabDragSlot extends ConsumerStatefulWidget {
  const _TabDragSlot({
    super.key,
    required this.windowId,
    required this.tabId,
    required this.placeholder,
    required this.placeholderSize,
    required this.onActivate,
    required this.child,
  });

  final String windowId;
  final String tabId;

  /// True while this tab is being dragged: its chip is painted by the overlay.
  final bool placeholder;
  final Size placeholderSize;

  /// Pointer went down on the tab; selects it before any drag can start.
  final VoidCallback onActivate;
  final Widget child;

  @override
  ConsumerState<_TabDragSlot> createState() => _TabDragSlotState();
}

class _TabDragSlotState extends ConsumerState<_TabDragSlot> {
  int? _pointer;
  var _localDrag = false;

  @override
  Widget build(BuildContext context) {
    if (widget.placeholder) {
      return SizedBox(
        width: widget.placeholderSize.width,
        height: widget.placeholderSize.height,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.primary.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }
    return Listener(
      onPointerDown: (event) {
        _pointer = event.pointer;
        if (event.buttons & kPrimaryMouseButton != 0) widget.onActivate();
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        dragStartBehavior: DragStartBehavior.down,
        onPanStart: _onPanStart,
        onPanUpdate: _onPanUpdate,
        onPanEnd: (_) => _endLocalDrag(),
        onPanCancel: _endLocalDrag,
        child: widget.child,
      ),
    );
  }

  void _onPanStart(DragStartDetails details) {
    final object = context.findRenderObject();
    if (object is! RenderBox || !object.hasSize) return;
    final pointer = details.globalPosition;
    final grab = object.globalToLocal(pointer);
    final grabInView = object.localToGlobal(Offset.zero) + grab;
    final windows = ref.read(workspaceWindowsProvider);
    final native = windows.beginTabDrag(
      windowId: widget.windowId,
      tabId: widget.tabId,
      grab: grab,
      grabInView: grabInView,
      chipSize: object.size,
      pointerInView: pointer,
    );
    if (native) {
      // The native session owns the rest of the gesture: the widget that saw
      // the press can end up in another window, which never sees the release.
      final pointerId = _pointer;
      if (pointerId != null) GestureBinding.instance.cancelPointer(pointerId);
      return;
    }
    _localDrag = true;
    windows.beginLocalTabDrag(
      windowId: widget.windowId,
      tabId: widget.tabId,
      grab: grab,
      grabInView: grabInView,
      chipSize: object.size,
      pointerInView: pointer,
    );
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (!_localDrag) return;
    ref
        .read(workspaceWindowsProvider)
        .updateLocalTabDrag(details.globalPosition);
  }

  void _endLocalDrag() {
    if (!_localDrag) return;
    _localDrag = false;
    ref.read(workspaceWindowsProvider).endLocalTabDrag();
  }
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
        // A vertical strip stacks entries, so each one keeps the bottom half
        // of its spacing to hold the row pitch the tab bar had before.
        padding: EdgeInsets.only(
          left: 3,
          right: 3,
          top: verticalPadding,
          bottom: vertical ? verticalPadding : 0,
        ),
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
      padding: EdgeInsets.symmetric(horizontal: 3, vertical: verticalPadding),
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
            for (var i = 0; i < panes.length; i++) ...[
              if (i > 0 && _vertical) const SizedBox(height: _paneTabGap),
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
          ],
        ),
      ),
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
        padding: EdgeInsets.symmetric(horizontal: compact ? 0 : 10),
        child: Row(
          mainAxisSize: compact
              ? MainAxisSize.min
              : vertical
              ? MainAxisSize.max
              : MainAxisSize.min,
          children: [
            ValueListenableBuilder<bool>(
              valueListenable: tab.session.isOutputActive,
              builder: (context, outputActive, _) =>
                  ValueListenableBuilder<maidterm.TerminalProgress?>(
                    valueListenable: tab.session.progress,
                    builder: (context, progress, _) {
                      final color = switch (progress?.state) {
                        .error => scheme.error,
                        .paused => scheme.tertiary,
                        _ => selected ? scheme.primary : scheme.onSurface,
                      };
                      if ((progress == null ||
                              progress.state == .remove ||
                              progress.state == .paused) &&
                          !outputActive) {
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
                          value: outputActive
                              ? null
                              : progress?.value == null
                              ? null
                              : progress!.value! / 100,
                          color: color,
                        ),
                      );
                    },
                  ),
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
                tooltip: 'workspaceCloseTab'.tr(),
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
