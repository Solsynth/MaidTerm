import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart' hide GlobalMaterialLocalizations;
import 'package:material_ui/material_ui.dart'
    as material_ui
    show GlobalMaterialLocalizations;
import 'package:package_info_plus/package_info_plus.dart';

import 'package:maidterm_app/settings/about_page.dart';

void main() {
  final info = PackageInfo(
    appName: 'MaidTerm',
    packageName: 'com.solsynth.maidterm',
    version: '0.1.0',
    buildNumber: '1',
  );

  Widget buildApp() => ProviderScope(
    overrides: [packageInfoProvider.overrideWith((ref) async => info)],
    child: MaterialApp(
      localizationsDelegates: [
        ...material_ui.GlobalMaterialLocalizations.delegates,
        GlobalMaterialLocalizations.delegate,
      ],
      home: const AboutPage(),
    ),
  );

  testWidgets('renders the app identity and version data', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(find.text('About'), findsOneWidget);
    expect(find.text('MaidTerm'), findsWidgets);
    expect(find.text('0.1.0'), findsOneWidget);
    expect(find.text('Version'), findsOneWidget);
    expect(find.text('Build'), findsOneWidget);
    expect(find.text('Package'), findsOneWidget);
    expect(find.text('App info'), findsOneWidget);

    final scrollable = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.text('Related products'),
      200,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();
    expect(find.text('Related products'), findsOneWidget);
    expect(find.text('MaidKit'), findsOneWidget);
    expect(find.text('Solar Network'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Check for updates'),
      200,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();
    expect(find.text('Check for updates'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Licenses'),
      200,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();
    expect(find.text('Licenses'), findsOneWidget);
  });

  testWidgets('license tile opens the license page', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Open-source licenses'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open-source licenses'));
    await tester.pumpAndSettle();

    // The license page carries the same title as the section heading.
    expect(find.text('Licenses'), findsWidgets);
  });
}
