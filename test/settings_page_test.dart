import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart' hide GlobalMaterialLocalizations;
import 'package:material_ui/material_ui.dart'
    as material_ui
    show GlobalMaterialLocalizations;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'dart:convert';
import 'dart:io';

import 'package:maidterm_app/settings/about_page.dart';
import 'package:maidterm_app/settings/settings_page.dart';
import 'package:maidterm_app/settings/terminal_fonts.dart';
import 'package:maidterm_app/settings/terminal_settings.dart';

/// Loads the real translation JSON files synchronously from disk.
///
/// easy_localization's default [RootBundleAssetLoader] goes through the
/// platform messenger, which does not progress in the fake-async zone of a
/// widget test once a previous test's EasyLocalization tree has been torn
/// down. Reading the files directly keeps the tests hermetic and real.
class _TestAssetLoader extends AssetLoader {
  final String basePath;
  const _TestAssetLoader(this.basePath);

  @override
  Future<Map<String, dynamic>?> load(String path, Locale locale) async {
    final file = File(
      '$basePath/${locale.toStringWithSeparator(separator: '-')}.json',
    );
    if (!file.existsSync()) return null;
    return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  }
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    EasyLocalization.logger.enableBuildModes = [];
  });

  Widget buildSettings(Widget child) => EasyLocalization(
    supportedLocales: const [
      Locale('en', 'US'),
      Locale('zh', 'CN'),
      Locale('zh', 'TW'),
    ],
    path: 'assets/translations',
    fallbackLocale: const Locale('en', 'US'),
    useFallbackTranslations: true,
    assetLoader: const _TestAssetLoader('assets/translations'),
    child: ProviderScope(
      child: Builder(
        builder: (context) => MaterialApp(
          localizationsDelegates: [
            ...context.localizationDelegates,
            ...material_ui.GlobalMaterialLocalizations.delegates,
          ],
          locale: context.locale,
          supportedLocales: context.supportedLocales,
          home: child,
        ),
      ),
    ),
  );

  testWidgets('settings page renders current values and persists changes', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'terminal.fontFamily': 'Fira Code',
      'terminal.fontSize': 16.0,
      'terminal.cursorBlink': false,
      'terminal.cursorStyle': 'bar',
    });

    await tester.pumpWidget(buildSettings(const SettingsPage()));
    await tester.pumpAndSettle();

    expect(find.text('settingsTitle'.tr()), findsOneWidget);
    expect(find.text('settingsBackgroundImage'.tr()), findsOneWidget);
    expect(find.text('settingsBackgroundChoose'.tr()), findsOneWidget);
    expect(find.text('settingsBackgroundNoImage'.tr()), findsOneWidget);

    // Values loaded from prefs.
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SettingsPage)),
    );
    expect(container.read(terminalSettingsProvider).value?.fontSize, 16.0);
    expect(container.read(terminalFontFamilyProvider), 'Fira Code');

    // Toggle blink persists.
    await tester.scrollUntilVisible(
      find.text('settingsCursorBlink'.tr()),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('settingsCursorBlink'.tr()));
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('terminal.cursorBlink'), isTrue);
  });

  testWidgets('tab bar position control persists selection', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(buildSettings(const SettingsPage()));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('settingsTabBar'.tr()),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('settingsTabBarLeft'.tr()).first);
    await tester.pumpAndSettle();

    final settings = ProviderScope.containerOf(
      tester.element(find.byType(SettingsPage)),
    ).read(terminalSettingsProvider).value!;
    expect(settings.tabBarPosition, TabBarPosition.left);
    expect(
      (await SharedPreferences.getInstance()).getString(
        'terminal.tabBarPosition',
      ),
      'left',
    );
  });
  testWidgets('status bar preferences persist selected signals', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'terminal.showStatusBar': true});

    await tester.pumpWidget(buildSettings(const SettingsPage()));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('settingsStatusBar'.tr()),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('settingsStatusBarEnabled'.tr()));
    await tester.tap(find.text('settingsStatusBarBattery'.tr()));
    await tester.pumpAndSettle();

    final settings = ProviderScope.containerOf(
      tester.element(find.byType(SettingsPage)),
    ).read(terminalSettingsProvider).value!;
    expect(settings.showStatusBar, isFalse);
    expect(settings.statusBarMetrics, contains(StatusMetric.battery));
    expect(
      (await SharedPreferences.getInstance()).getBool('terminal.showStatusBar'),
      isFalse,
    );
    expect(
      (await SharedPreferences.getInstance()).getString(
        'terminal.statusBarMetrics',
      ),
      contains('battery'),
    );
  });

  testWidgets('edits and persists both pane margin modes', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(buildSettings(const SettingsPage()));
    await tester.pumpAndSettle();

    final scrollable = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.text('settingsPaneMargins'.tr()),
      300,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();

    final normalLeft = find.byKey(
      ValueKey('${'settingsPaneNormalMode'.tr()}:margin-0'),
    );
    final fullScreenTop = find.byKey(
      ValueKey('${'settingsPaneFullScreenMode'.tr()}:margin-1'),
    );
    await tester.enterText(normalLeft, '12');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tester.enterText(fullScreenTop, '3.5');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    final settings = ProviderScope.containerOf(
      tester.element(find.byType(SettingsPage)),
    ).read(terminalSettingsProvider).value!;
    expect(settings.normalPaneMargin.left, 12);
    expect(settings.fullScreenPaneMargin.top, 3.5);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('terminal.normalPaneMargin'), contains('"left":12'));
    expect(
      prefs.getString('terminal.fullScreenPaneMargin'),
      contains('"top":3.5'),
    );
  });

  testWidgets('about entry opens the about page', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en', 'US')],
        path: 'assets/translations',
        fallbackLocale: const Locale('en', 'US'),
        useFallbackTranslations: true,
        child: ProviderScope(
          overrides: [
            packageInfoProvider.overrideWith(
              (ref) async => PackageInfo(
                appName: 'MaidTerm',
                packageName: 'com.solsynth.maidterm',
                version: '0.1.0',
                buildNumber: '1',
              ),
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: [
              ...material_ui.GlobalMaterialLocalizations.delegates,
              GlobalMaterialLocalizations.delegate,
            ],
            home: const SettingsPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('settingsAboutTile'.tr()),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('settingsAboutTile'.tr()));
    await tester.pumpAndSettle();

    expect(find.byType(AboutPage), findsOneWidget);
  });

  testWidgets('accent color accepts manual hex input and persists', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(buildSettings(const SettingsPage()));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(SettingsPage)),
    );
    final hexField = find.byKey(const ValueKey('accent-color-hex'));

    // Invalid hex shows an error and leaves the color unchanged.
    await tester.enterText(hexField, '#ZZZZZZ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('settingsHexError'.tr()), findsOneWidget);
    expect(
      container.read(terminalSettingsProvider).value?.seedColor,
      const Color(0xFF0F766E),
    );

    // Valid hex applies and persists to preferences.
    await tester.enterText(hexField, '#6750A4');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('settingsHexError'.tr()), findsNothing);
    expect(
      container.read(terminalSettingsProvider).value?.seedColor,
      const Color(0xFF6750A4),
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('app.seedColor'), 0xFF6750A4);
  });

  testWidgets('accent color editor dialog applies a custom color', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(buildSettings(const SettingsPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('accent-color-edit')));
    await tester.pumpAndSettle();
    expect(find.text('settingsColorDialogHelp'.tr()), findsOneWidget);

    final dialogHexField = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(dialogHexField, '#B3261E');
    await tester.pumpAndSettle();
    await tester.tap(find.text('commonSave'.tr()));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(SettingsPage)),
    );
    expect(
      container.read(terminalSettingsProvider).value?.seedColor,
      const Color(0xFFB3261E),
    );
    expect(find.byType(AlertDialog), findsNothing);
  });
  testWidgets('language dropdown switches locale and persists', (tester) async {
    await tester.pumpWidget(buildSettings(const SettingsPage()));
    await tester.pumpAndSettle();

    // The dropdown starts on the device locale (en-US).
    expect(find.text('English'), findsOneWidget);
    expect(find.text('settingsTitle'.tr()), findsOneWidget);

    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('简体中文').last);
    await tester.pumpAndSettle();

    // The page re-renders in Chinese; the raw key is gone.
    expect(find.text('设置'), findsOneWidget);
    expect(find.text('settingsTitle'), findsNothing);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('locale'), 'zh_CN');
  });
}
