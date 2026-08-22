# maidterm

A Flutter terminal engine: terminal emulation and rendering for desktop
terminal applications. It powers **MaidKit** and the **MaidTerm** terminal
emulator.

The emulation core is [Ghostty's `libghostty-vt`](https://github.com/ghostty-org/ghostty)
terminal emulator library, exposed through Dart FFI via
[libghostty](https://github.com/elias8/libghostty). MaidTerm adds the
rendering pipeline, input encoding, and the graphics protocols the core does
not implement itself.

## Tech stack

- Flutter / Dart — widgets and canvas rendering
- [libghostty](https://github.com/elias8/libghostty) — Dart FFI bindings to
  Ghostty's Zig terminal emulator core. The native library ships as a
  prebuilt binary (fetched by a build hook) or compiles from source with Zig.
- [image](https://pub.dev/packages/image) — PNG decoding for kitty graphics
- Custom Flutter rendering: glyph texture atlas, sprite renderer, and layered
  painters for backgrounds, shaped text, decorations, emoji, and graphics
  placements

## Capabilities

Emulation and rendering:

- VT100–VT520 escape sequences, alternate screen, scrollback, selection,
  bracketed paste, mouse tracking, text reflow on resize
- Truecolor (24-bit) and the full 256-color palette with OSC overrides
- Device attributes (DA1/DA2/DA3), XTWINOPS, DECRPM, and ENQ responses

Extensions:

- **Kitty graphics protocol** — transmit/display/placements, PNG and direct
  RGBA payloads, chunked transmissions, and the `OK` acknowledgment
- **Kitty keyboard protocol** — progressive enhancement flags and
  disambiguated key encoding
- **Sixel graphics** — a Dart sixel decoder in the input path that re-emits
  decoded images through the kitty graphics pipeline, moving the cursor like
  a native sixel renderer
- **OSC 0/2** titles, **OSC 7** working directory, **OSC 10/11** color
  queries, **OSC 52** clipboard, **OSC 133** semantic prompts
- **OSC 8** hyperlinks with link matching and activation modifiers

## Usage

```dart
final controller = TerminalController()
  ..onOutput = (bytes) => pty.write(bytes)
  ..onBell = () => playSound()
  ..onTitleChanged = () => updateTitle(controller.title);

TerminalView(controller: controller);

pty.onData = (bytes) => controller.write(bytes);
controller.sendText('ls -la\n');
```

- `TerminalController` — feed it backend bytes via `write`, receive responses
  and effects through `onOutput`/`onBell`/`onTitleChanged`/`onResize`, and
  send input with `sendText`/`sendKey`/`paste`
- `TerminalView` — the widget that renders the terminal and forwards
  keyboard/mouse input to the controller
- `TerminalConfig` — grid size, scrollback limit, kitty graphics storage
  limit, device attributes, cursor style, and initial terminal modes
- `Formatter` — extract terminal content as plain text, HTML, or VT
  sequences (for copy/export)

## Development

```sh
flutter pub get
dart test          # engine unit tests (sixel decoder, stream rewriter, ...)
```

The native library is resolved by the `libghostty` build hook: it downloads
the prebuilt binary for the current platform, or compiles from source when
Zig is available (`GHOSTTY_SRC` overrides the source checkout).
