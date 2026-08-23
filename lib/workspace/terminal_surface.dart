import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:maidterm/maidterm.dart' as maidterm;

import '../settings/terminal_color_scheme.dart';
import '../settings/terminal_fonts.dart';
import '../settings/terminal_settings.dart';
import 'terminal_workspace.dart';

/// Renders one terminal with the settings-derived theme. The palette follows
/// the app brightness: light settings use the light scheme, dark use dark.
class TerminalSurface extends ConsumerStatefulWidget {
  const TerminalSurface({super.key, required this.tab, this.autofocus = true});

  final TerminalTab tab;
  final bool autofocus;

  @override
  ConsumerState<TerminalSurface> createState() => _TerminalSurfaceState();
}

class _TerminalSurfaceState extends ConsumerState<TerminalSurface> {
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(debugLabel: 'terminal-input')
      ..addListener(_onFocusChanged);
    if (widget.autofocus) {
      _requestFocusAfterBuild();
    }
  }

  void _onFocusChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(TerminalSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.autofocus &&
        (!oldWidget.autofocus || oldWidget.tab.id != widget.tab.id)) {
      _requestFocusAfterBuild();
    }
  }

  void _requestFocusAfterBuild() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.autofocus) {
        _focusNode.requestFocus();
        widget.tab.session.controller.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
      final config = widget.tab.session.controller.config;
      if (config.cursorStyle != settings.cursorStyle ||
          config.cursorBlink != settings.cursorBlink) {
        widget.tab.session.controller.config = config.copyWith(
          cursorStyle: settings.cursorStyle,
          cursorBlink: settings.cursorBlink,
        );
      }
    }

    final transparent = settings?.transparentBackground ?? false;
    final theme = maidterm.TerminalTheme(
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
      backgroundOpacity: transparent ? 0 : 1,
    );
    final margin = settings?.normalPaneMargin ?? const EdgeInsets.all(8);
    return maidterm.TerminalView(
      controller: widget.tab.session.controller,
      focusNode: _focusNode,
      theme: theme,
      autofocus: true,
      padding: margin,
    );
  }
}
