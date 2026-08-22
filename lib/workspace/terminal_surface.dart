import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:maidterm/maidterm.dart' as maidterm;

import '../settings/terminal_color_scheme.dart';
import '../settings/terminal_fonts.dart';
import '../settings/terminal_settings.dart';
import 'terminal_workspace.dart';

/// Renders one terminal with the settings-derived theme. The palette follows
/// the app brightness: light settings use the light scheme, dark use dark.
class TerminalSurface extends ConsumerWidget {
  const TerminalSurface({super.key, required this.tab});

  final TerminalTab tab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(terminalSettingsProvider).value;
    // Watching the font provider ensures persisted system fonts are loaded
    // before the terminal uses the family during startup.
    final fontFamily = ref.watch(terminalFontFamilyProvider);
    final brightness = Theme.of(context).brightness;
    final scheme = settings == null
        ? TerminalColorSchemes.defaultScheme
        : (brightness == Brightness.light
              ? settings.lightTheme
              : settings.darkTheme);

    // Cursor style and blink are part of the controller config; apply them
    // live so changing the setting takes effect on the current session.
    if (settings != null) {
      final config = tab.session.controller.config;
      if (config.cursorStyle != settings.cursorStyle ||
          config.cursorBlink != settings.cursorBlink) {
        tab.session.controller.config = config.copyWith(
          cursorStyle: settings.cursorStyle,
          cursorBlink: settings.cursorBlink,
        );
      }
    }

    final transparent = settings?.transparentBackground ?? false;
    maidterm.TerminalTheme buildTheme(bool fullScreen) =>
        maidterm.TerminalTheme(
          palette: maidterm.ColorPalette(
            ansiColors: scheme.ansiColors,
            background: scheme.background,
            foreground: scheme.foreground,
          ),
          cursor: maidterm.CursorTheme(
            color: maidterm.DynamicColor.fixed(scheme.cursor),
          ),
          selection: maidterm.SelectionTheme(
            background: maidterm.DynamicColor.fixed(scheme.selection),
          ),
          cursorMotionDuration: const Duration(milliseconds: 90),
          fontFamily: fontFamily,
          fontSize: settings?.fontSize ?? 14.0,
          backgroundOpacity: transparent && !fullScreen ? 0 : 1,
        );

    final normalMargin = settings?.normalPaneMargin ?? const EdgeInsets.all(8);
    final fullScreenMargin = settings?.fullScreenPaneMargin ?? EdgeInsets.zero;
    return ValueListenableBuilder<bool>(
      valueListenable: tab.session.isFullScreen,
      builder: (context, fullScreen, _) {
        return maidterm.TerminalView(
          controller: tab.session.controller,
          theme: buildTheme(fullScreen),
          autofocus: true,
          // Alternate-screen ownership is the terminal protocol's
          // full-screen signal. Apply the selected mode's margins.
          padding: fullScreen ? fullScreenMargin : normalMargin,
        );
      },
    );
  }
}
