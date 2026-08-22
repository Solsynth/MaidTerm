import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Displays local desktop notifications requested by terminal applications.
abstract final class AppNotifications {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static var _initialized = false;
  static var _nextId = 0;

  /// Initializes the platform notification backend and requests the required
  /// desktop permission where the platform supports it.
  static Future<void> initialize() async {
    if (_initialized) return;

    final initialized = await _plugin.initialize(
      settings: const InitializationSettings(
        macOS: DarwinInitializationSettings(
          requestAlertPermission: true,
          requestSoundPermission: true,
          requestBadgePermission: false,
        ),
        linux: LinuxInitializationSettings(defaultActionName: 'Open'),
        windows: WindowsInitializationSettings(
          appName: 'MaidTerm',
          appUserModelId: 'MaidKit.MaidTerm.0.1',
          guid: '9b3e6a45-4a8c-4cc3-ae68-5c0a54dd7e4f',
        ),
      ),
    );
    if (initialized != true) return;
    _initialized = true;
  }

  /// Shows a notification if the plugin has initialized successfully.
  static Future<void> show({
    required String title,
    required String body,
  }) async {
    if (!_initialized || body.isEmpty) return;

    await _plugin.show(
      id: _nextId++,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        macOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBanner: true,
          presentList: true,
          presentSound: true,
        ),
        linux: LinuxNotificationDetails(),
        windows: WindowsNotificationDetails(),
      ),
    );
  }
}
