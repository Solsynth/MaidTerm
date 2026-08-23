import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maidterm_app/theme.dart';
void main() {
  Widget wrap(Widget? menuButton) {
    return MaterialApp(
      home: Scaffold(
        body: MaidTermWindowScaffold(
          title: 'MaidTerm',
          menuButton: menuButton,
          child: const SizedBox.expand(),
        ),
      ),
    );
  }

  testWidgets('without a menu button the title renders as a plain label',
      (tester) async {
    await tester.pumpWidget(wrap(null));
    await tester.pumpAndSettle();

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
    await tester.pumpWidget(
      wrap(
        IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

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
