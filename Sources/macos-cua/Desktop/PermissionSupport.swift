import AppKit
import ApplicationServices
import CoreGraphics
import Darwin
import Foundation

enum PermissionKind: String, CaseIterable {
    case accessibility
    case screenRecording

    var displayName: String {
        switch self {
        case .accessibility:
            return "Accessibility"
        case .screenRecording:
            return "Screen Recording"
        }
    }

    var settingsURL: URL? {
        switch self {
        case .accessibility:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        case .screenRecording:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
        }
    }

    var onboardingHint: String {
        switch self {
        case .accessibility:
            return "Enable Accessibility for `macos-cua`, `swift`, or the terminal/agent host that launched this process."
        case .screenRecording:
            return "Enable Screen Recording for the app that launched this process. On some macOS setups you need to fully quit and relaunch that app after enabling it."
        }
    }

    var requiredFor: String {
        switch self {
        case .accessibility:
            return "synthetic input and advanced window actions"
        case .screenRecording:
            return "screenshots"
        }
    }
}

struct PermissionAttempt {
    let kind: PermissionKind
    let initiallyGranted: Bool
    var granted: Bool
    var requestedPrompt: Bool = false
    var openedSettings: Bool = false
    var waited: Bool = false
    var json: [String: Any] {
        [
            "granted": granted,
            "initiallyGranted": initiallyGranted,
            "requestedPrompt": requestedPrompt,
            "openedSettings": openedSettings,
            "settingsURL": kind.settingsURL?.absoluteString as Any,
        ]
    }
}

struct OnboardingResult {
    let payload: [String: Any]
    let lines: [String]
}

enum PermissionSupport {
    static func isInteractiveSession() -> Bool {
        isatty(STDIN_FILENO) == 1 && isatty(STDOUT_FILENO) == 1
    }

    static func isGranted(_ kind: PermissionKind) -> Bool {
        switch kind {
        case .accessibility:
            return AXIsProcessTrusted()
        case .screenRecording:
            if #available(macOS 10.15, *) {
                return CGPreflightScreenCaptureAccess()
            }
            return true
        }
    }

    @discardableResult
    static func requestPrompt(for kind: PermissionKind) -> Bool {
        switch kind {
        case .accessibility:
            let promptKey = "AXTrustedCheckOptionPrompt" as CFString
            let options = [promptKey: true] as CFDictionary
            return AXIsProcessTrustedWithOptions(options)
        case .screenRecording:
            if #available(macOS 10.15, *) {
                return CGRequestScreenCaptureAccess()
            }
            return true
        }
    }

    @discardableResult
    static func openSettings(for kind: PermissionKind) -> Bool {
        guard let url = kind.settingsURL else { return false }
        return NSWorkspace.shared.open(url)
    }

    static func require(_ kind: PermissionKind, for capability: String? = nil) throws {
        guard isGranted(kind) else {
            let detail = capability ?? kind.requiredFor
            throw CUAError(message: "\(kind.displayName) permission is required for \(detail). Run `macos-cua onboard`.")
        }
    }

    static func onboarding(
        requestPrompts: Bool,
        openSettingsPane: Bool,
        waitForReady: Bool,
        timeoutSeconds: Int,
        log: ((String) -> Void)? = nil
    ) -> OnboardingResult {
        var attempts = Dictionary(uniqueKeysWithValues: PermissionKind.allCases.map { kind in
            let granted = isGranted(kind)
            return (kind, PermissionAttempt(kind: kind, initiallyGranted: granted, granted: granted))
        })

        let initialMissing = PermissionKind.allCases.filter { !(attempts[$0]?.granted ?? false) }
        guard !initialMissing.isEmpty else {
            return composeResult(
                attempts: attempts,
                interactive: isInteractiveSession(),
                waitForReady: waitForReady,
                timeoutSeconds: timeoutSeconds
            )
        }

        let deadline = Date().addingTimeInterval(TimeInterval(max(0, timeoutSeconds)))

        // Phase 1: trigger prompts and open settings for all missing permissions before waiting.
        for kind in PermissionKind.allCases {
            guard var attempt = attempts[kind], !attempt.granted else { continue }

            if requestPrompts {
                log?("Requesting \(kind.displayName) permission...")
                attempt.requestedPrompt = true
                _ = requestPrompt(for: kind)
                attempt.granted = isGranted(kind)
            }

            if !attempt.granted && openSettingsPane {
                log?("Opening System Settings for \(kind.displayName)...")
                attempt.openedSettings = openSettings(for: kind)
            }

            attempts[kind] = attempt
        }

        // Phase 2: poll all still-missing permissions together so the timeout is shared, not
        // consumed sequentially (which would starve later permissions of wait time).
        if waitForReady {
            let toWait = PermissionKind.allCases.filter { !(attempts[$0]?.granted ?? false) }
            if !toWait.isEmpty {
                for kind in toWait { attempts[kind]?.waited = true }
                log?("Waiting for: \(toWait.map(\.displayName).joined(separator: ", "))...")
                while Date() < deadline {
                    var allGranted = true
                    for kind in toWait {
                        if isGranted(kind) {
                            attempts[kind]?.granted = true
                        }
                        if !(attempts[kind]?.granted ?? false) { allGranted = false }
                    }
                    if allGranted { break }
                    usleep(500_000)
                }
            }
        }

        for kind in PermissionKind.allCases {
            if var attempt = attempts[kind] {
                attempt.granted = isGranted(kind)
                attempts[kind] = attempt
            }
        }

        return composeResult(
            attempts: attempts,
            interactive: isInteractiveSession(),
            waitForReady: waitForReady,
            timeoutSeconds: timeoutSeconds
        )
    }

    static func composeResult(
        attempts: [PermissionKind: PermissionAttempt],
        interactive: Bool,
        waitForReady: Bool,
        timeoutSeconds: Int
    ) -> OnboardingResult {
        let accessibility = attempts[.accessibility] ?? PermissionAttempt(kind: .accessibility, initiallyGranted: false, granted: false)
        let screenRecording = attempts[.screenRecording] ?? PermissionAttempt(kind: .screenRecording, initiallyGranted: false, granted: false)
        let allReady = accessibility.granted && screenRecording.granted
        let missing = PermissionKind.allCases.filter { !(attempts[$0]?.granted ?? false) }

        var nextSteps: [String] = []
        if missing.contains(.accessibility) {
            nextSteps.append(PermissionKind.accessibility.onboardingHint)
        }
        if missing.contains(.screenRecording) {
            nextSteps.append(PermissionKind.screenRecording.onboardingHint)
        }
        if !missing.isEmpty {
            nextSteps.append("Rerun `macos-cua onboard --wait` or `macos-cua doctor` after granting the missing permissions.")
        }

        var lines: [String] = [
            "Session mode: \(interactive ? "tty" : "non-tty")",
            "Accessibility: \(statusLine(for: accessibility))",
            "Screen Recording: \(statusLine(for: screenRecording))",
        ]
        if waitForReady {
            lines.append("Wait mode: enabled (\(timeoutSeconds)s timeout)")
        }
        if allReady {
            lines.append("Onboarding: ready")
        } else {
            lines.append("Onboarding: incomplete")
            lines.append(contentsOf: nextSteps.map { "Next: \($0)" })
        }

        return OnboardingResult(
            payload: [
                "allReady": allReady,
                "interactive": interactive,
                "waitForReady": waitForReady,
                "timeoutSeconds": timeoutSeconds,
                "permissions": [
                    PermissionKind.accessibility.rawValue: accessibility.json,
                    PermissionKind.screenRecording.rawValue: screenRecording.json,
                ],
                "nextSteps": nextSteps,
            ],
            lines: lines
        )
    }

    static func statusLine(for attempt: PermissionAttempt) -> String {
        var details: [String] = [attempt.granted ? "ready" : "missing"]
        if attempt.requestedPrompt {
            details.append("prompted")
        }
        if attempt.openedSettings {
            details.append("settings-opened")
        }
        if attempt.waited {
            details.append("waited")
        }
        return details.joined(separator: ", ")
    }
}
