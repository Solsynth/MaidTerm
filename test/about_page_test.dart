import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart' hide GlobalMaterialLocalizations;
import 'package:material_ui/material_ui.dart'
    as material_ui
    show GlobalMaterialLocalizations;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:maidterm_app/settings/about_page.dart';

void main() {
  final info = PackageInfo(
    appName: 'MaidTerm',
    packageName: 'com.solsynth.maidterm',
    version: '0.1.0',
    buildNumber: '1',
  );

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    EasyLocalization.logger.enableBuildModes = [];
  });

  Widget buildApp() => EasyLocalization(
    supportedLocales: const [Locale('en', 'US')],
    path: 'assets/translations',
    fallbackLocale: const Locale('en', 'US'),
    useFallbackTranslations: true,
    child: ProviderScope(
      overrides: [packageInfoProvider.overrideWith((ref) async => info)],
      child: MaterialApp(
        localizationsDelegates: [
          ...material_ui.GlobalMaterialLocalizations.delegates,
          GlobalMaterialLocalizations.delegate,
        ],
        home: const AboutPage(),
      ),
    ),
  );

  testWidgets('renders the app identity and version data', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(find.text('aboutTitle'.tr()), findsOneWidget);
    expect(find.text('MaidTerm'), findsWidgets);
    expect(find.text('0.1.0'), findsOneWidget);
    expect(find.text('aboutVersion'.tr()), findsOneWidget);
    expect(find.text('aboutBuild'.tr()), findsOneWidget);
    expect(find.text('aboutPackage'.tr()), findsOneWidget);
    expect(find.text('aboutAppInfo'.tr()), findsOneWidget);

    final scrollable = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.text('aboutRelatedProducts'.tr()),
      200,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();
    expect(find.text('aboutRelatedProducts'.tr()), findsOneWidget);
    expect(find.text('MaidKit'), findsOneWidget);
    expect(find.text('Solar Network'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('aboutCheckForUpdates'.tr()),
      200,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();
    expect(find.text('aboutCheckForUpdates'.tr()), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('aboutLicenses'.tr()),
      200,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();
    expect(find.text('aboutLicenses'.tr()), findsOneWidget);
  });

  testWidgets('license tile opens the license page', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('aboutOpenSourceLicenses'.tr()),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('aboutOpenSourceLicenses'.tr()));
    await tester.pumpAndSettle();

    // The LicensePage AppBar shows the material-en-US title 'Licenses'.
    expect(find.text('Licenses'), findsWidgets);
  });
}
