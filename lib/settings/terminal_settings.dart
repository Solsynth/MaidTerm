import 'dart:async';
import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:maidterm/maidterm.dart' as maidterm;
import 'package:shared_preferences/shared_preferences.dart';

import 'terminal_color_scheme.dart';
import 'terminal_fonts.dart';

/// A machine signal shown in the optional workspace status bar.
enum StatusMetric { cpu, memory, network, battery }

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
    this.fullScreenPaneMargin = EdgeInsets.zero,
    this.fontFamily = TerminalFonts.defaultFamily,
    this.lightTheme = TerminalColorSchemes.defaultLightScheme,
    this.darkTheme = TerminalColorSchemes.defaultScheme,
    this.transparentBackground = false,
    this.windowTransparency = 0.0,
    this.paneBackgroundOpacity = 1.0,
    this.themeMode = ThemeMode.dark,
    this.seedColor = const Color(0xFF0F766E),
    this.tabBarPosition = TabBarPosition.top,
    this.tabBarWidth = 180.0,
    this.showTitleBarMenuButton = false,
    this.showStatusBar = false,
    this.statusBarMetrics = const [
      StatusMetric.cpu,
      StatusMetric.memory,
      StatusMetric.network,
    ],
    this.statusBarRefreshSeconds = 2,
    this.statusBarHistoryMinutes = 5,
  });

  final double fontSize;
  final bool cursorBlink;
  final maidterm.CursorShape cursorStyle;
  final String? shellPath;

  /// Padding around normal shell output.
  final EdgeInsets normalPaneMargin;

  /// Padding while an alternate screen paints an almost full-grid background.
  final EdgeInsets fullScreenPaneMargin;

  /// Terminal font family (engine-registered name).
  final String fontFamily;

  /// Palette used when the app renders in light mode.
  final TerminalColorScheme lightTheme;

  /// Palette used when the app renders in dark mode.
  final TerminalColorScheme darkTheme;

  /// Transparent terminal background (lets the window surface show through).
  final bool transparentBackground;

  /// Window transparency level (0 = opaque, 1 = fully see-through).
  final double windowTransparency;

  /// Opacity of the pane card background (1 = solid, 0 = fully see-through).
  final double paneBackgroundOpacity;

  /// App theme mode: system, light or dark.
  final ThemeMode themeMode;

  /// App accent seed color.
  final Color seedColor;

  /// Position of the shared workspace tab bar.
  final TabBarPosition tabBarPosition;

  /// Width of left/right tab bars in logical pixels.
  final double tabBarWidth;

  /// Shows the app menu at the top-left of the title bar and centers the
  /// title. Meant for platforms without a system menu bar.
  final bool showTitleBarMenuButton;

  /// Whether the floating machine status bar is visible.
  final bool showStatusBar;

  /// Signals rendered in the floating machine status bar.
  final List<StatusMetric> statusBarMetrics;

  /// Poll interval for machine signals, in seconds.
  final int statusBarRefreshSeconds;

  /// Amount of signal history rendered by the statusbar chart, in minutes.
  final int statusBarHistoryMinutes;

  TerminalSettings copyWith({
    double? fontSize,
    bool? cursorBlink,
    maidterm.CursorShape? cursorStyle,
    String? shellPath,
    EdgeInsets? normalPaneMargin,
    EdgeInsets? fullScreenPaneMargin,
    String? fontFamily,
    TerminalColorScheme? lightTheme,
    TerminalColorScheme? darkTheme,
    bool? transparentBackground,
    double? windowTransparency,
    double? paneBackgroundOpacity,
    ThemeMode? themeMode,
    Color? seedColor,
    TabBarPosition? tabBarPosition,
    double? tabBarWidth,
    bool? showTitleBarMenuButton,
    bool? showStatusBar,
    List<StatusMetric>? statusBarMetrics,
    int? statusBarRefreshSeconds,
    int? statusBarHistoryMinutes,
  }) => TerminalSettings(
    fontSize: fontSize ?? this.fontSize,
    cursorBlink: cursorBlink ?? this.cursorBlink,
    cursorStyle: cursorStyle ?? this.cursorStyle,
    shellPath: shellPath ?? this.shellPath,
    normalPaneMargin: normalPaneMargin ?? this.normalPaneMargin,
    fullScreenPaneMargin: fullScreenPaneMargin ?? this.fullScreenPaneMargin,
    fontFamily: fontFamily ?? this.fontFamily,
    lightTheme: lightTheme ?? this.lightTheme,
    darkTheme: darkTheme ?? this.darkTheme,
    windowTransparency: windowTransparency ?? this.windowTransparency,
    transparentBackground: transparentBackground ?? this.transparentBackground,
    paneBackgroundOpacity: paneBackgroundOpacity ?? this.paneBackgroundOpacity,
    themeMode: themeMode ?? this.themeMode,
    seedColor: seedColor ?? this.seedColor,
    tabBarPosition: tabBarPosition ?? this.tabBarPosition,
    tabBarWidth: tabBarWidth ?? this.tabBarWidth,
    showTitleBarMenuButton:
        showTitleBarMenuButton ?? this.showTitleBarMenuButton,
    showStatusBar: showStatusBar ?? this.showStatusBar,
    statusBarMetrics: statusBarMetrics ?? this.statusBarMetrics,
    statusBarRefreshSeconds:
        statusBarRefreshSeconds ?? this.statusBarRefreshSeconds,
    statusBarHistoryMinutes:
        statusBarHistoryMinutes ?? this.statusBarHistoryMinutes,
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
  static const _fullScreenPaneMarginKey = 'terminal.fullScreenPaneMargin';
  static const _fontFamilyKey = 'terminal.fontFamily';
  static const _lightThemeKey = 'terminal.lightTheme';
  static const _tabBarWidthKey = 'terminal.tabBarWidth';
  static const _windowTransparencyKey = 'app.windowTransparency';
  static const _paneBackgroundOpacityKey = 'app.paneBackgroundOpacity';
  static const _darkThemeKey = 'terminal.darkTheme';
  static const _transparentKey = 'terminal.transparentBackground';
  static const _themeModeKey = 'app.themeMode';
  static const _seedColorKey = 'app.seedColor';
  static const _tabBarPositionKey = 'terminal.tabBarPosition';
  static const _showTitleBarMenuButtonKey = 'terminal.showTitleBarMenuButton';
  static const _showStatusBarKey = 'terminal.showStatusBar';
  static const _statusBarMetricsKey = 'terminal.statusBarMetrics';
  static const _statusBarRefreshSecondsKey = 'terminal.statusBarRefreshSeconds';
  static const _statusBarHistoryMinutesKey = 'terminal.statusBarHistoryMinutes';

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
      fullScreenPaneMargin: _decodePaneMargin(
        prefs.getString(_fullScreenPaneMarginKey),
        EdgeInsets.zero,
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
      paneBackgroundOpacity:
          prefs.getDouble(_paneBackgroundOpacityKey)?.clamp(0.0, 1.0) ??
          1.0,
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
      showTitleBarMenuButton:
          prefs.getBool(_showTitleBarMenuButtonKey) ?? false,
      showStatusBar: prefs.getBool(_showStatusBarKey) ?? false,
      statusBarMetrics: _decodeStatusMetrics(
        prefs.getString(_statusBarMetricsKey),
      ),
      statusBarRefreshSeconds: _sanitizeStatusBarRefreshSeconds(
        prefs.getInt(_statusBarRefreshSecondsKey) ?? 2,
      ),
      statusBarHistoryMinutes: _sanitizeStatusBarHistoryMinutes(
        prefs.getInt(_statusBarHistoryMinutesKey) ?? 5,
      ),
    );
  }

  Future<void> setNormalPaneMargin(EdgeInsets value) async {
    final margin = _sanitizePaneMargin(value);
    await _update(state.value!.copyWith(normalPaneMargin: margin));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_normalPaneMarginKey, _encodePaneMargin(margin));
  }

  Future<void> setFullScreenPaneMargin(EdgeInsets value) async {
    final margin = _sanitizePaneMargin(value);
    await _update(state.value!.copyWith(fullScreenPaneMargin: margin));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_fullScreenPaneMarginKey, _encodePaneMargin(margin));
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

  Future<void> setWindowTransparency(double value) async {
    final clamped = value.clamp(0.0, 1.0);
    await _update(state.value!.copyWith(windowTransparency: clamped));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_windowTransparencyKey, clamped);
  }

  Future<void> setPaneBackgroundOpacity(double value) async {
    final clamped = value.clamp(0.0, 1.0);
    await _update(state.value!.copyWith(paneBackgroundOpacity: clamped));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_paneBackgroundOpacityKey, clamped);
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

  Future<void> setShowTitleBarMenuButton(bool value) async {
    await _update(state.value!.copyWith(showTitleBarMenuButton: value));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_showTitleBarMenuButtonKey, value);
  }

  Future<void> setShowStatusBar(bool value) async {
    await _update(state.value!.copyWith(showStatusBar: value));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_showStatusBarKey, value);
  }

  Future<void> setStatusBarMetrics(List<StatusMetric> value) async {
    final metrics = _sanitizeStatusMetrics(value);
    await _update(state.value!.copyWith(statusBarMetrics: metrics));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_statusBarMetricsKey, _encodeStatusMetrics(metrics));
  }

  Future<void> setStatusBarRefreshSeconds(int value) async {
    final seconds = _sanitizeStatusBarRefreshSeconds(value);
    await _update(state.value!.copyWith(statusBarRefreshSeconds: seconds));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_statusBarRefreshSecondsKey, seconds);
  }

  Future<void> setStatusBarHistoryMinutes(int value) async {
    final minutes = _sanitizeStatusBarHistoryMinutes(value);
    await _update(state.value!.copyWith(statusBarHistoryMinutes: minutes));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_statusBarHistoryMinutesKey, minutes);
  }
}

List<StatusMetric> _sanitizeStatusMetrics(Iterable<StatusMetric> values) {
  final unique = <StatusMetric>{...values};
  if (unique.isEmpty) return const [StatusMetric.cpu, StatusMetric.memory];
  return List.unmodifiable(unique);
}

String _encodeStatusMetrics(Iterable<StatusMetric> values) =>
    values.map((metric) => metric.name).join(',');

List<StatusMetric> _decodeStatusMetrics(String? encoded) {
  if (encoded == null || encoded.isEmpty) {
    return const [StatusMetric.cpu, StatusMetric.memory, StatusMetric.network];
  }
  final metrics = encoded
      .split(',')
      .map(
        (name) => switch (name) {
          'cpu' => StatusMetric.cpu,
          'memory' => StatusMetric.memory,
          'network' => StatusMetric.network,
          'battery' => StatusMetric.battery,
          _ => null,
        },
      )
      .whereType<StatusMetric>();
  return _sanitizeStatusMetrics(metrics);
}

int _sanitizeStatusBarHistoryMinutes(int value) => value.clamp(1, 30).toInt();

int _sanitizeStatusBarRefreshSeconds(int value) => value.clamp(1, 10).toInt();

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
