# macos-cua vs Codex Computer Use vs bb-browser

This guide compares the three control surfaces that most often overlap in
agent workflows:

- `macos-cua`
- Codex Computer Use
- `bb-browser`

The point is not to crown one as universally better. The point is to choose the
right abstraction for the target surface and failure mode.

## Short Positioning

| Tool | Best mental model | Best at | Loses when |
| --- | --- | --- | --- |
| `macos-cua` | OS-level desktop input runtime | Visual-first desktop control, weak-a11y apps, cross-app glue | You need rich semantic structure or browser-native extraction |
| Codex Computer Use | App session plus key-window accessibility control | Element-oriented desktop interaction when the AX tree is usable | The app exposes little or broken accessibility structure |
| `bb-browser` | Controlled Chrome session plus site adapters | Browser tasks, login-aware site workflows, structured web data | The target is a native desktop app or outside the controlled browser |

## Core Differences

| Dimension | `macos-cua` | Codex Computer Use | `bb-browser` |
| --- | --- | --- | --- |
| Primary target | Native desktop and browser windows via macOS input | Native desktop apps through app state and accessibility | Chrome pages in the controlled browser session |
| Operation unit | Coordinates, pointer, keyboard, clipboard, app/window activation | App, key window, accessibility element | Browser tab, page, site adapter, sometimes screenshot/snapshot |
| Observation model | `state` plus `screenshot` | `get_app_state` returns key-window screenshot plus accessibility tree | Browser URL/tab/adapters, screenshots, snapshots, structured adapter output |
| Action model | Mouse, keyboard, scroll, clipboard, app/window switching | Click, scroll, keypress, type, set value, secondary AX actions | Open page, inspect tab, adapter commands, fetch, eval, browser-native workflows |
| Browser specialization | Low | Low to medium | High |
| Native app coverage | High when visual control is enough | Medium to high when accessibility is strong | Low |
| Weak-a11y app resilience | High | Low to medium | Not applicable |
| Structured data extraction | Low | Low | High |
| Token efficiency | Good for direct act-observe loops | Good when the AX tree is compact; degrades when trees get large | Best when adapters exist; screenshots are fallback |
| Login/session handling | Uses the user's current desktop state | Uses the target app's current desktop state | Uses the specific Chrome profile controlled by `bb-browser` |
| Typical failure mode | Misclicks, wrong coordinate space, wrong hover target | Missing or incomplete AX tree, unsupported accessibility action | Adapter mismatch, wrong controlled browser session, login state mismatch |

## Operation Unit

The three tools operate at different layers:

- `macos-cua`: coordinate space and OS input events
- Codex Computer Use: app -> key window -> accessibility element
- `bb-browser`: browser session -> tab/page -> site adapter or browser API

That difference matters more than command count.

If the target surface is visually obvious but semantically weak, `macos-cua`
usually wins.

If the target surface exposes stable, useful accessibility elements, Computer
Use is often cleaner.

If the task is fundamentally "work with a website", `bb-browser` should be the
default before either desktop-oriented option.

## Weak-a11y Apps

For weak-a11y native apps, `macos-cua` has the strongest fallback story because
it can still act through pointer and keyboard events even when the internal UI
tree is missing.

Computer Use is much more sensitive to whether the app exposes scrollable or
interactive accessibility elements.

### Telegram example

Local test on 2026-04-20:

- Computer Use `get_app_state("Telegram")` exposed only the standard window and
  menu bar, without useful inner scroll targets.
- Computer Use `scroll(app="Telegram", element_index="0", direction="down")`
  returned `AXError.notImplemented`.
- `macos-cua scroll` succeeded after moving the pointer over the message pane,
  and the before/after screenshots showed the message history moving.

This is representative of the abstraction difference:

- Computer Use needs a usable AX target for scroll.
- `macos-cua` can still work when the app accepts normal wheel events.

## Browser Work

For browser tasks, prefer `bb-browser` unless there is a strong reason not to.

Reasons:

- It works against a controlled Chrome session.
- It can verify login state in that exact session.
- It can use site adapters and structured outputs instead of desktop automation.
- It keeps browser workflows in the browser layer instead of bouncing through
  screenshots and desktop coordinates.

Use `macos-cua` for browser pages only when the task is still fundamentally a
visual desktop-control problem.

Use Computer Use for browser pages only when you specifically want to work
through the app's current key-window accessibility view and that tree is good
enough.

## Selection Table

| Scenario | Default choice | Why |
| --- | --- | --- |
| Weak-a11y native app such as Telegram, game launchers, custom Electron surfaces | `macos-cua` | Coordinate and event control survives poor accessibility exposure |
| Native app with strong, useful accessibility structure | Codex Computer Use | Element-level actions and app-state inspection are cleaner than coordinate loops |
| Logged-in website workflow in Chrome | `bb-browser` | Session-aware browser control beats desktop automation |
| Structured extraction from a supported website | `bb-browser` | Adapter output is lower-token and more robust than screenshots |
| Cross-app glue such as copy, paste, activate app, switch window | `macos-cua` | It exposes clipboard and basic app/window control directly |
| Need to inspect what a desktop app is exposing semantically | Codex Computer Use | `get_app_state` gives a screenshot and the current AX tree in one call |
| Dense visual desktop UI with tiny targets | `macos-cua` | Region screenshots plus direct click control fit the problem |
| Need browser-only fetch/eval/tab inspection | `bb-browser` | Those are native features of the browser control plane |

## Practical Rules

Start with this order:

1. If the task is primarily a website task, start with `bb-browser`.
2. If the task is primarily a desktop app task and the app is known to be weak
   on accessibility, start with `macos-cua`.
3. If the desktop app is likely to expose a useful accessibility tree, try
   Computer Use first and fall back to `macos-cua` if the tree is thin or the
   action is unsupported.

Fallback rules:

- Browser task failing in Computer Use or `macos-cua` does not automatically
  mean the task is hard. It may just be using the wrong layer. Switch to
  `bb-browser`.
- Desktop task failing in Computer Use due to missing elements or unsupported
  AX actions should usually fall back to `macos-cua`.
- `macos-cua` failures that look like coordinate drift should first be debugged
  with region screenshots and coordinate-space checks, not by switching tools
  immediately.

## Recommendation Summary

Use `macos-cua` as the visual desktop runtime.

Use Codex Computer Use as the semantic desktop runtime when accessibility is
actually available and useful.

Use `bb-browser` as the browser runtime.
