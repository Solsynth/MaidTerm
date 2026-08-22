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
/// palette derives from the same surface colors so the window chrome and
/// the terminal canvas agree.
ThemeData createMaidTermTheme(Brightness brightness, {Color? seedColor}) {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: seedColor ?? const Color(0xFF0F766E),
    brightness: brightness,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    brightness: brightness,
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
  const MaidTermWindowScaffold({super.key, required this.child, this.title});

  final Widget child;
  final String? title;

  @override
  Widget build(BuildContext context) {
    return flutter.Theme(
      data: _createWindowFrameTheme(Theme.of(context)),
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
          // Keep the frame's existing surface painting while providing the
          // Flutter SDK Material ancestor required by legacy controls.
          type: flutter.MaterialType.transparency,
          child: DesktopWindowFrame(
            onClose: windowManager.destroy,
            isDesktopPlatform: DesktopWindowFrame.isPlatformDesktop,
            // NOTE: island's macOS title bar renders only the title and
            // ignores additionalTitleBarActions; app actions live in the
            // toolbar row inside the workspace instead.
            title: Text(
              title ?? 'MaidTerm',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Supplies the Flutter Material theme consumed by legacy widgets inside
/// Island's window frame, derived from the modern app theme.
flutter.ThemeData _createWindowFrameTheme(ThemeData theme) {
  final colors = theme.colorScheme;
  final colorScheme =
      flutter.ColorScheme.fromSeed(
        seedColor: colors.primary,
        brightness: colors.brightness,
      ).copyWith(
        primary: colors.primary,
        onPrimary: colors.onPrimary,
        surface: colors.surface,
        onSurface: colors.onSurface,
        surfaceContainer: colors.surfaceContainer,
        onSurfaceVariant: colors.onSurfaceVariant,
        outline: colors.outline,
      );

  return flutter.ThemeData(
    brightness: colors.brightness,
    useMaterial3: true,
    colorScheme: colorScheme,
    iconTheme: flutter.IconThemeData(
      color: theme.iconTheme.color ?? colors.onSurface,
    ),
  );
}
