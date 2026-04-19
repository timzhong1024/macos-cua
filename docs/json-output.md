# JSON Output And Automation

Human-readable stdout is the default.

Add `--json` only when you need machine-readable output for:

- automation
- tests
- logging
- structured post-processing

Examples:

```bash
swift run macos-cua --json state
swift run macos-cua --json onboard --no-wait
```

`--json` is useful for agents and scripts, but it is not the primary human-oriented path in the README.
