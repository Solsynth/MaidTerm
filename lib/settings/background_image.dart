import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _backgroundImageFileName = 'maidterm_app_background';
const _backgroundImageEnabledKey = 'app.backgroundImageEnabled';

/// The user-provided image stored in application support.
final maidTermBackgroundImageProvider = FutureProvider<File?>((ref) async {
  if (kIsWeb) return null;

  final directory = await getApplicationSupportDirectory();
  final file = File('${directory.path}/$_backgroundImageFileName');
  return file.existsSync() ? file : null;
});

/// Whether the stored background image is currently shown.
final maidTermBackgroundImageEnabledProvider = FutureProvider<bool>((
  ref,
) async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_backgroundImageEnabledKey) ?? true;
});

Future<void> setMaidTermBackgroundImageEnabled(
  WidgetRef ref,
  bool enabled,
) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_backgroundImageEnabledKey, enabled);
  ref.invalidate(maidTermBackgroundImageEnabledProvider);
}

Future<void> saveMaidTermBackgroundImage(WidgetRef ref, File source) async {
  final directory = await getApplicationSupportDirectory();
  await source.copy('${directory.path}/$_backgroundImageFileName');
  await setMaidTermBackgroundImageEnabled(ref, true);
  ref.invalidate(maidTermBackgroundImageProvider);
}

Future<void> clearMaidTermBackgroundImage(WidgetRef ref) async {
  final directory = await getApplicationSupportDirectory();
  final file = File('${directory.path}/$_backgroundImageFileName');
  if (await file.exists()) await file.delete();
  ref.invalidate(maidTermBackgroundImageProvider);
}
