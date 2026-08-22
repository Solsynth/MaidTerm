import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart' hide GlobalMaterialLocalizations;
import 'package:material_ui/material_ui.dart'
    as material_ui
    show GlobalMaterialLocalizations;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:maidterm_app/settings/settings_page.dart';
import 'package:maidterm_app/settings/terminal_settings.dart';

void main() {
  testWidgets('settings page renders current values and persists changes', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'terminal.fontSize': 16.0,
      'terminal.cursorBlink': false,
      'terminal.cursorStyle': 'bar',
    });

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: [
            ...material_ui.GlobalMaterialLocalizations.delegates,
            GlobalMaterialLocalizations.delegate,
          ],
          home: const SettingsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);

    // Values loaded from prefs.
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SettingsPage)),
    );
    expect(container.read(terminalSettingsProvider).value?.fontSize, 16.0);

    // Toggle blink persists.
    await tester.scrollUntilVisible(
      find.text('Cursor blink'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cursor blink'));
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('terminal.cursorBlink'), isTrue);
  });
}
