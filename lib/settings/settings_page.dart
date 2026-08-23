import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:maidterm/maidterm.dart' as maidterm;

import 'terminal_color_scheme.dart';
import 'terminal_fonts.dart';
import 'background_image.dart';
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
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        elevation: 0,
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 40),
              children: [
                const _SettingsIntro(),
                if (data == null)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 48),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else ...[
                  _SettingsSection(
                    title: 'Appearance',
                    description: 'Theme and accent used across the workspace.',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _ThemeModePicker(settings: data),
                        const SizedBox(height: 20),
                        _SeedColorPicker(settings: data),
                      ],
                    ),
                  ),
                  _SettingsSection(
                    title: 'Background image',
                    description: 'Show a subtle image behind transparent terminal surfaces.',
                    child: const _BackgroundImageSettings(),
                  ),
                  _SettingsSection(
                    title: 'Typography',
                    description: 'Choose the face and scale of terminal text.',
                    child: const _TerminalFontDropdown(),
                  ),
                  _SettingsSection(
                    title: 'Behavior',
                    description: 'Small details that shape the terminal feel.',
                    child: Column(
                      children: [
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Cursor blink'),
                          subtitle: const Text(
                            'Show movement when the terminal is ready',
                          ),
                          value: data.cursorBlink,
                          onChanged: (v) => ref
                              .read(terminalSettingsProvider.notifier)
                              .setCursorBlink(v),
                        ),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Cursor style'),
                          subtitle: const Text(
                            'The shape used for the active cell',
                          ),
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
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Transparent background'),
                          subtitle: const Text(
                            'Show the workspace background through the terminal',
                          ),
                          value: data.transparentBackground,
                          onChanged: (v) => ref
                              .read(terminalSettingsProvider.notifier)
                              .setTransparentBackground(v),
                        ),
                      ],
                    ),
                  ),
                  _SettingsSection(
                    title: 'Tab bar',
                    description:
                        'Choose where the shared workspace tab bar appears.',
                    child: _TabBarPositionPicker(settings: data),
                  ),
                  _SettingsSection(
                    title: 'Title bar',
                    description:
                        'Window chrome for platforms without a system menu bar.',
                    child: SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Show menu button'),
                      subtitle: const Text(
                        'Shows the app menu at the top-left of the title bar '
                        'and centers the title',
                      ),
                      value: data.showTitleBarMenuButton,
                      onChanged: (v) => ref
                          .read(terminalSettingsProvider.notifier)
                          .setShowTitleBarMenuButton(v),
                    ),
                  ),
                  _SettingsSection(
                    title: 'Pane margins',
                    description: 'Set independent margins for normal output and terminal UIs that paint almost the full grid.',
                    child: _PaneMarginSettings(
                      normalMargin: data.normalPaneMargin,
                      fullScreenMargin: data.fullScreenPaneMargin,
                      onNormalChanged: (value) => ref
                          .read(terminalSettingsProvider.notifier)
                          .setNormalPaneMargin(value),
                      onFullScreenChanged: (value) => ref
                          .read(terminalSettingsProvider.notifier)
                          .setFullScreenPaneMargin(value),
                    ),
                  ),
                  _SettingsSection(
                    title: 'Terminal themes',
                    description:
                        'Tune the palettes used in light and dark mode.',
                    child: Column(
                      children: [
                        _TerminalThemeTile(
                          mode: Brightness.light,
                          theme: data.lightTheme,
                          onEdit: () =>
                              _editTheme(context, ref, Brightness.light),
                        ),
                        _TerminalThemeTile(
                          mode: Brightness.dark,
                          theme: data.darkTheme,
                          onEdit: () =>
                              _editTheme(context, ref, Brightness.dark),
                        ),
                      ],
                    ),
                  ),
                  _SettingsSection(
                    title: 'Shell',
                    description: 'Use a specific shell, or leave this blank for the system default.',
                    child: TextField(
                      controller: TextEditingController(
                        text: data.shellPath ?? '',
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Shell path',
                        hintText: 'Default shell',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (v) => ref
                          .read(terminalSettingsProvider.notifier)
                          .setShellPath(v.trim()),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
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

class _SettingsIntro extends StatelessWidget {
  const _SettingsIntro();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'TERMINAL PREFERENCES',
            style: theme.textTheme.labelSmall?.copyWith(
              fontFamily: 'IBM Plex Mono',
              letterSpacing: 1.4,
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _TabBarPositionPicker extends ConsumerWidget {
  const _TabBarPositionPicker({required this.settings});

  final TerminalSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SegmentedButton<TabBarPosition>(
      segments: const [
        ButtonSegment(value: TabBarPosition.top, label: Text('Top')),
        ButtonSegment(value: TabBarPosition.bottom, label: Text('Bottom')),
        ButtonSegment(value: TabBarPosition.left, label: Text('Left')),
        ButtonSegment(value: TabBarPosition.right, label: Text('Right')),
      ],
      selected: {settings.tabBarPosition},
      onSelectionChanged: (selection) => ref
          .read(terminalSettingsProvider.notifier)
          .setTabBarPosition(selection.first),
    );
  }
}

class _BackgroundImageSettings extends ConsumerWidget {
  const _BackgroundImageSettings();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final image = ref.watch(maidTermBackgroundImageProvider).asData?.value;
    final enabled =
        ref.watch(maidTermBackgroundImageEnabledProvider).asData?.value ?? true;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (image != null) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: double.infinity,
              height: 148,
              child: Image.file(
                image,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => ColoredBox(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: const Center(child: Icon(Symbols.broken_image)),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            image.path.split(Platform.pathSeparator).last,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'IBM Plex Mono',
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Show background image'),
            value: enabled,
            onChanged: (value) => setMaidTermBackgroundImageEnabled(ref, value),
          ),
        ] else
          Text(
            'No image selected.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: () => _chooseImage(context, ref),
              icon: const Icon(Symbols.image),
              label: const Text('Choose image'),
            ),
            if (image != null)
              TextButton.icon(
                onPressed: () => clearMaidTermBackgroundImage(ref),
                icon: const Icon(Symbols.delete_outline),
                label: const Text('Clear image'),
              ),
          ],
        ),
      ],
    );
  }

  Future<void> _chooseImage(BuildContext context, WidgetRef ref) async {
    // MaidTerm is intentionally not sandboxed. file_picker's entitlement
    // guard must be bypassed for this desktop configuration.
    final selection = await FilePicker.pickFiles(
      dialogTitle: 'Choose background image',
      type: FileType.image,
    );
    final path = selection.isEmpty ? null : selection.first.path;
    if (path == null) return;

    try {
      await saveMaidTermBackgroundImage(ref, File(path));
    } on Object catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save background image: $error')),
      );
    }
  }
}

class _PaneMarginSettings extends StatelessWidget {
  const _PaneMarginSettings({
    required this.normalMargin,
    required this.fullScreenMargin,
    required this.onNormalChanged,
    required this.onFullScreenChanged,
  });

  final EdgeInsets normalMargin;
  final EdgeInsets fullScreenMargin;
  final ValueChanged<EdgeInsets> onNormalChanged;
  final ValueChanged<EdgeInsets> onFullScreenChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PaneMarginEditor(
          key: const ValueKey('normal-pane-margin'),
          title: 'Normal mode',
          margin: normalMargin,
          onChanged: onNormalChanged,
        ),
        const SizedBox(height: 20),
        _PaneMarginEditor(
          key: const ValueKey('fullscreen-pane-margin'),
          title: 'Full-screen mode',
          margin: fullScreenMargin,
          onChanged: onFullScreenChanged,
        ),
      ],
    );
  }
}

class _PaneMarginEditor extends StatefulWidget {
  const _PaneMarginEditor({
    super.key,
    required this.title,
    required this.margin,
    required this.onChanged,
  });

  final String title;
  final EdgeInsets margin;
  final ValueChanged<EdgeInsets> onChanged;

  @override
  State<_PaneMarginEditor> createState() => _PaneMarginEditorState();
}

class _PaneMarginEditorState extends State<_PaneMarginEditor> {
  static const _labels = ['Left', 'Top', 'Right', 'Bottom'];
  late final List<TextEditingController> _controllers;

  @override
  void initState() {
    super.initState();
    _controllers = _values(widget.margin)
        .map((value) => TextEditingController(text: value.toString()))
        .toList();
  }

  @override
  void didUpdateWidget(_PaneMarginEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.margin != widget.margin) {
      final values = _values(widget.margin);
      for (var i = 0; i < values.length; i++) {
        _controllers[i].text = values[i].toString();
      }
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _commit() {
    final values = <double>[];
    for (var i = 0; i < _controllers.length; i++) {
      final value = double.tryParse(_controllers[i].text);
      if (value == null || !value.isFinite || value < 0) {
        _controllers[i].text = _values(widget.margin)[i].toString();
        return;
      }
      values.add(value);
    }
    final next = EdgeInsets.fromLTRB(
      values[0],
      values[1],
      values[2],
      values[3],
    );
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.title, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (var i = 0; i < _labels.length; i++)
              SizedBox(
                width: 96,
                child: TextField(
                  key: ValueKey('${widget.title}:margin-$i'),
                  controller: _controllers[i],
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    labelText: _labels[i],
                    suffixText: 'px',
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _commit(),
                ),
              ),
          ],
        ),
      ],
    );
  }

  static List<double> _values(EdgeInsets margin) => [
    margin.left,
    margin.top,
    margin.right,
    margin.bottom,
  ];
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.title,
    required this.description,
    required this.child,
  });

  final String title;
  final String description;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 3,
                height: 20,
                margin: const EdgeInsets.only(top: 2, right: 10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _ThemeModePicker extends ConsumerWidget {
  const _ThemeModePicker({required this.settings});

  final TerminalSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SegmentedButton<ThemeMode>(
      segments: const [
        ButtonSegment(value: ThemeMode.system, label: Text('System')),
        ButtonSegment(value: ThemeMode.light, label: Text('Light')),
        ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
      ],
      selected: {settings.themeMode},
      onSelectionChanged: (selection) => ref
          .read(terminalSettingsProvider.notifier)
          .setThemeMode(selection.first),
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

    final familyField = DropdownButtonFormField<String>(
      initialValue: current,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Font family',
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
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final sizeField = SizedBox(
              width: 132,
              child: const _FontSizeField(),
            );
            if (constraints.maxWidth < 420) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [familyField, const SizedBox(height: 12), sizeField],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: familyField),
                const SizedBox(width: 12),
                sizeField,
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        TextField(
          controller: TextEditingController(text: current),
          decoration: const InputDecoration(
            labelText: 'Custom family',
            hintText: 'e.g. Fira Code',
            border: OutlineInputBorder(),
          ),
          onSubmitted: setFontFamily,
        ),
        const SizedBox(height: 4),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Monospace only'),
          subtitle: const Text('Keep the font list focused on terminal faces'),
          value: monoOnly,
          onChanged: (value) => ref
              .read(monospaceTerminalFontsOnlyProvider.notifier)
              .setEnabled(value),
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

    return TextField(
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
