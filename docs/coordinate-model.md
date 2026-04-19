# Coordinate Model

`macos-cua` is window-first by default.

## Default Behavior

- `screenshot`, `move`, and `click` use frontmost-window coordinates
- `--screen` switches them to screen-global coordinates
- if no usable frontmost window is available, these commands fall back to screen coordinates

This is the default action model and the preferred happy path.

## Diagnostics

These remain screen-global diagnostics:

- `window list`
- `state.frontmostWindow.bounds`

This makes local-to-global translation explicit instead of hiding it.

## State Fields

Use `state` to inspect the current action context:

- `defaultCoordinateSpace`
- `defaultCoordinateFallback`
- `pointerScreen`
- `pointerWindow`
- `pointerRelative` when running with `--relative`

## Region Screenshots

- default `screenshot --region x y w h` uses the active coordinate space
- with `--screen`, the region is screen-global
- with `--relative`, the region is interpreted in `[0, 1000]` relative to the active coordinate space

For dense pages and small targets, use `screenshot --region` as a second-pass
inspection step:

1. capture the full window for context
2. crop tightly around the likely target area
3. re-read that local crop before issuing the final click

## Why Absolute Comes First

When the screenshot is consumed at its useful logical resolution, absolute coordinates keep `image space` and `action space` directly aligned. That usually gives the best click precision and the easiest debugging path.
