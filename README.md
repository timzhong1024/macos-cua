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
record enable|disable|status
screenshot [--screen] [--region x y w h] <path.png>
move <x> <y> [--fast|--precise]
click <x> <y> [left|right|middle] [--fast|--precise]
double-click <x> <y> [left|right|middle] [--fast|--precise]
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
swift run macos-cua record enable
swift run macos-cua --json state
swift run macos-cua screenshot /tmp/frontmost.png
swift run macos-cua screenshot --screen /tmp/screen.png
swift run macos-cua screenshot --region 100 100 300 200 /tmp/region.png
swift run macos-cua move 800 400 --precise
swift run macos-cua click 800 400 --fast
swift run macos-cua keypress cmd+n
swift run macos-cua type "hello from macos-cua"
swift run macos-cua clipboard set "hello"
swift run macos-cua clipboard paste
swift run macos-cua app activate Code
swift run macos-cua window list
```

## Notes

- Default `screenshot` captures the frontmost window and normalizes the output image to action-space resolution.
- `--screen` is explicit because full-screen capture is a secondary mode.
- `window list` is AX-first when Accessibility is available, then falls back to CoreGraphics window discovery.
- Browser DOM/ref actions are intentionally out of scope for this repo.
- `record enable` starts a persistent session under `~/Library/Application Support/macos-cua/records/`; each subsequent command appends an action log entry, a full-screen timeline screenshot, failure-only snapshots, and a replayable `replay.sh` trace until `record disable`.
- A shareable VS Code debug example lives at `.vscode/launch.example.json`; local `.vscode/launch.json` stays ignored.
- GitHub Actions can be triggered manually to build release CLI archives for both `arm64` and `x86_64` macOS runners.
- Pointer movement anti-bot research notes live in [`docs/research/movement-anti-bot.md`](docs/research/movement-anti-bot.md).
- `move`, `click`, and `double-click` use humanized pointer motion profiles; default is `--fast`, with `--precise` available for tighter target acquisition.

## Screenshot Resolution

- Screenshot output is normalized to logical action-space dimensions, not Retina/native pixel dimensions.
- This keeps screenshot coordinates aligned with `move`, `click`, and window `bounds` without requiring callers to divide by `scale`.
- `actionSpace.width` and `actionSpace.height` describe the coordinate system used for input and the default screenshot raster size.
- For `screenshot --screen`, `image.width` and `image.height` match the main-screen action space.
- For window screenshots, `image.width` and `image.height` match the captured window `bounds.width` and `bounds.height`.
- Window screenshots are captured without the macOS drop shadow so the image edges line up with the reported window bounds.
- Native pixel fidelity is intentionally discarded during screenshot export to preserve direct coordinate compatibility for agent actions.
