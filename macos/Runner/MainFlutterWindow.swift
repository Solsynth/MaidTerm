import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var terminalMenuTarget: TerminalMenuTarget?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()

    let channel = FlutterMethodChannel(
      name: "maidterm/menu",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    terminalMenuTarget = TerminalMenuTarget(channel: channel)
    DispatchQueue.main.async { [weak self] in
      self?.installTerminalMenu()
    }
  }

  func installTerminalMenu() {
    guard let target = terminalMenuTarget else { return }
    guard let mainMenu = NSApp.mainMenu,
          mainMenu.item(withTitle: "Terminal") == nil else {
      return
    }
    let terminalMenu = NSMenu(title: "Terminal")
    terminalMenu.addItem(menuItem("New Tab", key: "t", target: target, action: #selector(TerminalMenuTarget.newTab(_:))))
    terminalMenu.addItem(menuItem("Split Pane Right", key: "d", target: target, action: #selector(TerminalMenuTarget.splitRight(_:))))
    terminalMenu.addItem(menuItem("Split Pane Below", key: "d", modifiers: [.command, .shift], target: target, action: #selector(TerminalMenuTarget.splitBelow(_:))))
    terminalMenu.addItem(.separator())
    terminalMenu.addItem(menuItem("Close Pane", key: "w", target: target, action: #selector(TerminalMenuTarget.closePane(_:))))
    terminalMenu.addItem(menuItem("Close Tab", key: "w", modifiers: [.command, .shift], target: target, action: #selector(TerminalMenuTarget.closeTab(_:))))

    let terminalItem = NSMenuItem()
    terminalItem.title = "Terminal"
    terminalItem.submenu = terminalMenu
    let viewIndex = mainMenu.items.firstIndex { $0.title == "View" } ?? mainMenu.items.count
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
