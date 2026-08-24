import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:solsynth_express/solsynth_express.dart';
import 'package:url_launcher/url_launcher.dart';

/// The installed app's version metadata, resolved from the platform once.
final packageInfoProvider = FutureProvider<PackageInfo>((ref) {
  return PackageInfo.fromPlatform();
});

const _mono = 'IBM Plex Mono';

/// The coral wrapping the app icon: the one brand colour that is not the
/// Material seed. Used for the prompt accent so the hero's prompt line echoes
/// the mascot logo's colour.
const _brandCoral = Color(0xFFF2A39D);
const _brandCoralDeep = Color(0xFFC65047);

/// Solsynth Express distribution endpoint and MaidTerm's product id. The
/// product id can be overridden at build time with --dart-define.
const kMaidTermDistributionApiBaseUrl = String.fromEnvironment(
  'DISTRIBUTION_API_BASE_URL',
  defaultValue: 'https://api.solian.app/dist',
);
const kMaidTermDistributionProductId = String.fromEnvironment(
  'DISTRIBUTION_PRODUCT_ID',
  defaultValue: 'dd7632e5-80b2-4e56-8248-edc0240e0fe3',
);

/// The glyph face reads on both light and dark cards: soft coral for dark
/// themes, a deeper text-safe salmon for light themes.
Color _faceColor(ThemeData theme) =>
    theme.brightness == Brightness.dark ? _brandCoral : _brandCoralDeep;

/// MaidTerm's identity, told the way the app speaks — as a terminal session.
///
/// The hero is a terminal window whose centre is the mascot's glyph face
/// (`> _ <`), the same marks that make up the app icon. Everything after it
/// is quiet reading material: real version data, the engine it is built on,
/// and the open-source licences.
class AboutPage extends ConsumerWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final packageInfo = ref.watch(packageInfoProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('About'),
        elevation: 0,
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 660),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
            children: [
              const _TerminalHero(),
              const SizedBox(height: 28),
              ...packageInfo.when(
                loading: () => const [
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: 48),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ],
                error: (error, _) => [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Text(
                      'Could not load app details: $error',
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                    ),
                  ),
                ],
                data: (info) => _infoSections(context, info),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _infoSections(BuildContext context, PackageInfo info) {
    final theme = Theme.of(context);
    return [
      const _SectionTitle('App info'),
      const SizedBox(height: 8),
      Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Symbols.info),
              title: const Text('Version'),
              subtitle: Text(info.version, style: _monoStyle(theme)),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Symbols.build),
              title: const Text('Build'),
              subtitle: Text(info.buildNumber, style: _monoStyle(theme)),
            ),
            if (info.packageName.isNotEmpty) ...[
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Symbols.inventory_2),
                title: const Text('Package'),
                subtitle: SelectableText(
                  info.packageName,
                  style: _monoStyle(theme),
                ),
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 24),
      const _SectionTitle('Related products'),
      const SizedBox(height: 8),
      Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            _ProductLinkTile(
              icon: Symbols.dns,
              title: 'MaidKit',
              subtitle:
                  'A cross-platform SSH server manager — maintain servers '
                  'without installing anything on them.',
              url: 'https://solsynth.dev/products/maid-kit',
            ),
            const Divider(height: 1),
            _ProductLinkTile(
              icon: Symbols.public,
              title: 'Solar Network',
              subtitle:
                  'A social network for technology, programming, and ACG fans.',
              url: 'https://solsynth.dev/products/solar-network',
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      const _SectionTitle('Updates'),
      const SizedBox(height: 8),
      Card(
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          leading: const Icon(Symbols.system_update),
          title: const Text('Check for updates'),
          subtitle: const Text('Look for a newer release on Solsynth Express.'),
          trailing: const Icon(Symbols.chevron_right),
          onTap: () {
            UpdateService(
              apiBaseUrl: kMaidTermDistributionApiBaseUrl,
              productId: kMaidTermDistributionProductId,
              channel: 'stable',
              enabled: true,
            ).checkForUpdates(context);
          },
        ),
      ),
      const SizedBox(height: 24),
      const _SectionTitle('Licenses'),
      const SizedBox(height: 8),
      Card(
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          leading: const Icon(Symbols.description),
          title: const Text('Open-source licenses'),
          subtitle: const Text(
            'The packages, engine, and fonts that power MaidTerm.',
          ),
          trailing: const Icon(Symbols.chevron_right),
          onTap: () => showLicensePage(
            context: context,
            applicationName: 'MaidTerm',
            applicationVersion: info.version,
            applicationIcon: Padding(
              padding: const EdgeInsets.all(8),
              child: Image.asset(
                'assets/icons/icon.png',
                width: 48,
                height: 48,
                errorBuilder: (_, _, _) =>
                    const Icon(Symbols.dns, size: 48),
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: 36),
      Center(
        child: Text(
          '© ${DateTime.now().year} Solsynth',
          style: _footerStyle(theme),
        ),
      ),
    ];
  }
}

/// A card styled as a slim terminal window: a title bar with window dots and
/// the mascot glyph face plus a prompt line in its body.
class _TerminalHero extends StatelessWidget {
  const _TerminalHero();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final face = _faceColor(theme);

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        children: [
          const _TerminalTitleBar(),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _LogoBadge(),
                const SizedBox(height: 22),
                Text(
                  'MaidTerm',
                  style: TextStyle(
                    fontFamily: _mono,
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 10),
                _PromptLine(
                  color: face,
                  text: 'local-first terminal for macOS, Windows, and Linux',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TerminalTitleBar extends StatelessWidget {
  const _TerminalTitleBar();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      color: scheme.surfaceContainerHighest,
      child: Row(
        children: const [
          _WindowDot(color: Color(0xFFE5665C)),
          SizedBox(width: 8),
          _WindowDot(color: Color(0xFFE8B84C)),
          SizedBox(width: 8),
          _WindowDot(color: Color(0xFF8FCB68)),
          SizedBox(width: 12),
          Text(
            'maidterm',
            style: TextStyle(
              fontFamily: _mono,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _WindowDot extends StatelessWidget {
  const _WindowDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

/// The app icon, shown as a rounded badge. The mascot's face is already part
/// of the artwork, so the About page uses the real mark rather than redrawing
/// the glyphs by hand.
class _LogoBadge extends StatelessWidget {
  const _LogoBadge();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Image.asset(
        'assets/icons/icon.png',
        width: 96,
        height: 96,
        errorBuilder: (_, _, _) => Container(
          width: 96,
          height: 96,
          alignment: Alignment.center,
          color: scheme.surfaceContainerHighest,
          child: Icon(Symbols.dns, size: 48, color: scheme.primary),
        ),
      ),
    );
  }
}

/// A single monospace prompt line: a coral `>` then muted text, echoing a
/// terminal that is ready for the next command.
class _PromptLine extends StatelessWidget {
  const _PromptLine({required this.color, required this.text});

  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Text.rich(
      TextSpan(
        style: TextStyle(
          fontFamily: _mono,
          fontSize: 13,
          height: 1.5,
          color: scheme.onSurfaceVariant,
        ),
        children: [
          TextSpan(
            text: '> ',
            style: TextStyle(color: color, fontWeight: FontWeight.w600),
          ),
          TextSpan(text: text),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    );
  }
}

/// Opens [url] in the default browser.
Future<void> _openUrl(String url) async {
  final uri = Uri.parse(url);
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

/// A linked row to a related Solsynth product.
class _ProductLinkTile extends StatelessWidget {
  const _ProductLinkTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.url,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String url;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: scheme.primary, size: 24),
      ),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Symbols.open_in_new),
      onTap: () => _openUrl(url),
    );
  }
}

TextStyle _monoStyle(ThemeData theme) => TextStyle(
  fontFamily: _mono,
  fontSize: 14,
  color: theme.colorScheme.onSurfaceVariant,
);

TextStyle _footerStyle(ThemeData theme) => TextStyle(
  fontFamily: _mono,
  fontSize: 12,
  color: theme.colorScheme.onSurfaceVariant,
);
