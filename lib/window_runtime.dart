import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'workspace/window_tab_transfer.dart';

final windowLaunchDataProvider = Provider<WindowLaunchData>(
  (ref) => const WindowLaunchData.main(),
);

const maidTermMainWindow = 'main';
const maidTermWorkspaceWindow = 'workspace';

class WindowLaunchData {
  const WindowLaunchData({required this.type, required this.window, this.tab});

  const WindowLaunchData.main({this.window})
    : type = maidTermMainWindow,
      tab = null;

  factory WindowLaunchData.fromWindow(WindowController controller) {
    return _fromSerialized(controller.arguments, controller);
  }

  factory WindowLaunchData.fromEntrypointArgs(
    WindowController controller,
    List<String> args,
  ) {
    if (args.length >= 3 && args[0] == 'multi_window') {
      return _fromSerialized(args[2], controller);
    }
    return WindowLaunchData.fromWindow(controller);
  }

  static WindowLaunchData _fromSerialized(
    String raw,
    WindowController controller,
  ) {
    if (raw.trim().isEmpty) {
      return WindowLaunchData.main(window: controller);
    }
    try {
      final json = jsonDecode(raw);
      if (json is! Map) return WindowLaunchData.main(window: controller);
      final tabJson = json['tab'];
      return WindowLaunchData(
        type: json['type'] as String? ?? maidTermMainWindow,
        window: controller,
        tab: tabJson is Map
            ? WorkspaceTabTransfer.fromJson(Map<dynamic, dynamic>.from(tabJson))
            : null,
      );
    } on Object {
      return WindowLaunchData.main(window: controller);
    }
  }

  final String type;
  final WindowController? window;
  final WorkspaceTabTransfer? tab;

  bool get isWorkspaceWindow => type == maidTermWorkspaceWindow;
}
