import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:maidterm/maidterm.dart' as maidterm;

import '../settings/terminal_color_scheme.dart';
import '../settings/terminal_fonts.dart';
import '../settings/background_image.dart';
import '../settings/terminal_settings.dart';
import '../shell/drop_paths.dart';
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
  var _dragHovered = false;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(debugLabel: 'terminal-input')
      ..addListener(_onFocusChanged);
    _requestFocusAfterBuild();
  }

  void _onFocusChanged() {
    if (mounted) setState(() {});
  }

  void _setDragHovered(bool value) {
    if (_dragHovered == value || !mounted) return;
    setState(() => _dragHovered = value);
  }

  /// Inserts OS-dropped file paths into the terminal input line, each
  /// shell-quoted so it reads as one argument. Paste encoding is preserved
  /// so image-aware TUIs can recognize image paths in bracketed paste data.
  /// The terminal keeps focus so the user can keep typing (or press Enter)
  /// right after the drop.
  void _handleDrop(DropDoneDetails details) {
    final paths = details.files
        .map((file) => file.path)
        .where((path) => path.isNotEmpty)
        .toList();
    if (paths.isEmpty) return;
    widget.tab.session.controller.paste(formatDroppedPaths(paths));
    _focusNode.requestFocus();
  }

  void _requestFocusAfterBuild() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.autofocus) {
        _focusNode.requestFocus();
        widget.tab.session.controller.requestFocus();
      }
      widget.tab.session.refreshResize();
    });
  }

  @override
  void didUpdateWidget(TerminalSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tab.id != widget.tab.id) {
      _requestFocusAfterBuild();
    }
  }

  /// Opens a detected link with the platform default handler.
  ///
  /// URIs open in the browser; file paths open with the OS file association
  /// (e.g. `open` on macOS, `xdg-open` on Linux, `start` on Windows).
  void _handleLinkActivate(maidterm.ActivatedLink link) {
    final uri = link.uri;
    if (uri != null) {
      _openExternal(uri.toString());
      return;
    }
    final file = link.file;
    if (file != null) {
      _openExternal(file.resolvedPath ?? file.path);
    }
  }

  Future<void> _openExternal(String target) async {
    try {
      if (Platform.isMacOS) {
        await Process.run('open', [target]);
      } else if (Platform.isWindows) {
        await Process.run('cmd', ['/c', 'start', '', target]);
      } else {
        await Process.run('xdg-open', [target]);
      }
    } on Exception catch (e) {
      debugPrint('Failed to open link "$target": $e');
    }
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

    // The stored image is the terminal backdrop: while one is enabled the
    // surface stays transparent so the shared pane-layout image shows
    // through, matching the transparent-background behavior.
    final imageEnabled =
        ref.watch(maidTermBackgroundImageProvider).asData?.value != null &&
        (ref.watch(maidTermBackgroundImageEnabledProvider).asData?.value ??
            true);
    final transparent =
        (settings?.transparentBackground ?? false) || imageEnabled;
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
          hyperlink: maidterm.HyperlinkTheme(
            idle: maidterm.HyperlinkStyle(underline: .single),
            highlighted: maidterm.HyperlinkStyle(
              underline: .single,
              backgroundColor: scheme.ansiColors.length > 4
                  ? scheme.ansiColors[4].withValues(alpha: 0.25)
                  : scheme.selection.withValues(alpha: 0.35),
            ),
          ),
          cursorMotionDuration: const Duration(milliseconds: 90),
          fontFamily: fontFamily,
          fontSize: settings?.fontSize ?? 14.0,
          backgroundOpacity: transparent && !fullScreen ? 0 : 1,
        );
    final normalMargin = settings?.normalPaneMargin ?? const EdgeInsets.all(8);
    final fullScreenMargin = settings?.fullScreenPaneMargin ?? EdgeInsets.zero;
    return ValueListenableBuilder<bool>(
      valueListenable: widget.tab.session.isFullScreen,
      builder: (context, fullScreen, _) {
        final margin = fullScreen ? fullScreenMargin : normalMargin;
        return DropTarget(
          onDragEntered: (_) => _setDragHovered(true),
          onDragExited: (_) => _setDragHovered(false),
          onDragDone: _handleDrop,
          child: Stack(
            children: [
              maidterm.TerminalView(
                controller: widget.tab.session.controller,
                focusNode: _focusNode,
                theme: buildTheme(fullScreen),
                autofocus: true,
                padding: margin,
                linkSettings: maidterm.LinkSettings(
                  onActivate: _handleLinkActivate,
                ),
                onVisualFullScreenChanged:
                    widget.tab.session.setVisualFullScreen,
              ),
              if (_dragHovered)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Container(
                      key: const ValueKey('file-drop-highlight'),
                      decoration: BoxDecoration(
                        border: Border.all(color: scheme.selection, width: 2),
                        // Matches the pane radius in terminal_workspace_page
                        // so the outline hugs the pane border, not the
                        // terminal's padded grid area.
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
