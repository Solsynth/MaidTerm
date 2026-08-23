import 'dart:async';
import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:maidterm/maidterm.dart' as maidterm;
import 'package:shared_preferences/shared_preferences.dart';

import 'terminal_color_scheme.dart';
import 'terminal_fonts.dart';

/// Placement of the workspace-wide tab bar.
enum TabBarPosition { top, bottom, left, right }

/// User-tunable appearance and terminal behavior, persisted locally.
@immutable
class TerminalSettings {
  const TerminalSettings({
    this.fontSize = 14.0,
    this.cursorBlink = true,
    this.cursorStyle = maidterm.CursorShape.block,
    this.shellPath,
    this.normalPaneMargin = const EdgeInsets.all(8),
    this.fontFamily = TerminalFonts.defaultFamily,
    this.lightTheme = TerminalColorSchemes.defaultLightScheme,
    this.darkTheme = TerminalColorSchemes.defaultScheme,
    this.transparentBackground = false,
    this.themeMode = ThemeMode.dark,
    this.seedColor = const Color(0xFF0F766E),
    this.tabBarPosition = TabBarPosition.top,
    this.tabBarWidth = 180.0,
  });

  final double fontSize;
  final bool cursorBlink;
  final maidterm.CursorShape cursorStyle;
  final String? shellPath;

  /// Padding around normal shell output.
  final EdgeInsets normalPaneMargin;

  /// Terminal font family (engine-registered name).
  final String fontFamily;

  /// Palette used when the app renders in light mode.
  final TerminalColorScheme lightTheme;

  /// Palette used when the app renders in dark mode.
  final TerminalColorScheme darkTheme;

  /// Transparent terminal background (lets the window surface show through).
  final bool transparentBackground;

  /// App theme mode: system, light or dark.
  final ThemeMode themeMode;

  /// App accent seed color.
  final Color seedColor;

  /// Position of the shared workspace tab bar.
  final TabBarPosition tabBarPosition;

  /// Width of left/right tab bars in logical pixels.
  final double tabBarWidth;

  TerminalSettings copyWith({
    double? fontSize,
    bool? cursorBlink,
    maidterm.CursorShape? cursorStyle,
    String? shellPath,
    EdgeInsets? normalPaneMargin,
    String? fontFamily,
    TerminalColorScheme? lightTheme,
    TerminalColorScheme? darkTheme,
    bool? transparentBackground,
    ThemeMode? themeMode,
    Color? seedColor,
    TabBarPosition? tabBarPosition,
    double? tabBarWidth,
  }) => TerminalSettings(
    fontSize: fontSize ?? this.fontSize,
    cursorBlink: cursorBlink ?? this.cursorBlink,
    cursorStyle: cursorStyle ?? this.cursorStyle,
    shellPath: shellPath ?? this.shellPath,
    normalPaneMargin: normalPaneMargin ?? this.normalPaneMargin,
    fontFamily: fontFamily ?? this.fontFamily,
    lightTheme: lightTheme ?? this.lightTheme,
    darkTheme: darkTheme ?? this.darkTheme,
    transparentBackground: transparentBackground ?? this.transparentBackground,
    themeMode: themeMode ?? this.themeMode,
    seedColor: seedColor ?? this.seedColor,
    tabBarPosition: tabBarPosition ?? this.tabBarPosition,
    tabBarWidth: tabBarWidth ?? this.tabBarWidth,
  );
}

final terminalSettingsProvider =
    AsyncNotifierProvider<TerminalSettingsNotifier, TerminalSettings>(
      TerminalSettingsNotifier.new,
    );

class TerminalSettingsNotifier extends AsyncNotifier<TerminalSettings> {
  static const _fontSizeKey = 'terminal.fontSize';
  static const _cursorBlinkKey = 'terminal.cursorBlink';
  static const _cursorStyleKey = 'terminal.cursorStyle';
  static const _shellPathKey = 'terminal.shellPath';
  static const _normalPaneMarginKey = 'terminal.normalPaneMargin';
  static const _fontFamilyKey = 'terminal.fontFamily';
  static const _lightThemeKey = 'terminal.lightTheme';
  static const _tabBarWidthKey = 'terminal.tabBarWidth';
  static const _darkThemeKey = 'terminal.darkTheme';
  static const _transparentKey = 'terminal.transparentBackground';
  static const _themeModeKey = 'app.themeMode';
  static const _seedColorKey = 'app.seedColor';
  static const _tabBarPositionKey = 'terminal.tabBarPosition';

  @override
  Future<TerminalSettings> build() async {
    final prefs = await SharedPreferences.getInstance();
    return TerminalSettings(
      fontSize: prefs.getDouble(_fontSizeKey) ?? 14.0,
      cursorBlink: prefs.getBool(_cursorBlinkKey) ?? true,
      cursorStyle: switch (prefs.getString(_cursorStyleKey)) {
        'bar' => maidterm.CursorShape.bar,
        'underline' => maidterm.CursorShape.underline,
        _ => maidterm.CursorShape.block,
      },
      shellPath: prefs.getString(_shellPathKey),
      normalPaneMargin: _decodePaneMargin(
        prefs.getString(_normalPaneMarginKey),
        const EdgeInsets.all(8),
      ),
      fontFamily:
          prefs.getString(_fontFamilyKey) ?? TerminalFonts.defaultFamily,
      lightTheme:
          _decodeTheme(prefs.getString(_lightThemeKey)) ??
          TerminalColorSchemes.defaultLightScheme,
      darkTheme:
          _decodeTheme(prefs.getString(_darkThemeKey)) ??
          TerminalColorSchemes.defaultScheme,
      transparentBackground: prefs.getBool(_transparentKey) ?? false,
      themeMode: switch (prefs.getString(_themeModeKey)) {
        'system' => ThemeMode.system,
        'light' => ThemeMode.light,
        _ => ThemeMode.dark,
      },
      seedColor: Color(prefs.getInt(_seedColorKey) ?? 0xFF0F766E),
      tabBarWidth: _sanitizeTabBarWidth(
        prefs.getDouble(_tabBarWidthKey) ?? 180.0,
      ),
      tabBarPosition: switch (prefs.getString(_tabBarPositionKey)) {
        'bottom' => TabBarPosition.bottom,
        'left' => TabBarPosition.left,
        'right' => TabBarPosition.right,
        _ => TabBarPosition.top,
      },
    );
  }

  Future<void> setNormalPaneMargin(EdgeInsets value) async {
    final margin = _sanitizePaneMargin(value);
    await _update(state.value!.copyWith(normalPaneMargin: margin));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_normalPaneMarginKey, _encodePaneMargin(margin));
  }

  Future<void> _update(TerminalSettings next) async {
    state = AsyncData(next);
  }

  Future<void> setFontSize(double value) async {
    await _update(state.value!.copyWith(fontSize: value));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_fontSizeKey, value);
  }

  Future<void> setCursorBlink(bool value) async {
    await _update(state.value!.copyWith(cursorBlink: value));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_cursorBlinkKey, value);
  }

  Future<void> setCursorStyle(maidterm.CursorShape value) async {
    await _update(state.value!.copyWith(cursorStyle: value));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cursorStyleKey, value.name);
  }

  Future<void> setShellPath(String? value) async {
    await _update(state.value!.copyWith(shellPath: value));
    final prefs = await SharedPreferences.getInstance();
    if (value == null || value.isEmpty) {
      await prefs.remove(_shellPathKey);
    } else {
      await prefs.setString(_shellPathKey, value);
    }
  }

  Future<void> setFontFamily(String value) async {
    await _update(state.value!.copyWith(fontFamily: value));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_fontFamilyKey, value);
  }

  Future<void> setLightTheme(TerminalColorScheme value) async {
    await _update(state.value!.copyWith(lightTheme: value));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lightThemeKey, _encodeTheme(value));
  }

  Future<void> setDarkTheme(TerminalColorScheme value) async {
    await _update(state.value!.copyWith(darkTheme: value));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_darkThemeKey, _encodeTheme(value));
  }

  Future<void> setTransparentBackground(bool value) async {
    await _update(state.value!.copyWith(transparentBackground: value));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_transparentKey, value);
  }

  Future<void> setThemeMode(ThemeMode value) async {
    await _update(state.value!.copyWith(themeMode: value));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeModeKey, value.name);
  }

  Future<void> setSeedColor(Color value) async {
    await _update(state.value!.copyWith(seedColor: value));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_seedColorKey, value.toARGB32());
  }

  Future<void> setTabBarWidth(double value) async {
    final width = _sanitizeTabBarWidth(value);
    await _update(state.value!.copyWith(tabBarWidth: width));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_tabBarWidthKey, width);
  }

  Future<void> setTabBarPosition(TabBarPosition value) async {
    await _update(state.value!.copyWith(tabBarPosition: value));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tabBarPositionKey, value.name);
  }
}

double _sanitizeTabBarWidth(double value) {
  if (!value.isFinite) return 180.0;
  return value.clamp(36.0, 360.0).toDouble();
}

EdgeInsets _sanitizePaneMargin(EdgeInsets value) {
  double clampValue(double component) {
    if (!component.isFinite) return 0;
    return component.clamp(0, 256).toDouble();
  }

  return EdgeInsets.fromLTRB(
    clampValue(value.left),
    clampValue(value.top),
    clampValue(value.right),
    clampValue(value.bottom),
  );
}

String _encodePaneMargin(EdgeInsets margin) => jsonEncode({
  'left': margin.left,
  'top': margin.top,
  'right': margin.right,
  'bottom': margin.bottom,
});

EdgeInsets _decodePaneMargin(String? encoded, EdgeInsets fallback) {
  if (encoded == null) return fallback;
  try {
    final json = jsonDecode(encoded) as Map<String, dynamic>;
    return _sanitizePaneMargin(
      EdgeInsets.fromLTRB(
        (json['left'] as num).toDouble(),
        (json['top'] as num).toDouble(),
        (json['right'] as num).toDouble(),
        (json['bottom'] as num).toDouble(),
      ),
    );
  } on Object {
    return fallback;
  }
}

String _encodeTheme(TerminalColorScheme theme) => jsonEncode({
  'id': theme.id,
  'label': theme.label,
  'background': theme.background.toARGB32(),
  'foreground': theme.foreground.toARGB32(),
  'cursor': theme.cursor.toARGB32(),
  'selection': theme.selection.toARGB32(),
  'ansi': theme.ansiColors.map((color) => color.toARGB32()).toList(),
});

TerminalColorScheme? _decodeTheme(String? encoded) {
  if (encoded == null) return null;
  try {
    final json = jsonDecode(encoded) as Map<String, dynamic>;
    final ansi = (json['ansi'] as List<dynamic>)
        .map((value) => Color(value as int))
        .toList();
    return TerminalColorScheme(
      id: json['id'] as String? ?? 'custom',
      label: json['label'] as String? ?? 'Custom',
      background: Color(json['background'] as int),
      foreground: Color(json['foreground'] as int),
      cursor: Color(json['cursor'] as int),
      selection: Color(json['selection'] as int),
      ansiColors: ansi,
    );
  } catch (_) {
    return null;
  }
}
