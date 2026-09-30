import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maidterm_app/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/window_harness.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    EasyLocalization.logger.enableBuildModes = [];
  });

  Future<void> wrap(WidgetTester tester, Widget? menuButton) => pumpHarness(
    tester,
    Scaffold(
      body: MaidTermWindowScaffold(
        windowId: testWindowId,
        title: 'MaidTerm',
        menuButton: menuButton,
        child: const SizedBox.expand(),
      ),
    ),
  );

  testWidgets('without a menu button the title renders as a plain label',
      (tester) async {
    await wrap(tester, null);

    expect(find.text('MaidTerm'), findsOneWidget);
    // No centering wrapper: the label keeps island's default placement.
    expect(
      find.ancestor(
        of: find.text('MaidTerm'),
        matching: find.byType(Center),
      ),
      findsNothing,
    );
  });

  testWidgets('with a menu button the title is centered and the button shown',
      (tester) async {
    await wrap(
      tester,
      IconButton(
        icon: const Icon(Icons.menu),
        onPressed: () {},
      ),
    );

    expect(find.byIcon(Icons.menu), findsOneWidget);
    // The title is wrapped in a Center when the button layout is active.
    expect(
      find.ancestor(
        of: find.text('MaidTerm'),
        matching: find.byType(Center),
      ),
      findsOneWidget,
    );
  });
}
