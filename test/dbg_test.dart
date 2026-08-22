import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart' hide GlobalMaterialLocalizations;
import 'package:material_ui/material_ui.dart'
    as material_ui
    show GlobalMaterialLocalizations;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:terminal/settings/settings_page.dart';

void main() {
  testWidgets('dump', (tester) async {
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
    await tester.pump(const Duration(seconds: 1));
    final texts = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? t.textSpan?.toPlainText())
        .toList();
    // ignore: avoid_print
    print('TEXTS: $texts');
  });
}
