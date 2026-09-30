import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Whether any MaidTerm window is focused.
///
/// Focus belongs to the app, not to one window: a terminal notification is
/// muted while the user is looking at *any* window. The windows controller
/// keeps this current and sessions only read it, which keeps the shell layer
/// free of any dependency on the windows controller.
class AppFocus extends ValueNotifier<bool> {
  AppFocus() : super(false);
}

final appFocusProvider = Provider<AppFocus>((ref) {
  final focus = AppFocus();
  ref.onDispose(focus.dispose);
  return focus;
});
