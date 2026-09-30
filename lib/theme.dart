import 'dart:io';

import 'package:flutter/material.dart' as flutter;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_localizations/flutter_localizations.dart'
    as flutter_localizations;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:nativeapi_flutter/nativeapi_flutter.dart' as na;

import 'windows/workspace_windows.dart';

/// The application-wide Material theme. Keep feature widgets dependent on
/// this shared foundation instead of creating local colour schemes or chrome.
///
/// Terminals are dark tools: MaidTerm ships dark-only, and the terminal
ThemeData createMaidTermTheme(
  Brightness brightness, {
  Color? seedColor,
  double windowTransparency = 0.0,
}) {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: seedColor ?? const Color(0xFF0F766E),
    brightness: brightness,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    brightness: brightness,
    scaffoldBackgroundColor: colorScheme.surface.withValues(
      alpha: 1.0 - windowTransparency,
    ),
    fontFamily: 'IBM Plex Sans',
    appBarTheme: const AppBarTheme(centerTitle: false),
    inputDecorationTheme: InputDecorationThemeData(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
    ),
  );
}

/// Desktop window chrome: the Island frame plus the theme bridge that keeps
/// legacy Flutter widgets inside the frame on the app theme.
///
/// Island's `DesktopWindowFrame` mixes modern `material_ui` widgets and
/// legacy Flutter widgets. Without a Flutter-side `Theme` and localization
/// override, the legacy parts fall back to stock defaults and the title bar
/// looks like a different app. This mirrors MaidKit's
/// `MaidKitWindowScaffold`.
///
/// The frame talks to its own window through
/// [WorkspaceWindowsController] rather than a process-wide window handle,
/// so every window of the app drags and closes itself.
class MaidTermWindowScaffold extends ConsumerStatefulWidget {
  const MaidTermWindowScaffold({
    super.key,
    required this.windowId,
    required this.child,
    this.title,
    this.menuButton,
    this.windowTransparency = 0.0,
  });

  /// The window this frame belongs to.
  final String windowId;
  final Widget child;
  final String? title;

  /// Optional leading menu button shown in the title bar. When present the
  /// title text is centered instead of left-aligned.
  final Widget? menuButton;

  /// Window transparency level (0 = opaque, 1 = fully see-through).
  /// The frame surface fades with it so the desktop shows through.
  final double windowTransparency;

  @override
  ConsumerState<MaidTermWindowScaffold> createState() =>
      _MaidTermWindowScaffoldState();
}

class _MaidTermWindowScaffoldState
    extends ConsumerState<MaidTermWindowScaffold> {
  final FocusNode _keyboardFocusNode = FocusNode(
    debugLabel: 'window-frame',
    skipTraversal: true,
  );

  @override
  void initState() {
    super.initState();
    // Something has to own the keyboard before a terminal claims it, or the
    // first shortcut of a fresh window is dropped.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _keyboardFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _keyboardFocusNode.dispose();
    super.dispose();
  }

  na.Window? get _nativeWindow => ref
      .read(workspaceWindowsProvider)
      .windowById(widget.windowId)
      ?.native;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return flutter.Theme(
      data: _createWindowFrameTheme(
        Theme.of(context),
        windowTransparency: widget.windowTransparency,
      ),
      child: flutter.Localizations.override(
        context: context,
        delegates: const [
          // Both packages define distinct MaterialLocalizations types.
          ...GlobalMaterialLocalizations.delegates,
          flutter_localizations.GlobalCupertinoLocalizations.delegate,
          flutter_localizations.GlobalMaterialLocalizations.delegate,
          flutter_localizations.GlobalWidgetsLocalizations.delegate,
        ],
        child: flutter.Material(
          color: Colors.transparent,
          child: Theme(
            data: ThemeData(
              scaffoldBackgroundColor: theme.colorScheme.surface.withValues(
                alpha: 1.0 - widget.windowTransparency,
              ),
              colorScheme:
                  ColorScheme.fromSeed(
                    seedColor: theme.colorScheme.primary,
                    brightness: theme.colorScheme.brightness,
                  ).copyWith(
                    surface: theme.colorScheme.surface.withValues(
                      alpha: 1.0 - widget.windowTransparency,
                    ),
                    // The frame paints the single backdrop tone; keep every
                    // surface variant identical so titlebar, ground, tab bar
                    // and status bar render one uniform color.
                    surfaceContainer: theme.colorScheme.surface.withValues(
                      alpha: 1.0 - widget.windowTransparency,
                    ),
                    onSurface: theme.colorScheme.onSurface,
                    onSurfaceVariant: theme.colorScheme.onSurfaceVariant,
                    outline: theme.colorScheme.outline,
                  ),
            ),
            child: Focus(
              focusNode: _keyboardFocusNode,
              child: Material(
                color: Theme.of(context).colorScheme.surfaceContainer,
                child: Column(
                  children: [
                    _buildTitleBar(context),
                    Expanded(child: widget.child),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The title bar. On macOS the content sits under the real (transparent)
  /// title bar, so AppKit moves the window for drags that start there; on the
  /// other platforms the title bar is hidden and the frame has to move the
  /// window itself.
  Widget _buildTitleBar(BuildContext context) {
    final bar = SizedBox(
      height: _titleBarHeight,
      child: Stack(
        alignment: Alignment.center,
        children: [_buildTitle(context)],
      ),
    );
    if (Platform.isMacOS) return bar;
    final native = _nativeWindow;
    if (native == null) return bar;
    return na.DragToMoveArea(window: native, child: bar);
  }

  /// The title-bar content: a plain label, or — when [menuButton] is set —
  /// the label centered over a full-width bar with the button at the leading
  /// edge. The full-width layout is required because the frame centers
  /// whatever widget is passed as the title.
  Widget _buildTitle(BuildContext context) {
    final theme = Theme.of(context);
    final text = Text(
      widget.title ?? 'MaidTerm',
      style: theme.textTheme.labelLarge,
    );
    final button = widget.menuButton;
    if (button == null) return text;
    return SizedBox(
      width: double.infinity,
      height: _titleBarHeight,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(child: text),
          Align(
            alignment: Alignment.centerLeft,
            // macOS traffic lights float over the leading ~70px of the
            // transparent title bar; keep the menu button clear of them.
            child: Padding(
              padding: EdgeInsets.only(left: Platform.isMacOS ? 76 : 0),
              child: button,
            ),
          ),
        ],
      ),
    );
  }
}

const double _titleBarHeight = 32.0;

/// Supplies the Flutter Material theme consumed by legacy widgets inside
/// Island's window frame, derived from the modern app theme.
flutter.ThemeData _createWindowFrameTheme(
  ThemeData theme, {
  double windowTransparency = 0.0,
}) {
  final alpha = 1.0 - windowTransparency;
  final colors = theme.colorScheme;
  final colorScheme =
      flutter.ColorScheme.fromSeed(
        seedColor: colors.primary,
        brightness: colors.brightness,
      ).copyWith(
        primary: colors.primary,
        onPrimary: colors.onPrimary,
        surface: colors.surface.withValues(alpha: alpha),
        onSurface: colors.onSurface,
        surfaceContainer: colors.surfaceContainer.withValues(alpha: alpha),
        onSurfaceVariant: colors.onSurfaceVariant,
        outline: colors.outline,
      );

  return flutter.ThemeData(
    brightness: colors.brightness,
    useMaterial3: true,
    colorScheme: colorScheme,
    fontFamily: 'IBM Plex Sans',
    iconTheme: flutter.IconThemeData(
      color: theme.iconTheme.color ?? colors.onSurface,
    ),
  );
}
