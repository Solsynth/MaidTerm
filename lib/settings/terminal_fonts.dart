import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:system_fonts/system_fonts.dart';

import 'terminal_settings.dart';

/// A selectable terminal font family.
class TerminalFontOption {
  const TerminalFontOption({required this.label, required this.family});

  /// Display name, without weight/style suffixes (e.g. `SFMono`).
  final String label;

  /// Font file name registered in the engine and used for rendering
  /// (e.g. `SFMono-Regular`).
  final String family;
}

/// Collapses font files of the same family into a single option, preferring
/// the regular weight variant. Ported from MaidKit.
abstract final class TerminalFonts {
  static const defaultFamily = 'JetBrains Mono';

  static const _variantKeywords = <String>[
    'extralightitalic',
    'extrabolditalic',
    'semibolditalic',
    'mediumitalic',
    'lightitalic',
    'blackitalic',
    'thinitalic',
    'bolditalic',
    'extralight',
    'extrabold',
    'semilight',
    'condensed',
    'semibold',
    'expanded',
    'regular',
    'oblique',
    'medium',
    'italic',
    'retina',
    'heavy',
    'black',
    'light',
    'ultra',
    'book',
    'bold',
    'demi',
    'thin',
    'text',
  ];

  static String sanitize(String family) {
    final trimmed = family.trim();
    return trimmed.isEmpty ? defaultFamily : trimmed;
  }

  static bool _isVariantSegment(String segment) {
    var rest = segment.toLowerCase();
    var matched = false;
    while (rest.isNotEmpty) {
      String? keyword;
      for (final candidate in _variantKeywords) {
        if (rest.startsWith(candidate)) {
          keyword = candidate;
          break;
        }
      }
      if (keyword == null) return false;
      matched = true;
      rest = rest.substring(keyword.length);
    }
    return matched;
  }

  static String _stripVariantSuffix(String name) {
    final dash = name.lastIndexOf('-');
    if (dash == -1) return name;
    final segment = name.substring(dash + 1);
    if (_isVariantSegment(segment)) {
      return name.substring(0, dash);
    }
    return name;
  }

  static String _pickRegular(List<String> names) {
    for (final name in names) {
      if (name.toLowerCase().endsWith('-regular')) return name;
    }
    final sorted = [...names]
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return sorted.first;
  }

  static List<TerminalFontOption> dedupe(List<String> families) {
    final byBase = <String, List<String>>{};
    for (final family in families) {
      byBase.putIfAbsent(_stripVariantSuffix(family), () => []).add(family);
    }
    final options = [
      for (final entry in byBase.entries)
        TerminalFontOption(label: entry.key, family: _pickRegular(entry.value)),
    ];
    options.sort(
      (a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()),
    );
    return options;
  }
}

/// The selected terminal font family, persisted through [TerminalSettings].
final terminalFontFamilyProvider =
    NotifierProvider<TerminalFontFamilyNotifier, String>(
      TerminalFontFamilyNotifier.new,
    );

class TerminalFontFamilyNotifier extends Notifier<String> {
  @override
  String build() {
    final value = TerminalFonts.sanitize(
      ref.read(terminalSettingsProvider).value?.fontFamily ??
          TerminalFonts.defaultFamily,
    );
    unawaited(_loadFont(value));
    return value;
  }

  Future<void> setFontFamily(String family) async {
    final value = TerminalFonts.sanitize(family);
    await _loadFont(value);
    await ref.read(terminalSettingsProvider.notifier).setFontFamily(value);
    state = value;
  }

  Future<void> _loadFont(String family) async {
    try {
      await SystemFonts().loadFont(family);
    } on Object {
      // Font not available on this system; rendering falls back.
    }
  }
}

/// All families available on this machine (plus the persisted/default ones).
final availableTerminalFontsProvider = FutureProvider<List<TerminalFontOption>>(
  (ref) async {
    final options = TerminalFonts.dedupe(SystemFonts().getFontList());
    final defaultOption = TerminalFontOption(
      label: TerminalFonts.defaultFamily,
      family: TerminalFonts.defaultFamily,
    );
    if (!options.any(
      (option) => option.family == TerminalFonts.defaultFamily,
    )) {
      options.insert(0, defaultOption);
    }
    final persisted = ref.read(terminalFontFamilyProvider);
    if (!options.any((option) => option.family == persisted)) {
      options.insert(0, TerminalFontOption(label: persisted, family: persisted));
    }
    return List.unmodifiable(options);
  },
);

/// Filter the font list to monospace families only.
final monospaceTerminalFontsOnlyProvider =
    NotifierProvider<MonospaceTerminalFontsOnlyNotifier, bool>(
      MonospaceTerminalFontsOnlyNotifier.new,
    );

class MonospaceTerminalFontsOnlyNotifier extends Notifier<bool> {
  @override
  bool build() => true;

  void setEnabled(bool enabled) => state = enabled;
}
