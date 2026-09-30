// ignore_for_file: invalid_use_of_internal_member, implementation_imports

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/src/foundation/_features.dart' show isWindowingEnabled;
import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:maidterm_app/app.dart';
import 'package:maidterm_app/notifications/app_notifications.dart';

Future<void> main(List<String> args) async {
  // All windows are views of one engine: they are created from Dart through
  // Flutter's experimental multi-window API, which the stable channel still
  // gates behind a build-time feature flag.
  isWindowingEnabled = true;
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();
  EasyLocalization.logger.enableBuildModes = [];
  await AppNotifications.initialize();

  runWidget(
    ProviderScope(
      child: EasyLocalization(
        supportedLocales: const [
          Locale('en', 'US'),
          Locale('zh', 'CN'),
          Locale('zh', 'TW'),
        ],
        path: 'assets/translations',
        fallbackLocale: const Locale('en', 'US'),
        useFallbackTranslations: true,
        child: const MaidTermWindowsHost(),
      ),
    ),
  );
}
