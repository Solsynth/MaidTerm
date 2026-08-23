import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart' hide GlobalMaterialLocalizations;
import 'package:material_ui/material_ui.dart'
    as material_ui
    show GlobalMaterialLocalizations;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:maidterm_app/settings/settings_page.dart';
import 'package:maidterm_app/settings/terminal_fonts.dart';
import 'package:maidterm_app/settings/terminal_settings.dart';

void main() {
  testWidgets('settings page renders current values and persists changes', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'terminal.fontFamily': 'Fira Code',
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
    expect(find.text('Background image'), findsOneWidget);
    expect(find.text('Choose image'), findsOneWidget);
    expect(find.text('No image selected.'), findsOneWidget);

    // Values loaded from prefs.
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SettingsPage)),
    );
    expect(container.read(terminalSettingsProvider).value?.fontSize, 16.0);
    expect(container.read(terminalFontFamilyProvider), 'Fira Code');

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

  testWidgets('tab bar position control persists selection', (tester) async {
    SharedPreferences.setMockInitialValues({});

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

    await tester.scrollUntilVisible(
      find.text('Tab bar'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Left').first);
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

  testWidgets('edits and persists pane margins', (tester) async {
    SharedPreferences.setMockInitialValues({});

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

    final scrollable = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.text('Pane margins'),
      300,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();

    final terminalLeft = find.byKey(const ValueKey('Terminal:margin-0'));
    await tester.enterText(terminalLeft, '12');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    final settings = ProviderScope.containerOf(
      tester.element(find.byType(SettingsPage)),
    ).read(terminalSettingsProvider).value!;
    expect(settings.normalPaneMargin.left, 12);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('terminal.normalPaneMargin'), contains('"left":12'));
  });
}
