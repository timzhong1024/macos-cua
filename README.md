# macos-cua

`macos-cua` is a macOS-only low-level computer-use runtime for agents.

It is designed around three defaults:

- Coordinates are always interpreted in the logical main-screen action space.
- The frontmost window is first-class.
- Human-readable stdout is the default; add `--json` for structured output.

## Permissions

`macos-cua` relies on standard macOS permissions:

- `Accessibility`: required for synthetic mouse, keyboard, and window actions.
- `Screen Recording`: required for screenshots.

Use `macos-cua doctor` to inspect current readiness.

## Commands

```text
macos-cua [--json] <command> [args...]

doctor
state
screenshot [--screen] [--region x y w h] <path.png>
move <x> <y> [--duration-ms N]
click <x> <y> [left|right|middle]
double-click <x> <y> [left|right|middle]
scroll <dx> <dy>
keypress <key[+key...]>
type [--fast] <text>
wait <ms>
clipboard get|set|copy|paste
app list|frontmost|activate
window frontmost|list|activate|minimize|maximize|close
```

## Examples

```bash
swift run macos-cua doctor
swift run macos-cua --json state
swift run macos-cua screenshot /tmp/frontmost.png
swift run macos-cua screenshot --screen /tmp/screen.png
swift run macos-cua screenshot --region 100 100 300 200 /tmp/region.png
swift run macos-cua move 800 400 --duration-ms 400
swift run macos-cua click 800 400
swift run macos-cua keypress cmd+n
swift run macos-cua type "hello from macos-cua"
swift run macos-cua clipboard set "hello"
swift run macos-cua clipboard paste
swift run macos-cua app activate Code
swift run macos-cua window list
```

## Notes

- Default `screenshot` captures the frontmost window and returns its bounds in action-space coordinates.
- `--screen` is explicit because full-screen capture is a secondary mode.
- `window list` is AX-first when Accessibility is available, then falls back to CoreGraphics window discovery.
- Browser DOM/ref actions are intentionally out of scope for this repo.
- A shareable VS Code debug example lives at `.vscode/launch.example.json`; local `.vscode/launch.json` stays ignored.
