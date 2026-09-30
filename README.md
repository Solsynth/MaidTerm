# MaidTerm

MaidTerm is a local-first desktop terminal emulator for macOS, Windows, and
Linux, built on the [MaidTerm engine](packages/maidterm) — a Flutter terminal
engine that wraps the Ghostty terminal emulator core through Dart FFI and
powers the MaidKit.

## Features

- Local shell sessions over a real PTY, with process-level title tracking
- A multi-session workspace: multiple terminals in tabs and split layouts
- Terminal settings: color schemes, fonts, and cursor/behavior preferences
  persisted locally
- Full extension support from the engine — kitty graphics protocol, kitty
  keyboard protocol, sixel, truecolor, OSC 0/2/7/9;4/10/11/52/133, OSC 8
- A frameless desktop window frame rendered by the app's own UI layer

## Architecture

```
MaidTerm app (this repository)
├── lib/workspace   — session layouts, terminal workspaces and pages
├── lib/shell       — PTY-backed local shell sessions, process title monitor
├── lib/settings    — theme, font, and behavior settings
└── packages/
    ├── maidterm    — the terminal engine (emulation + rendering)
    └── maidpty     — PTY plugin used for local shell sessions
```

The app is the thin product layer: it spawns shells with
`maidpty`, feeds PTY output into a `TerminalController`, and renders the
result through `TerminalView`. All terminal behavior — escape sequence
handling, graphics protocols, input encoding, and painting — lives in the
`maidterm` engine package.

## Tech stack

- [flutter](https://flutter.dev) / Dart (SDK ^3.13.0)
- [maidterm](packages/maidterm) — terminal engine based on
  [libghostty](https://github.com/elias8/libghostty) (Dart FFI bindings to
  Ghostty's Zig-based `libghostty-vt` emulator core)
- [maidpty](packages/maidpty) — PTY sessions
- [hooks_riverpod](https://pub.dev/packages/hooks_riverpod) — state
- [island_ui_foundation](https://src.solsynth.dev/SoSYS/Solian) /
  [material_ui](https://pub.dev/packages/material_ui) — theming and widgets
- [nativeapi](https://pub.dev/packages/nativeapi_flutter) — window drag
  sessions that track the cursor across windows

## Windows

A window is a view of the single Flutter engine, created from Dart through
Flutter's multi-window API: `WorkspaceWindowsController`
(`lib/windows/`) owns them and each window's `TerminalWorkspaceNotifier`
owns its tabs and PTY sessions. Because every window shares one engine,
moving a tab between windows reparents its widget subtree — the shell keeps
running and its scrollback and output stream come along.

Tabs are dragged with `na.WindowDragSession`, which reports the global cursor
even while the pointer is over another window's view. Dropping a tab on
another strip moves it there; dragging one far enough off its own strip
detaches it into a new window. Where the platform cannot report the cursor
(Wayland), tab presses fall back to reordering inside the strip.

## Getting started

```sh
flutter pub get
flutter run -d macos   # or -d windows / -d linux
```

The engine's native library is fetched by a build hook: a prebuilt
`libghostty` binary is downloaded automatically, or compiled from source when
Zig is installed (see `packages/maidterm`).

## Testing

```sh
flutter test              # app widget tests
(cd packages/maidterm && dart test)   # engine unit tests
```
