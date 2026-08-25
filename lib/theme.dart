import 'dart:io';

import 'package:flutter/material.dart' as flutter;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_localizations/flutter_localizations.dart'
    as flutter_localizations;
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:window_manager/window_manager.dart';

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
class MaidTermWindowScaffold extends StatelessWidget {
  const MaidTermWindowScaffold({
    super.key,
    required this.child,
    this.title,
    this.menuButton,
    this.windowTransparency = 0.0,
  });

  final Widget child;
  final String? title;

  /// Optional leading menu button shown in the title bar. When present the
  /// title text is centered instead of left-aligned.
  final Widget? menuButton;

  /// Window transparency level (0 = opaque, 1 = fully see-through).
  /// The frame surface fades with it so the desktop shows through.
  final double windowTransparency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return flutter.Theme(
      data: _createWindowFrameTheme(
        Theme.of(context),
        windowTransparency: windowTransparency,
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
                alpha: 1.0 - windowTransparency,
              ),
              colorScheme:
                  ColorScheme.fromSeed(
                    seedColor: theme.colorScheme.primary,
                    brightness: theme.colorScheme.brightness,
                  ).copyWith(
                    surface: theme.colorScheme.surface.withValues(
                      alpha: 1.0 - windowTransparency,
                    ),
                    // The frame paints the single backdrop tone; keep every
                    // surface variant identical so titlebar, ground, tab bar
                    // and status bar render one uniform color.
                    surfaceContainer: theme.colorScheme.surface.withValues(
                      alpha: 1.0 - windowTransparency,
                    ),
                    onSurface: theme.colorScheme.onSurface,
                    onSurfaceVariant: theme.colorScheme.onSurfaceVariant,
                    outline: theme.colorScheme.outline,
                  ),
            ),
            child: DesktopWindowFrame(
              onClose: windowManager.destroy,
              isDesktopPlatform: DesktopWindowFrame.isPlatformDesktop,
              // NOTE: island's macOS title bar renders only the title and
              // ignores additionalTitleBarActions; app actions live in the
              // toolbar row inside the workspace instead.
              title: _buildTitle(theme),
              child: child,
            ),
          ),
        ),
      ),
    );
  }

  /// The title-bar content: a plain label, or — when [menuButton] is set —
  /// the label centered over a full-width bar with the button at the leading
  /// edge. The full-width layout is required because island's macOS frame
  /// centers whatever widget is passed as the title.
  Widget _buildTitle(ThemeData theme) {
    final text = Text(title ?? 'MaidTerm', style: theme.textTheme.labelLarge);
    final button = menuButton;
    if (button == null) return text;
    return SizedBox(
      width: double.infinity,
      height: 32,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(child: text),
          Align(
            alignment: Alignment.centerLeft,
            // macOS traffic lights float over the leading ~70px of the
            // hidden title bar; keep the menu button clear of them.
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
