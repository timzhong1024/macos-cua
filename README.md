# macos-cua

`macos-cua` is a macOS-only low-level computer-use runtime for agents.

It is designed around three defaults:

- Coordinates default to the frontmost-window coordinate space.
- The frontmost window is first-class.
- Human-readable stdout is the default; add `--json` for structured output.

## Permissions

`macos-cua` relies on standard macOS permissions:

- `Accessibility`: required for synthetic mouse, keyboard, and window actions.
- `Screen Recording`: required for screenshots.

Use `macos-cua doctor` to inspect current readiness.

Use `macos-cua onboard` to trigger the native prompts, open the relevant System Settings panes, and guide a human through granting both permissions. In a tty session it waits by default; in non-tty mode it triggers the flow and returns immediately unless you pass `--wait`. When Screen Recording appears to have been granted but the process has not yet been restarted, `onboard` surfaces a targeted restart hint rather than a generic enable instruction. Add `--json` for structured output including per-permission `granted`, `waited`, and `likelyNeedsRestart` fields.

## Commands

```text
macos-cua [--json] <command> [args...]

onboard [--wait|--no-wait] [--timeout <seconds>] [--no-request] [--no-open]
doctor
state
record enable|disable|status
screenshot [--screen] [--region x y w h] <path.png>
move <x> <y> [--screen] [--fast|--precise]
click <x> <y> [left|right|middle] [--screen] [--fast|--precise]
double-click <x> <y> [left|right|middle] [--screen] [--fast|--precise]
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
swift run macos-cua onboard
swift run macos-cua onboard --wait --timeout 180
swift run macos-cua --json onboard --no-wait
swift run macos-cua record enable
swift run macos-cua --json state
swift run macos-cua screenshot /tmp/frontmost.png
swift run macos-cua screenshot --screen /tmp/screen.png
swift run macos-cua screenshot --region 100 100 300 200 /tmp/region.png
swift run macos-cua move 800 400 --precise
swift run macos-cua move 800 400 --screen --precise
swift run macos-cua click 800 400 --fast
swift run macos-cua click 800 400 --screen --fast
swift run macos-cua keypress cmd+n
swift run macos-cua type "hello from macos-cua"
swift run macos-cua clipboard set "hello"
swift run macos-cua clipboard paste
swift run macos-cua app activate Code
swift run macos-cua window list
```

## Notes

- Default `screenshot`, `move`, `click`, and `double-click` use frontmost-window coordinates.
- `--screen` switches `screenshot`, `move`, `click`, and `double-click` to screen-global coordinates.
- If no usable frontmost window is available, default coordinate-taking commands fall back to screen coordinates and report that fallback in output.
- `window list` is AX-first when Accessibility is available, then falls back to CoreGraphics window discovery.
- `window list`, `window frontmost`, and `state.frontmostWindow.bounds` remain screen-global diagnostics; they are not window-local action coordinates.
- Missing permission errors point back to `macos-cua onboard` so agent and human flows land on the same recovery path.
- Browser DOM/ref actions are intentionally out of scope for this repo.
- `record enable` starts a persistent session under `~/Library/Application Support/macos-cua/records/`; each subsequent command appends an action log entry, a full-screen timeline screenshot, failure-only snapshots, and a replayable `replay.sh` trace until `record disable`.
- A shareable VS Code debug example lives at `.vscode/launch.example.json`; local `.vscode/launch.json` stays ignored.
- GitHub Actions can be triggered manually to build release CLI archives for both `arm64` and `x86_64` macOS runners.
- Pointer movement anti-bot research notes live in [`docs/research/movement-anti-bot.md`](docs/research/movement-anti-bot.md).
- `move`, `click`, and `double-click` use humanized pointer motion profiles; default is `--fast`, with `--precise` available for tighter target acquisition.

## State Output

- `state.defaultCoordinateSpace` reports whether default coordinate-taking commands currently resolve to `window` or `screen`.
- `state.defaultCoordinateFallback` is `true` when default commands had to fall back from window coordinates to screen coordinates.
- `state.pointerScreen` is the current pointer in screen-global coordinates.
- `state.pointerWindow` is the current pointer relative to the frontmost window when available, otherwise `null`.
- `state.frontmostWindow.bounds` stays in screen-global coordinates to make window-local to screen-global translation explicit.

## Screenshot Resolution

- Screenshot output is normalized to logical action-space dimensions, not Retina/native pixel dimensions.
- This keeps screenshot coordinates aligned with the active coordinate space for `move` and `click` without requiring callers to divide by `scale`.
- `actionSpace.width` and `actionSpace.height` still describe the main-screen logical action space.
- For `screenshot --screen`, `image.width` and `image.height` match the main-screen action space.
- For default window screenshots, `image.width` and `image.height` match the frontmost window size and the returned `bounds` are window-local.
- For default region screenshots, `bounds` are interpreted in the active coordinate space and align with the returned raster.
- Window screenshots are captured without the macOS drop shadow so the image edges line up with the reported window bounds.
- Native pixel fidelity is intentionally discarded during screenshot export to preserve direct coordinate compatibility for agent actions.
