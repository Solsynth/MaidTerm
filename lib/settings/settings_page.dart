import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:maidterm/maidterm.dart' as maidterm;

import 'terminal_color_scheme.dart';
import 'terminal_fonts.dart';
import 'terminal_settings.dart';
import 'terminal_theme_editor.dart';

/// Application appearance and terminal settings, modeled after MaidKit's
/// settings page.
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(terminalSettingsProvider);
    final data = settings.value;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const _SectionHeader('Appearance'),
          if (data == null)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            _ThemeModePicker(settings: data),
            const SizedBox(height: 16),
            _SeedColorPicker(settings: data),
            const Divider(height: 40),
            const _SectionHeader('Terminal'),
            const SizedBox(height: 16),
            const _TerminalFontDropdown(),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Monospace only',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(width: 4),
                Switch(
                  value: ref.watch(monospaceTerminalFontsOnlyProvider),
                  onChanged: (value) => ref
                      .read(monospaceTerminalFontsOnlyProvider.notifier)
                      .setEnabled(value),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const _FontSizeField(),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Cursor blink'),
              value: data.cursorBlink,
              onChanged: (v) =>
                  ref.read(terminalSettingsProvider.notifier).setCursorBlink(v),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Cursor style'),
              trailing: DropdownButton<maidterm.CursorShape>(
                value: data.cursorStyle,
                items: const [
                  DropdownMenuItem(
                    value: maidterm.CursorShape.block,
                    child: Text('Block'),
                  ),
                  DropdownMenuItem(
                    value: maidterm.CursorShape.bar,
                    child: Text('Bar'),
                  ),
                  DropdownMenuItem(
                    value: maidterm.CursorShape.underline,
                    child: Text('Underline'),
                  ),
                ],
                onChanged: (v) {
                  if (v != null) {
                    ref
                        .read(terminalSettingsProvider.notifier)
                        .setCursorStyle(v);
                  }
                },
              ),
            ),
            _TerminalThemeTile(
              mode: Brightness.light,
              theme: data.lightTheme,
              onEdit: () => _editTheme(context, ref, Brightness.light),
            ),
            _TerminalThemeTile(
              mode: Brightness.dark,
              theme: data.darkTheme,
              onEdit: () => _editTheme(context, ref, Brightness.dark),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Transparent background'),
              subtitle: const Text('Lets the window surface show through'),
              value: data.transparentBackground,
              onChanged: (v) => ref
                  .read(terminalSettingsProvider.notifier)
                  .setTransparentBackground(v),
            ),
            TextField(
              controller: TextEditingController(text: data.shellPath ?? ''),
              decoration: const InputDecoration(
                labelText: 'Shell (empty = default)',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (v) => ref
                  .read(terminalSettingsProvider.notifier)
                  .setShellPath(v.trim()),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _editTheme(
    BuildContext context,
    WidgetRef ref,
    Brightness brightness,
  ) async {
    final isLight = brightness == Brightness.light;
    final current = ref.read(terminalSettingsProvider).value;
    if (current == null) return;
    final updated = await showTerminalThemeEditor(
      context,
      brightness: brightness,
      initialScheme: isLight ? current.lightTheme : current.darkTheme,
    );
    if (updated == null) return;
    final notifier = ref.read(terminalSettingsProvider.notifier);
    if (isLight) {
      await notifier.setLightTheme(updated);
    } else {
      await notifier.setDarkTheme(updated);
    }
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }
}

class _ThemeModePicker extends ConsumerWidget {
  const _ThemeModePicker({required this.settings});

  final TerminalSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Theme'),
        const SizedBox(height: 4),
        Text(
          'Follows the system when set to System',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        SegmentedButton<ThemeMode>(
          segments: const [
            ButtonSegment(
              value: ThemeMode.system,
              label: Text('System'),
              icon: Icon(Icons.brightness_auto),
            ),
            ButtonSegment(
              value: ThemeMode.light,
              label: Text('Light'),
              icon: Icon(Icons.light_mode),
            ),
            ButtonSegment(
              value: ThemeMode.dark,
              label: Text('Dark'),
              icon: Icon(Icons.dark_mode),
            ),
          ],
          selected: {settings.themeMode},
          onSelectionChanged: (selection) => ref
              .read(terminalSettingsProvider.notifier)
              .setThemeMode(selection.first),
        ),
      ],
    );
  }
}

class _SeedColorPicker extends ConsumerWidget {
  const _SeedColorPicker({required this.settings});

  final TerminalSettings settings;

  static const _presets = [
    Color(0xFF0F766E), // teal
    Color(0xFF6750A4), // material purple
    Color(0xFF00639B), // blue
    Color(0xFF006D3A), // green
    Color(0xFF904A00), // amber
    Color(0xFFB3261E), // red
    Color(0xFF7D5260), // rose
    Color(0xFF4A4458), // neutral
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Accent color'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final color in _presets)
              InkWell(
                onTap: () => ref
                    .read(terminalSettingsProvider.notifier)
                    .setSeedColor(color),
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: settings.seedColor == color
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.outlineVariant,
                      width: settings.seedColor == color ? 3 : 1,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// System font picker with a monospace filter and a manual entry field for
/// fonts that are not listed.
class _TerminalFontDropdown extends ConsumerWidget {
  const _TerminalFontDropdown();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fonts = ref.watch(availableTerminalFontsProvider);
    final monoOnly = ref.watch(monospaceTerminalFontsOnlyProvider);
    final current = ref.watch(terminalFontFamilyProvider);

    final all = fonts.value ?? const <TerminalFontOption>[];
    final filtered = <TerminalFontOption>[
      for (final option in all)
        if (!monoOnly || option.label.toLowerCase().contains('mono')) option,
    ];
    if (!filtered.any((option) => option.family == current)) {
      filtered.insert(0, TerminalFontOption(label: current, family: current));
    }

    void setFontFamily(String? family) {
      if (family != null && family.trim().isNotEmpty) {
        ref.read(terminalFontFamilyProvider.notifier).setFontFamily(family);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          initialValue: current,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Terminal font',
            border: OutlineInputBorder(),
          ),
          items: [
            for (final option in filtered)
              DropdownMenuItem(
                value: option.family,
                child: Text(
                  option.label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontFamily: option.family),
                ),
              ),
          ],
          onChanged: setFontFamily,
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Monospace only',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(width: 4),
            Switch(
              value: monoOnly,
              onChanged: (value) => ref
                  .read(monospaceTerminalFontsOnlyProvider.notifier)
                  .setEnabled(value),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: TextEditingController(text: current),
          decoration: const InputDecoration(
            labelText: 'Custom font family',
            hintText: 'e.g. FiraCode Nerd Font',
            border: OutlineInputBorder(),
          ),
          onSubmitted: setFontFamily,
        ),
      ],
    );
  }
}

/// Numeric entry for the terminal font size.
class _FontSizeField extends ConsumerWidget {
  const _FontSizeField();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final size = ref.watch(
      terminalSettingsProvider.select(
        (settings) => settings.value?.fontSize ?? 14.0,
      ),
    );

    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 120),
        child: TextField(
          key: ValueKey(size),
          controller: TextEditingController(text: size.toStringAsFixed(0)),
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            labelText: 'Font size (pt)',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (value) {
            final parsed = double.tryParse(value);
            if (parsed != null && parsed >= 6 && parsed <= 48) {
              ref.read(terminalSettingsProvider.notifier).setFontSize(parsed);
            }
          },
        ),
      ),
    );
  }
}

class _TerminalThemeTile extends StatelessWidget {
  const _TerminalThemeTile({
    required this.mode,
    required this.theme,
    required this.onEdit,
  });

  final Brightness mode;
  final TerminalColorScheme theme;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: TerminalPalettePreview(theme: theme),
      title: Text(mode == Brightness.light ? 'Light theme' : 'Dark theme'),
      subtitle: Text('${theme.label} · tap to edit'),
      trailing: const Icon(Symbols.edit),
      onTap: onEdit,
    );
  }
}
