import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:maidterm/maidterm.dart' as maidterm;

import 'terminal_color_scheme.dart';
import 'about_page.dart';
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
        title: Text('settingsTitle'.tr()),
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
                    title: 'settingsAppearance'.tr(),
                    description: 'settingsAppearanceDescription'.tr(),
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
                    title: 'settingsLanguage'.tr(),
                    description: 'settingsLanguageDescription'.tr(),
                    child: DropdownButton<Locale>(
                      value: context.locale,
                      isExpanded: true,
                      items: const [
                        DropdownMenuItem(
                          value: Locale('en', 'US'),
                          child: Text('English'),
                        ),
                        DropdownMenuItem(
                          value: Locale('zh', 'CN'),
                          child: Text('简体中文'),
                        ),
                        DropdownMenuItem(
                          value: Locale('zh', 'TW'),
                          child: Text('繁體中文'),
                        ),
                      ],
                      onChanged: (locale) {
                        if (locale != null) {
                          context.setLocale(locale);
                        }
                      },
                    ),
                  ),
                  _SettingsSection(
                    title: 'settingsBackgroundImage'.tr(),
                    description: 'settingsBackgroundImageDescription'.tr(),
                    child: const _BackgroundImageSettings(),
                  ),
                  _SettingsSection(
                    title: 'settingsTypography'.tr(),
                    description: 'settingsTypographyDescription'.tr(),
                    child: const _TerminalFontDropdown(),
                  ),
                  _SettingsSection(
                    title: 'settingsBehavior'.tr(),
                    description: 'settingsBehaviorDescription'.tr(),
                    child: Column(
                      children: [
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text('settingsCursorBlink'.tr()),
                          subtitle: Text('settingsCursorBlinkDescription'.tr()),
                          value: data.cursorBlink,
                          onChanged: (v) => ref
                              .read(terminalSettingsProvider.notifier)
                              .setCursorBlink(v),
                        ),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text('settingsCursorStyle'.tr()),
                          subtitle: Text('settingsCursorStyleDescription'.tr()),
                          trailing: DropdownButton<maidterm.CursorShape>(
                            value: data.cursorStyle,
                            items: [
                              DropdownMenuItem(
                                value: maidterm.CursorShape.block,
                                child: Text('settingsCursorBlock'.tr()),
                              ),
                              DropdownMenuItem(
                                value: maidterm.CursorShape.bar,
                                child: Text('settingsCursorBar'.tr()),
                              ),
                              DropdownMenuItem(
                                value: maidterm.CursorShape.underline,
                                child: Text('settingsCursorUnderline'.tr()),
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
                          title: Text('settingsTransparentBackground'.tr()),
                          subtitle: Text(
                            'settingsTransparentBackgroundDescription'.tr(),
                          ),
                          value: data.transparentBackground,
                          onChanged: (v) => ref
                              .read(terminalSettingsProvider.notifier)
                              .setTransparentBackground(v),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(child: Text('settingsWindowTransparency'.tr())),
                                Text(
                                  '${(data.windowTransparency * 100).round()}%',
                                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                    fontFamily: 'IBM Plex Mono',
                                  ),
                                ),
                              ],
                            ),
                            Slider(
                              padding: EdgeInsets.zero,
                              value: data.windowTransparency,
                              min: 0,
                              max: 1,
                              divisions: 100,
                              label: '${(data.windowTransparency * 100).round()}%',
                              onChanged: (v) => ref
                                  .read(terminalSettingsProvider.notifier)
                                  .setWindowTransparency(v),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(child: Text('settingsPaneBackgroundOpacity'.tr())),
                                Text(
                                  '${(data.paneBackgroundOpacity * 100).round()}%',
                                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                    fontFamily: 'IBM Plex Mono',
                                  ),
                                ),
                              ],
                            ),
                            Slider(
                              padding: EdgeInsets.zero,
                              value: data.paneBackgroundOpacity,
                              min: 0,
                              max: 1,
                              divisions: 100,
                              label: '${(data.paneBackgroundOpacity * 100).round()}%',
                              onChanged: (v) => ref
                                  .read(terminalSettingsProvider.notifier)
                                  .setPaneBackgroundOpacity(v),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  _SettingsSection(
                    title: 'settingsTabBar'.tr(),
                    description: 'settingsTabBarDescription'.tr(),
                    child: _TabBarPositionPicker(settings: data),
                  ),
                  _SettingsSection(
                    title: 'settingsStatusBar'.tr(),
                    description: 'settingsStatusBarDescription'.tr(),
                    child: _StatusBarSettings(settings: data),
                  ),
                  _SettingsSection(
                    title: 'settingsTitleBar'.tr(),
                    description: 'settingsTitleBarDescription'.tr(),
                    child: SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('settingsShowMenuButton'.tr()),
                      subtitle: Text('settingsShowMenuButtonDescription'.tr()),
                      value: data.showTitleBarMenuButton,
                      onChanged: (v) => ref
                          .read(terminalSettingsProvider.notifier)
                          .setShowTitleBarMenuButton(v),
                    ),
                  ),
                  _SettingsSection(
                    title: 'settingsPaneMargins'.tr(),
                    description: 'settingsPaneMarginsDescription'.tr(),
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
                    title: 'settingsTerminalThemes'.tr(),
                    description: 'settingsTerminalThemesDescription'.tr(),
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
                    title: 'settingsShell'.tr(),
                    description: 'settingsShellDescription'.tr(),
                    child: TextField(
                      controller: TextEditingController(
                        text: data.shellPath ?? '',
                      ),
                      decoration: InputDecoration(
                        labelText: 'settingsShellPath'.tr(),
                        hintText: 'settingsShellDefaultHint'.tr(),
                        border: const OutlineInputBorder(),
                      ),
                      onSubmitted: (v) => ref
                          .read(terminalSettingsProvider.notifier)
                          .setShellPath(v.trim()),
                    ),
                  ),
                  _SettingsSection(
                    title: 'settingsAbout'.tr(),
                    description: 'settingsAboutDescription'.tr(),
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Symbols.info),
                      title: Text('settingsAboutTile'.tr()),
                      trailing: const Icon(Symbols.chevron_right),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          settings: const RouteSettings(name: '/about'),
                          builder: (_) => const AboutPage(),
                        ),
                      ),
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
            'settingsTerminalPreferences'.tr(),
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
      segments: [
        ButtonSegment(
          value: TabBarPosition.top,
          label: Text('settingsTabBarTop'.tr()),
        ),
        ButtonSegment(
          value: TabBarPosition.bottom,
          label: Text('settingsTabBarBottom'.tr()),
        ),
        ButtonSegment(
          value: TabBarPosition.left,
          label: Text('settingsTabBarLeft'.tr()),
        ),
        ButtonSegment(
          value: TabBarPosition.right,
          label: Text('settingsTabBarRight'.tr()),
        ),
      ],
      selected: {settings.tabBarPosition},
      onSelectionChanged: (selection) => ref
          .read(terminalSettingsProvider.notifier)
          .setTabBarPosition(selection.first),
    );
  }
}

class _StatusBarSettings extends ConsumerWidget {
  const _StatusBarSettings({required this.settings});

  final TerminalSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(terminalSettingsProvider.notifier);
    final orderedMetrics = [...settings.statusBarMetrics];
    final selected = orderedMetrics.toSet();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('settingsStatusBarEnabled'.tr()),
          subtitle: Text('settingsStatusBarEnabledDescription'.tr()),
          value: settings.showStatusBar,
          onChanged: notifier.setShowStatusBar,
        ),
        const SizedBox(height: 8),
        Text(
          'settingsStatusBarSignals'.tr(),
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final metric in StatusMetric.values)
              FilterChip(
                label: Text(_statusMetricLabel(metric)),
                selected: selected.contains(metric),
                onSelected: (value) {
                  final next = [...orderedMetrics];
                  if (value) {
                    if (!next.contains(metric)) next.add(metric);
                  } else {
                    next.remove(metric);
                  }
                  notifier.setStatusBarMetrics(next);
                },
              ),
          ],
        ),
        if (orderedMetrics.length > 1) ...[
          const SizedBox(height: 10),
          Text(
            'settingsStatusBarOrder'.tr(),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: orderedMetrics.length,
            onReorderItem: (oldIndex, newIndex) {
              final next = [...orderedMetrics];
              final metric = next.removeAt(oldIndex);
              next.insert(newIndex, metric);
              notifier.setStatusBarMetrics(next);
            },
            itemBuilder: (context, index) {
              final metric = orderedMetrics[index];
              return ListTile(
                key: ValueKey(metric),
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: ReorderableDragStartListener(
                  index: index,
                  child: const Icon(Icons.drag_handle),
                ),
                title: Text(_statusMetricLabel(metric)),
              );
            },
          ),
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: Text('settingsStatusBarRefresh'.tr())),
            Text(
              '${settings.statusBarRefreshSeconds}s',
              style: Theme.of(context).textTheme.labelLarge
                  ?.copyWith(fontFamily: 'IBM Plex Mono'),
            ),
          ],
        ),
        Slider(
          padding: EdgeInsets.zero,
          value: settings.statusBarRefreshSeconds.toDouble(),
          min: 1,
          max: 10,
          divisions: 9,
          label: '${settings.statusBarRefreshSeconds}s',
          onChanged: (value) =>
              notifier.setStatusBarRefreshSeconds(value.round()),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: Text('settingsStatusBarHistory'.tr())),
            Text(
              '${settings.statusBarHistoryMinutes}m',
              style: Theme.of(context).textTheme.labelLarge
                  ?.copyWith(fontFamily: 'IBM Plex Mono'),
            ),
          ],
        ),
        Slider(
          padding: EdgeInsets.zero,
          value: settings.statusBarHistoryMinutes.toDouble(),
          min: 1,
          max: 30,
          divisions: 29,
          label: '${settings.statusBarHistoryMinutes}m',
          onChanged: (value) =>
              notifier.setStatusBarHistoryMinutes(value.round()),
        ),
      ],
    );
  }
}

String _statusMetricLabel(StatusMetric metric) => switch (metric) {
  StatusMetric.cpu => 'settingsStatusBarCpu'.tr(),
  StatusMetric.memory => 'settingsStatusBarMemory'.tr(),
  StatusMetric.network => 'settingsStatusBarNetwork'.tr(),
  StatusMetric.battery => 'settingsStatusBarBattery'.tr(),
};

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
            title: Text('settingsBackgroundShow'.tr()),
            value: enabled,
            onChanged: (value) => setMaidTermBackgroundImageEnabled(ref, value),
          ),
        ] else
          Text(
            'settingsBackgroundNoImage'.tr(),
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
              label: Text('settingsBackgroundChoose'.tr()),
            ),
            if (image != null)
              TextButton.icon(
                onPressed: () => clearMaidTermBackgroundImage(ref),
                icon: const Icon(Symbols.delete_outline),
                label: Text('settingsBackgroundClear'.tr()),
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
      dialogTitle: 'settingsBackgroundChooseDialog'.tr(),
      type: FileType.image,
    );
    if (selection == null || selection.files.isEmpty) return;
    final path = selection.files.first.path;
    if (path == null) return;

    try {
      await saveMaidTermBackgroundImage(ref, File(path));
    } on Object catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('settingsBackgroundSaveError'.tr(args: ['$error'])),
        ),
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
          title: 'settingsPaneNormalMode'.tr(),
          margin: normalMargin,
          onChanged: onNormalChanged,
        ),
        const SizedBox(height: 20),
        _PaneMarginEditor(
          key: const ValueKey('fullscreen-pane-margin'),
          title: 'settingsPaneFullScreenMode'.tr(),
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
                    labelText: _labels[i].tr(),
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
      segments: [
        ButtonSegment(
          value: ThemeMode.system,
          label: Text('settingsThemeModeSystem'.tr()),
        ),
        ButtonSegment(
          value: ThemeMode.light,
          label: Text('settingsThemeModeLight'.tr()),
        ),
        ButtonSegment(
          value: ThemeMode.dark,
          label: Text('settingsThemeModeDark'.tr()),
        ),
      ],
      selected: {settings.themeMode},
      onSelectionChanged: (selection) => ref
          .read(terminalSettingsProvider.notifier)
          .setThemeMode(selection.first),
    );
  }
}

/// Accent color picker: preset swatches plus manual hex entry and a full
/// color editor, modeled after MaidKit's settings page.
class _SeedColorPicker extends ConsumerStatefulWidget {
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
  ConsumerState<_SeedColorPicker> createState() => _SeedColorPickerState();
}

class _SeedColorPickerState extends ConsumerState<_SeedColorPicker> {
  late final TextEditingController _hexController;
  String? _hexError;

  @override
  void initState() {
    super.initState();
    _hexController = TextEditingController(
      text: _hexFor(widget.settings.seedColor),
    );
  }

  @override
  void didUpdateWidget(_SeedColorPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings.seedColor != widget.settings.seedColor) {
      _hexController.text = _hexFor(widget.settings.seedColor);
    }
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  void _applyHex(String value) {
    final color = _colorFromHex(value);
    if (color == null) {
      setState(() => _hexError = 'settingsHexError'.tr());
      return;
    }
    setState(() => _hexError = null);
    ref.read(terminalSettingsProvider.notifier).setSeedColor(color);
  }

  Future<void> _editColor() async {
    final updated = await showDialog<Color>(
      context: context,
      builder: (context) => _ColorEditDialog(
        title: 'settingsColorDialogTitle'.tr(),
        initialColor: widget.settings.seedColor,
      ),
    );
    if (updated != null) {
      ref.read(terminalSettingsProvider.notifier).setSeedColor(updated);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('settingsAccentColor'.tr()),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final color in _SeedColorPicker._presets)
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
                      color: widget.settings.seedColor == color
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.outlineVariant,
                      width: widget.settings.seedColor == color ? 3 : 1,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: widget.settings.seedColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                key: const ValueKey('accent-color-hex'),
                controller: _hexController,
                maxLength: 7,
                onSubmitted: _applyHex,
                decoration: InputDecoration(
                  labelText: 'settingsThemeColor'.tr(),
                  hintText: '#0F766E',
                  errorText: _hexError,
                  counterText: '',
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              key: const ValueKey('accent-color-edit'),
              tooltip: 'settingsEditTheme'.tr(),
              onPressed: _editColor,
              icon: const Icon(Symbols.edit),
            ),
          ],
        ),
      ],
    );
  }
}

/// Hex + RGB channel editor for a single color, modeled after MaidKit's
/// color dialog.
class _ColorEditDialog extends StatefulWidget {
  const _ColorEditDialog({required this.title, required this.initialColor});

  final String title;
  final Color initialColor;

  @override
  State<_ColorEditDialog> createState() => _ColorEditDialogState();
}

class _ColorEditDialogState extends State<_ColorEditDialog> {
  late final TextEditingController _hexController;
  late int _red;
  late int _green;
  late int _blue;
  String? _colorError;

  @override
  void initState() {
    super.initState();
    final color = widget.initialColor;
    _red = color.r.toInt();
    _green = color.g.toInt();
    _blue = color.b.toInt();
    _hexController = TextEditingController(text: _hexFor(_color));
  }

  Color get _color => Color.fromARGB(255, _red, _green, _blue);

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  void _updateFromHex(String value) {
    final color = _colorFromHex(value);
    setState(() {
      _colorError = color == null ? 'settingsHexError'.tr() : null;
      if (color != null) {
        _red = color.r.toInt();
        _green = color.g.toInt();
        _blue = color.b.toInt();
      }
    });
  }

  void _updateColor(void Function() update) {
    setState(() {
      update();
      _colorError = null;
      _hexController.text = _hexFor(_color);
    });
  }

  void _save() {
    final color = _colorFromHex(_hexController.text);
    if (color == null) {
      setState(() => _colorError = 'settingsHexError'.tr());
      return;
    }
    Navigator.of(context).pop(color);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: _color,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _hexController,
                      maxLength: 7,
                      onChanged: _updateFromHex,
                      decoration: InputDecoration(
                        labelText: 'settingsThemeColor'.tr(),
                        hintText: '#0F766E',
                        errorText: _colorError,
                        counterText: '',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'settingsColorDialogHelp'.tr(),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              _ColorChannelSlider(
                label: 'R',
                value: _red,
                onChanged: (value) => _updateColor(() => _red = value),
              ),
              _ColorChannelSlider(
                label: 'G',
                value: _green,
                onChanged: (value) => _updateColor(() => _green = value),
              ),
              _ColorChannelSlider(
                label: 'B',
                value: _blue,
                onChanged: (value) => _updateColor(() => _blue = value),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('commonCancel'.tr()),
        ),
        FilledButton(onPressed: _save, child: Text('commonSave'.tr())),
      ],
    );
  }
}

class _ColorChannelSlider extends StatelessWidget {
  const _ColorChannelSlider({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 20, child: Text(label)),
        Expanded(
          child: Slider(
            padding: EdgeInsets.zero,
            value: value.toDouble(),
            min: 0,
            max: 255,
            divisions: 255,
            label: '$value',
            onChanged: (value) => onChanged(value.round()),
          ),
        ),
        SizedBox(width: 28, child: Text('$value')),
      ],
    );
  }
}

String _hexFor(Color color) =>
    '#${color.r.toInt().toRadixString(16).padLeft(2, '0').toUpperCase()}${color.g.toInt().toRadixString(16).padLeft(2, '0').toUpperCase()}${color.b.toInt().toRadixString(16).padLeft(2, '0').toUpperCase()}';

Color? _colorFromHex(String value) {
  final hex = value.trim().replaceFirst('#', '');
  if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(hex)) return null;
  return Color(int.parse('FF$hex', radix: 16));
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
      decoration: InputDecoration(
        labelText: 'settingsFontFamily'.tr(),
        border: const OutlineInputBorder(),
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
          decoration: InputDecoration(
            labelText: 'settingsFontCustomFamily'.tr(),
            hintText: 'settingsFontCustomFamilyHint'.tr(),
            border: const OutlineInputBorder(),
          ),
          onSubmitted: setFontFamily,
        ),
        const SizedBox(height: 4),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('settingsFontMonospaceOnly'.tr()),
          subtitle: Text('settingsFontMonospaceOnlyDescription'.tr()),
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
      decoration: InputDecoration(
        labelText: 'settingsFontSize'.tr(),
        border: const OutlineInputBorder(),
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
      title: Text(
        mode == Brightness.light
            ? 'settingsThemeLight'.tr()
            : 'settingsThemeDark'.tr(),
      ),
      subtitle: Text('settingsThemeEditHint'.tr(args: [theme.label])),
      trailing: const Icon(Symbols.edit),
      onTap: onEdit,
    );
  }
}
