import Foundation

enum CLI {
    static let usage = """
    Usage:
      macos-cua [--json] <command> [args...]

    Commands:
      doctor
      state
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

    Notes:
      Coordinates are always in the logical main-screen action space.
      Screenshot defaults to the frontmost window. Use --screen for full screen.
      Pointer movement defaults to the fast humanized profile.
    """

    static func run(arguments: [String]) throws {
        var args = arguments
        var json = false
        if let first = args.first, first == "--json" {
            json = true
            args.removeFirst()
        }
        guard let command = args.first else {
            print(usage)
            return
        }
        if ["-h", "--help", "help"].contains(command) {
            print(usage)
            return
        }

        let output = CLIOutput(json: json)
        switch command {
        case "doctor":
            try doctor(output: output)
        case "state":
            try state(output: output)
        case "screenshot":
            try screenshot(args: Array(args.dropFirst()), output: output)
        case "move":
            try move(args: Array(args.dropFirst()), output: output)
        case "click":
            try click(args: Array(args.dropFirst()), output: output, count: 1)
        case "double-click":
            try click(args: Array(args.dropFirst()), output: output, count: 2)
        case "scroll":
            try scroll(args: Array(args.dropFirst()), output: output)
        case "keypress":
            try keypress(args: Array(args.dropFirst()), output: output)
        case "type":
            try typeText(args: Array(args.dropFirst()), output: output)
        case "wait":
            try wait(args: Array(args.dropFirst()), output: output)
        case "clipboard":
            try clipboard(args: Array(args.dropFirst()), output: output)
        case "app":
            try app(args: Array(args.dropFirst()), output: output)
        case "window":
            try window(args: Array(args.dropFirst()), output: output)
        default:
            throw CUAError(message: "unsupported command: \(command)")
        }
    }

    static func doctor(output: CLIOutput) throws {
        let accessibility = WindowSupport.isAccessibilityTrusted()
        let screenRecording = ScreenshotSupport.screenCaptureAccess()
        let frontmostApp = AppSupport.frontmostApplication().map(AppSupport.record(for:))?.json
        let frontmostWindow = WindowSupport.frontmostWindow()?.json
        let actionSpace = try InputSupport.actionSpace()

        var screenshotCheck: [String: Any] = [
            "ok": false,
        ]
        if screenRecording {
            let tempPath = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("macos-cua-doctor-\(UUID().uuidString).png")
            do {
                _ = try ScreenshotSupport.capture(target: .frontmostWindow, path: tempPath.path)
                screenshotCheck = ["ok": true, "path": tempPath.path]
                try? FileManager.default.removeItem(at: tempPath)
            } catch {
                screenshotCheck = ["ok": false, "error": error.localizedDescription]
            }
        }

        let payload: [String: Any] = [
            "accessibility": accessibility,
            "screenRecording": screenRecording,
            "syntheticInputReady": accessibility,
            "screenshotReady": screenshotCheck,
            "frontmostApp": frontmostApp as Any,
            "frontmostWindow": frontmostWindow as Any,
            "actionSpace": actionSpace,
        ]
        try output.emit(
            payload,
            lines: [
                "Accessibility: \(accessibility ? "ready" : "missing")",
                "Screen Recording: \(screenRecording ? "ready" : "missing")",
                "Synthetic input: \(accessibility ? "ready" : "missing")",
                "Screenshot check: \((screenshotCheck["ok"] as? Bool) == true ? "ok" : "failed")",
                "Frontmost app: \((frontmostApp?["name"] as? String) ?? "n/a")",
                "Frontmost window: \((frontmostWindow?["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "<untitled>")",
            ]
        )
    }

    static func state(output: CLIOutput) throws {
        let pointer = InputSupport.currentPointer()
        let modifiers = InputSupport.currentModifierNames()
        let mouseButtons = InputSupport.currentMouseButtons()
        let frontmostApp = AppSupport.frontmostApplication().map(AppSupport.record(for:))?.json
        let frontmostWindow = WindowSupport.frontmostWindow()?.json
        var releaseHints: [String] = []
        releaseHints.append(contentsOf: modifiers.map { "release key \($0)" })
        releaseHints.append(contentsOf: mouseButtons.map { "release mouse \($0)" })

        let payload: [String: Any] = [
            "pointer": ["x": Int(pointer.x.rounded()), "y": Int(pointer.y.rounded())],
            "held": [
                "modifiers": modifiers,
                "mouseButtons": mouseButtons,
            ],
            "releaseHints": releaseHints,
            "frontmostApp": frontmostApp as Any,
            "frontmostWindow": frontmostWindow as Any,
            "actionSpace": try InputSupport.actionSpace(),
        ]
        try output.emit(
            payload,
            lines: [
                "Pointer: \(Int(pointer.x.rounded())),\(Int(pointer.y.rounded()))",
                "Held modifiers: \(modifiers.isEmpty ? "none" : modifiers.joined(separator: ", "))",
                "Held mouse buttons: \(mouseButtons.isEmpty ? "none" : mouseButtons.joined(separator: ", "))",
                "Frontmost app: \((frontmostApp?["name"] as? String) ?? "n/a")",
                "Frontmost window: \((frontmostWindow?["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "<untitled>")",
            ]
        )
    }

    static func screenshot(args: [String], output: CLIOutput) throws {
        guard !args.isEmpty else {
            throw CUAError(message: "usage: macos-cua screenshot [--screen] [--region x y w h] <path.png>")
        }
        var target = ScreenshotTarget.frontmostWindow
        var rest = args
        if rest.first == "--screen" {
            target = .screen
            rest.removeFirst()
        } else if rest.first == "--region" {
            guard rest.count >= 6 else {
                throw CUAError(message: "usage: macos-cua screenshot --region x y w h <path.png>")
            }
            let x = try parseInt(rest[1], name: "x")
            let y = try parseInt(rest[2], name: "y")
            let w = try parseInt(rest[3], name: "width")
            let h = try parseInt(rest[4], name: "height")
            target = .region(CGRect(x: x, y: y, width: w, height: h))
            rest = Array(rest.dropFirst(5))
        }
        guard rest.count == 1 else {
            throw CUAError(message: "usage: macos-cua screenshot [--screen] [--region x y w h] <path.png>")
        }
        let payload = try ScreenshotSupport.capture(target: target, path: rest[0])
        let image = payload["image"] as? [String: Any]
        let bounds = payload["bounds"] as? [String: Any]
        let human = "captured \(payload["target"] as? String ?? "screenshot") to \(rest[0]) (\(image?["width"] ?? "?")x\(image?["height"] ?? "?"), bounds \(bounds?["x"] ?? "?"),\(bounds?["y"] ?? "?") \(bounds?["width"] ?? "?")x\(bounds?["height"] ?? "?"))"
        try output.emit(payload, human: human)
    }

    static func move(args: [String], output: CLIOutput) throws {
        let (rest, profile) = try parsePointerProfile(args, usage: "usage: macos-cua move <x> <y> [--fast|--precise]")
        guard rest.count == 2 else {
            throw CUAError(message: "usage: macos-cua move <x> <y> [--fast|--precise]")
        }
        let x = try parseInt(rest[0], name: "x")
        let y = try parseInt(rest[1], name: "y")
        _ = try InputSupport.performMotion(to: CGPoint(x: x, y: y), profile: profile, kind: .move)
        try output.emit(
            ["x": x, "y": y, "profile": profile.rawValue],
            human: "moved pointer to \(x),\(y) [\(profile.rawValue)]"
        )
    }

    static func click(args: [String], output: CLIOutput, count: Int) throws {
        let usage = "usage: macos-cua \(count == 1 ? "click" : "double-click") <x> <y> [left|right|middle] [--fast|--precise]"
        let (rest, profile) = try parsePointerProfile(args, usage: usage)
        guard (2...3).contains(rest.count) else {
            throw CUAError(message: usage)
        }
        let x = try parseInt(rest[0], name: "x")
        let y = try parseInt(rest[1], name: "y")
        let button = try InputSupport.mouseButton(named: rest.count == 3 ? rest[2] : "left")
        try InputSupport.click(point: CGPoint(x: x, y: y), button: button, count: count, profile: profile)
        try output.emit(
            ["x": x, "y": y, "button": button.rawValue, "count": count, "profile": profile.rawValue],
            human: "\(count == 1 ? "clicked" : "double-clicked") \(button.rawValue) at \(x),\(y) [\(profile.rawValue)]"
        )
    }

    static func scroll(args: [String], output: CLIOutput) throws {
        guard args.count == 2 else {
            throw CUAError(message: "usage: macos-cua scroll <dx> <dy>")
        }
        let dx = try parseInt(args[0], name: "dx")
        let dy = try parseInt(args[1], name: "dy")
        try InputSupport.scroll(dx: dx, dy: dy)
        try output.emit(["dx": dx, "dy": dy], human: "scrolled \(dx),\(dy)")
    }

    static func keypress(args: [String], output: CLIOutput) throws {
        guard args.count == 1 else {
            throw CUAError(message: "usage: macos-cua keypress <key[+key...]>")
        }
        try InputSupport.keypress(args[0])
        try output.emit(["keys": args[0]], human: "sent keypress: \(args[0])")
    }

    static func typeText(args: [String], output: CLIOutput) throws {
        guard !args.isEmpty else {
            throw CUAError(message: "usage: macos-cua type [--fast] <text>")
        }
        var rest = args
        var fast = false
        if rest.first == "--fast" {
            fast = true
            rest.removeFirst()
        }
        guard rest.count == 1 else {
            throw CUAError(message: "usage: macos-cua type [--fast] <text>")
        }
        try InputSupport.typeText(rest[0], fast: fast)
        try output.emit(["length": rest[0].count, "fast": fast], human: "typed \(rest[0].count) characters")
    }

    static func wait(args: [String], output: CLIOutput) throws {
        guard args.count == 1 else {
            throw CUAError(message: "usage: macos-cua wait <ms>")
        }
        let ms = try parseInt(args[0], name: "ms")
        usleep(useconds_t(ms * 1_000))
        try output.emit(["ms": ms], human: "waited \(ms)ms")
    }

    static func clipboard(args: [String], output: CLIOutput) throws {
        guard let subcommand = args.first else {
            throw CUAError(message: "usage: macos-cua clipboard get|set|copy|paste")
        }
        switch subcommand {
        case "get":
            let text = try ClipboardSupport.getText()
            try output.emit(["text": text], human: text)
        case "set":
            guard args.count == 2 else {
                throw CUAError(message: "usage: macos-cua clipboard set <text>")
            }
            try ClipboardSupport.setText(args[1])
            try output.emit(["ok": true, "length": args[1].count], human: "clipboard updated")
        case "copy":
            try ClipboardSupport.copySelection()
            try output.emit(["ok": true], human: "sent copy shortcut")
        case "paste":
            try ClipboardSupport.pasteClipboard()
            try output.emit(["ok": true], human: "sent paste shortcut")
        default:
            throw CUAError(message: "unsupported clipboard command: \(subcommand)")
        }
    }

    static func app(args: [String], output: CLIOutput) throws {
        guard let subcommand = args.first else {
            throw CUAError(message: "usage: macos-cua app list|frontmost|activate")
        }
        switch subcommand {
        case "list":
            let records = AppSupport.runningUserApplications().map(AppSupport.record(for:))
            try output.emit(
                records.map(\.json),
                lines: records.isEmpty ? ["No running user apps found."] : records.map(\.line)
            )
        case "frontmost":
            let record = AppSupport.frontmostApplication().map(AppSupport.record(for:))
            try output.emit(record?.json as Any, human: record?.line ?? "No frontmost app.")
        case "activate":
            guard args.count >= 2 else {
                throw CUAError(message: "usage: macos-cua app activate <name-or-bundle-id>")
            }
            let query = args.dropFirst().joined(separator: " ")
            let payload = try AppSupport.activate(query: query)
            let record = (payload["app"] as? [String: Any])?["name"] as? String ?? query
            try output.emit(payload, human: "activated app: \(record)")
        default:
            throw CUAError(message: "unsupported app command: \(subcommand)")
        }
    }

    static func window(args: [String], output: CLIOutput) throws {
        guard let subcommand = args.first else {
            throw CUAError(message: "usage: macos-cua window frontmost|list|activate|minimize|maximize|close")
        }
        switch subcommand {
        case "frontmost":
            let record = WindowSupport.frontmostWindow()
            try output.emit(record?.json as Any, human: record?.line ?? "No frontmost window.")
        case "list":
            let windows = WindowSupport.listWindows()
            try output.emit(
                windows.map(\.json),
                lines: windows.isEmpty ? ["No interactive windows found."] : windows.map(\.line)
            )
        case "activate":
            guard args.count == 2 else {
                throw CUAError(message: "usage: macos-cua window activate <id>")
            }
            let id = try parseInt(args[1], name: "window id")
            let payload = try WindowSupport.activateWindow(id: id)
            try output.emit(payload, human: "activated window \(id)")
        case "minimize":
            let payload = try WindowSupport.minimizeFrontmostWindow()
            try output.emit(payload, human: "minimized the frontmost window")
        case "maximize":
            let payload = try WindowSupport.maximizeFrontmostWindow()
            try output.emit(payload, human: "maximized the frontmost window")
        case "close":
            let payload = try WindowSupport.closeFrontmostWindow()
            try output.emit(payload, human: "closed the frontmost window")
        default:
            throw CUAError(message: "unsupported window command: \(subcommand)")
        }
    }

    static func parsePointerProfile(_ args: [String], usage: String) throws -> ([String], PointerMotionProfile) {
        var rest: [String] = []
        var selected: PointerMotionProfile = .fast
        var explicit = false

        for arg in args {
            switch arg {
            case "--fast":
                if explicit && selected != .fast {
                    throw CUAError(message: usage)
                }
                selected = .fast
                explicit = true
            case "--precise":
                if explicit && selected != .precise {
                    throw CUAError(message: usage)
                }
                selected = .precise
                explicit = true
            case "--duration-ms":
                throw CUAError(message: "move --duration-ms has been removed; use --fast or --precise")
            default:
                rest.append(arg)
            }
        }
        return (rest, selected)
    }
}
