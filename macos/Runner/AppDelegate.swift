import Cocoa
import FlutterMacOS

/// Owns the single Flutter engine the whole app runs on.
///
/// Windows are created from Dart through Flutter's multi-window API, so this
/// delegate deliberately creates no `NSWindow`: the nib only builds the menu
/// bar, and every terminal window is a view of the engine below.
@main
class AppDelegate: FlutterAppDelegate {
  private var engine: FlutterEngine?
  private var terminalMenuTarget: TerminalMenuTarget?

  override func applicationDidFinishLaunching(_ notification: Notification) {
    let engine = FlutterEngine(name: "maidterm", project: nil)
    engine.run(withEntrypoint: nil)
    RegisterGeneratedPlugins(registry: engine)
    self.engine = engine

    let menuChannel = FlutterMethodChannel(
      name: "maidterm/menu",
      binaryMessenger: engine.binaryMessenger
    )
    terminalMenuTarget = TerminalMenuTarget(channel: menuChannel)
    DispatchQueue.main.async { [weak self] in
      self?.installTerminalMenu()
    }

    super.applicationDidFinishLaunching(notification)
  }

  /// Windows are destroyed by Dart, which decides when the app is done; the
  /// last window closing may still be cancelled by the user.
  override func applicationShouldTerminateAfterLastWindowClosed(
    _ sender: NSApplication
  ) -> Bool {
    return false
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication)
    -> Bool
  {
    return true
  }

  func installTerminalMenu() {
    guard let target = terminalMenuTarget else { return }
    guard let mainMenu = NSApp.mainMenu,
      mainMenu.item(withTitle: "Terminal") == nil
    else {
      return
    }
    let terminalMenu = NSMenu(title: "Terminal")
    terminalMenu.addItem(
      menuItem("New Tab", key: "t", target: target, action: #selector(TerminalMenuTarget.newTab(_:)))
    )
    terminalMenu.addItem(
      menuItem("New Window", key: "n", target: target, action: #selector(TerminalMenuTarget.newWindow(_:)))
    )
    terminalMenu.addItem(
      menuItem("Split Pane Right", key: "d", target: target, action: #selector(TerminalMenuTarget.splitRight(_:)))
    )
    terminalMenu.addItem(
      menuItem(
        "Split Pane Below", key: "d", modifiers: [.command, .shift], target: target,
        action: #selector(TerminalMenuTarget.splitBelow(_:)))
    )
    terminalMenu.addItem(.separator())
    terminalMenu.addItem(
      menuItem("Close Pane", key: "w", target: target, action: #selector(TerminalMenuTarget.closePane(_:)))
    )
    terminalMenu.addItem(
      menuItem(
        "Close Tab", key: "w", modifiers: [.command, .shift], target: target,
        action: #selector(TerminalMenuTarget.closeTab(_:)))
    )

    let terminalItem = NSMenuItem()
    terminalItem.title = "Terminal"
    terminalItem.submenu = terminalMenu
    let viewIndex =
      mainMenu.items.firstIndex { $0.title == "View" } ?? mainMenu.items.count
    mainMenu.insertItem(terminalItem, at: viewIndex)
  }

  private func menuItem(
    _ title: String,
    key: String,
    modifiers: NSEvent.ModifierFlags = [.command],
    target: AnyObject,
    action: Selector
  ) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
    item.keyEquivalentModifierMask = modifiers
    item.target = target
    return item
  }
}

private final class TerminalMenuTarget: NSObject {
  private let channel: FlutterMethodChannel

  init(channel: FlutterMethodChannel) {
    self.channel = channel
  }

  @objc func newTab(_ sender: Any?) {
    channel.invokeMethod("newTab", arguments: nil)
  }

  @objc func newWindow(_ sender: Any?) {
    channel.invokeMethod("newWindow", arguments: nil)
  }

  @objc func splitRight(_ sender: Any?) {
    channel.invokeMethod("splitRight", arguments: nil)
  }

  @objc func splitBelow(_ sender: Any?) {
    channel.invokeMethod("splitBelow", arguments: nil)
  }

  @objc func closeTab(_ sender: Any?) {
    channel.invokeMethod("closeTab", arguments: nil)
  }

  @objc func closePane(_ sender: Any?) {
    channel.invokeMethod("closePane", arguments: nil)
  }
}
