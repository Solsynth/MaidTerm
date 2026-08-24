import 'package:material_ui/material_ui.dart';
import 'package:easy_localization/easy_localization.dart';

import 'terminal_color_scheme.dart';

/// Small live preview of a palette: "Aa" sample plus the 16-color grid.
class TerminalPalettePreview extends StatelessWidget {
  const TerminalPalettePreview({
    super.key,
    required this.theme,
    this.large = false,
  });

  final TerminalColorScheme theme;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: large ? 120 : 64,
      height: large ? 88 : 48,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: theme.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Aa',
            style: TextStyle(
              color: theme.foreground,
              fontSize: large ? 16 : 11,
              height: 1,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: GridView.count(
              crossAxisCount: 8,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              mainAxisSpacing: 1,
              crossAxisSpacing: 1,
              children: [
                for (final color in theme.ansiColors)
                  Container(
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(1.5),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Opens the theme editor for [initialScheme]; returns the edited scheme, or
/// null when cancelled.
Future<TerminalColorScheme?> showTerminalThemeEditor(
  BuildContext context, {
  required Brightness brightness,
  required TerminalColorScheme initialScheme,
}) {
  return showDialog<TerminalColorScheme>(
    context: context,
    builder: (context) => _TerminalThemeDialog(
      brightness: brightness,
      initialScheme: initialScheme,
    ),
  );
}

class _TerminalThemeDialog extends StatefulWidget {
  const _TerminalThemeDialog({
    required this.brightness,
    required this.initialScheme,
  });

  final Brightness brightness;
  final TerminalColorScheme initialScheme;

  @override
  State<_TerminalThemeDialog> createState() => _TerminalThemeDialogState();
}

class _TerminalThemeDialogState extends State<_TerminalThemeDialog> {
  static const _ansiBaseLabels = [
    'Black',
    'Red',
    'Green',
    'Yellow',
    'Blue',
    'Magenta',
    'Cyan',
    'White',
  ];

  late TerminalColorScheme _scheme;
  bool _edited = false;

  @override
  void initState() {
    super.initState();
    _scheme = widget.initialScheme;
  }

  Future<void> _editColor(
    String label,
    Color current,
    ValueChanged<Color> apply,
  ) async {
    final updated = await showDialog<Color>(
      context: context,
      builder: (context) =>
          _ColorEditDialog(title: label, initialColor: current),
    );
    if (updated != null) {
      setState(() {
        apply(updated);
        // Edited variants become custom schemes so presets stay intact.
        if (_scheme.id != 'custom') {
          _scheme = _scheme.copyWith(id: 'custom', label: 'commonCustom'.tr());
        }
        _edited = true;
      });
    }
  }

  void _setAnsi(int index, Color color) {
    final ansi = List<Color>.of(_scheme.ansiColors);
    ansi[index] = color;
    setState(() => _scheme = _scheme.copyWith(ansiColors: ansi));
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.brightness == Brightness.light
        ? 'themeEditorLightTheme'.tr()
        : 'themeEditorDarkTheme'.tr();
    final isCustom = !TerminalColorSchemes.all.any(
      (scheme) => scheme.id == _scheme.id,
    );

    return AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<String>(
                initialValue: isCustom ? 'custom' : _scheme.id,
                decoration: InputDecoration(labelText: 'themeEditorPreset'.tr()),
                items: [
                  for (final scheme in TerminalColorSchemes.all)
                    DropdownMenuItem(
                      value: scheme.id,
                      child: Text(scheme.label),
                    ),
                  DropdownMenuItem(
                    value: 'custom',
                    child: Text('commonCustom'.tr()),
                  ),
                ],
                onChanged: (id) {
                  if (id == null || id == 'custom') return;
                  setState(() => _scheme = TerminalColorSchemes.byId(id));
                },
              ),
              const SizedBox(height: 16),
              Center(
                child: TerminalPalettePreview(theme: _scheme, large: true),
              ),
              const SizedBox(height: 16),
              _TerminalColorRow(
                label: 'themeEditorBackground'.tr(),
                color: _scheme.background,
                onTap: () => _editColor(
                  'themeEditorBackground'.tr(),
                  _scheme.background,
                  (color) => _scheme = _scheme.copyWith(background: color),
                ),
              ),
              _TerminalColorRow(
                label: 'themeEditorForeground'.tr(),
                color: _scheme.foreground,
                onTap: () => _editColor(
                  'themeEditorForeground'.tr(),
                  _scheme.foreground,
                  (color) => _scheme = _scheme.copyWith(foreground: color),
                ),
              ),
              _TerminalColorRow(
                label: 'themeEditorCursor'.tr(),
                color: _scheme.cursor,
                onTap: () => _editColor(
                  'themeEditorCursor'.tr(),
                  _scheme.cursor,
                  (color) => _scheme = _scheme.copyWith(cursor: color),
                ),
              ),
              _TerminalColorRow(
                label: 'themeEditorSelection'.tr(),
                color: _scheme.selection,
                onTap: () => _editColor(
                  'themeEditorSelection'.tr(),
                  _scheme.selection,
                  (color) => _scheme = _scheme.copyWith(selection: color),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'themeEditorNormalColors'.tr(),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              for (var i = 0; i < 8; i++)
                _TerminalColorRow(
                  label: _ansiBaseLabels[i].tr(),
                  color: _scheme.ansiColors[i],
                  onTap: () => _editColor(
                    _ansiBaseLabels[i].tr(),
                    _scheme.ansiColors[i],
                    (color) => setState(() => _setAnsi(i, color)),
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                'themeEditorBrightColors'.tr(),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              for (var i = 0; i < 8; i++)
                _TerminalColorRow(
                  label: 'themeEditorBrightColor'.tr(
                    args: [_ansiBaseLabels[i].tr()],
                  ),
                  color: _scheme.ansiColors[i + 8],
                  onTap: () => _editColor(
                    'themeEditorBrightColor'.tr(
                      args: [_ansiBaseLabels[i].tr()],
                    ),
                    _scheme.ansiColors[i + 8],
                    (color) => setState(() => _setAnsi(i + 8, color)),
                  ),
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
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_scheme),
          child: Text(_edited ? 'commonSave'.tr() : 'themeEditorDone'.tr()),
        ),
      ],
    );
  }
}

class _TerminalColorRow extends StatelessWidget {
  const _TerminalColorRow({
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      ),
      title: Text(label),
      trailing: Text(
        hexFor(color),
        style: Theme.of(context).textTheme.bodySmall,
      ),
      onTap: onTap,
    );
  }
}

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
    _red = (color.r * 255).round();
    _green = (color.g * 255).round();
    _blue = (color.b * 255).round();
    _hexController = TextEditingController(text: hexFor(color));
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  Color get _color => Color.fromARGB(255, _red, _green, _blue);

  void _updateFromHex(String value) {
    final color = colorFromHex(value);
    setState(() {
      _colorError = color == null ? 'themeEditorInvalidHex'.tr() : null;
      if (color != null) {
        _red = (color.r * 255).round();
        _green = (color.g * 255).round();
        _blue = (color.b * 255).round();
      }
    });
  }

  void _updateColor(void Function() update) {
    setState(() {
      update();
      _colorError = null;
      _hexController.text = hexFor(_color);
    });
  }

  void _save() {
    final color = colorFromHex(_hexController.text);
    if (color == null) {
      setState(() => _colorError = 'themeEditorInvalidHex'.tr());
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
                        labelText: 'themeEditorColor'.tr(),
                        hintText: '#0F766E',
                        errorText: _colorError,
                        counterText: '',
                      ),
                      buildCounter:
                          (
                            context, {
                            required currentLength,
                            required isFocused,
                            maxLength,
                          }) => null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _ColorChannelSlider(
                label: 'R',
                value: _red,
                activeColor: Colors.red,
                onChanged: (value) => _updateColor(() => _red = value),
              ),
              _ColorChannelSlider(
                label: 'G',
                value: _green,
                activeColor: Colors.green,
                onChanged: (value) => _updateColor(() => _green = value),
              ),
              _ColorChannelSlider(
                label: 'B',
                value: _blue,
                activeColor: Colors.blue,
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
    this.activeColor,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;
  final Color? activeColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 20, child: Text(label)),
        Expanded(
          child: Slider(
            value: value.toDouble(),
            min: 0,
            max: 255,
            divisions: 255,
            label: '$value',
            activeColor: activeColor,
            onChanged: (value) => onChanged(value.round()),
          ),
        ),
        SizedBox(width: 28, child: Text('$value')),
      ],
    );
  }
}

/// `#RRGGBB`, uppercase.
String hexFor(Color color) =>
    '#${(color.r * 255).round().toRadixString(16).padLeft(2, '0').toUpperCase()}'
    '${(color.g * 255).round().toRadixString(16).padLeft(2, '0').toUpperCase()}'
    '${(color.b * 255).round().toRadixString(16).padLeft(2, '0').toUpperCase()}';

/// Parses `#RRGGBB` or `RRGGBB`; returns null when malformed.
Color? colorFromHex(String value) {
  final hex = value.trim().replaceFirst('#', '');
  if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(hex)) return null;
  return Color(int.parse('FF$hex', radix: 16));
}
