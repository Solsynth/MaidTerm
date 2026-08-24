import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'workspace/window_tab_transfer.dart';

final windowLaunchDataProvider = Provider<WindowLaunchData>(
  (ref) => const WindowLaunchData.main(),
);

const maidTermMainWindow = 'main';
const maidTermWorkspaceWindow = 'workspace';
const windowProtocolVersion = 1;

class WindowLaunchData {
  const WindowLaunchData({
    required this.type,
    required this.window,
    this.tab,
    this.protocol = windowProtocolVersion,
    this.requestId,
    this.sourceWindowId,
    this.hiddenAtLaunch = false,
  });

  const WindowLaunchData.main({this.window})
    : type = maidTermMainWindow,
      tab = null,
      protocol = windowProtocolVersion,
      requestId = null,
      sourceWindowId = null,
      hiddenAtLaunch = false;

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
    if (raw.trim().isEmpty) return WindowLaunchData.main(window: controller);
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('Window payload is not an object');
    }
    final json = Map<dynamic, dynamic>.from(decoded);
    final protocolValue = (json['protocol'] as num?)?.toInt();
    if (protocolValue != windowProtocolVersion) {
      throw FormatException('Unsupported window protocol: ${json['protocol']}');
    }
    final protocol = protocolValue!;
    final type = json['type'];
    if (type is! String ||
        (type != maidTermMainWindow && type != maidTermWorkspaceWindow)) {
      throw FormatException('Unsupported window role: $type');
    }
    final tabJson = json['tab'];
    return WindowLaunchData(
      type: type,
      window: controller,
      protocol: protocol,
      requestId: json['requestId'] as String?,
      sourceWindowId: json['sourceWindowId'] as String?,
      hiddenAtLaunch: json['hiddenAtLaunch'] as bool? ?? false,
      tab: tabJson is Map
          ? WorkspaceTabTransfer.fromJson(Map<dynamic, dynamic>.from(tabJson))
          : null,
    );
  }

  final String type;
  final WindowController? window;
  final WorkspaceTabTransfer? tab;
  final int protocol;
  final String? requestId;
  final String? sourceWindowId;
  final bool hiddenAtLaunch;

  bool get isWorkspaceWindow => type == maidTermWorkspaceWindow;
}
