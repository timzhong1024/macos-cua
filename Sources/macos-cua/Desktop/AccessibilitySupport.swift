import ApplicationServices
import CoreGraphics
import Foundation

enum AccessibilitySupport {
    private static let maxTreeNodes = 200
    private static let maxTextCandidates = 8
    private static let maxDescendantTextNodes = 24
    private static let maxDescendantTextDepth = 3
    private static let maxParameterizedTextLength = 120
    private static let nearRadius: CGFloat = 50

    private static let actionableRoles: Set<String> = [
        kAXButtonRole as String,
        "AXLink",
        kAXMenuItemRole as String,
        kAXCheckBoxRole as String,
        kAXRadioButtonRole as String,
        kAXPopUpButtonRole as String,
        "AXTabButton",
        kAXDisclosureTriangleRole as String,
    ]

    private static let editableRoles: Set<String> = [
        kAXTextFieldRole as String,
        kAXTextAreaRole as String,
        kAXComboBoxRole as String,
        "AXSearchField",
    ]

    private static let interactiveRoles: Set<String> = actionableRoles.union([
        "AXRow",
        "AXCell",
        "AXOutline",
        "AXList",
        "AXTable",
    ])

    private static let interactiveSubroles: Set<String> = [
        "AXOutlineRow",
    ]

    private static let interactiveActions: Set<String> = [
        kAXPressAction as String,
        "AXShowDefaultUI",
        "AXShowAlternateUI",
    ]

    private static let containerRoles: Set<String> = [
        "AXOutline",
        "AXList",
        "AXTable",
        "AXScrollArea",
        "AXCollection",
        "AXBrowser",
    ]

    private static let feedbackRoleBlacklist: Set<String> = [
        "AXGroup",
        "AXSplitGroup",
        "AXCell",
        "AXWindow",
        "AXApplication",
        "AXScrollArea",
    ]

    private static let parameterizedTextRoles: Set<String> = [
        "AXWebArea",
        "AXTextArea",
        "AXTextField",
        "AXStaticText",
        "AXDocument",
    ]

    struct Snapshot {
        let element: AXUIElement
        let role: String
        let subrole: String?
        let text: String?
        let bounds: CGRect?
        let actionNames: [String]
        let isFocused: Bool
        let isEnabled: Bool?

        var center: CGPoint? {
            guard let bounds else { return nil }
            return CGPoint(x: bounds.midX, y: bounds.midY)
        }

        var isActionable: Bool {
            actionNames.contains(kAXPressAction as String) || actionableRoles.contains(role)
        }

        var isInteractive: Bool {
            !interactiveActions.intersection(actionNames).isEmpty
                || interactiveRoles.contains(role)
                || (subrole.map { interactiveSubroles.contains($0) } ?? false)
        }

        var isStrongInteractive: Bool {
            !interactiveActions.intersection(actionNames).isEmpty
                || isActionable
                || role == "AXRow"
                || subrole == "AXOutlineRow"
                || isEditable
        }

        var isEditable: Bool {
            editableRoles.contains(role) || subrole == "AXSearchField"
        }

        var isContainer: Bool {
            containerRoles.contains(role)
        }
    }

    static func isAvailable() -> Bool {
        WindowSupport.isAccessibilityTrusted()
    }

    static func feedback(for point: CGPoint, resolution: CoordinateResolution) -> [String: Any]? {
        guard isAvailable(),
              let root = WindowSupport.frontmostWindowAXElement() else {
            return nil
        }

        if let hit = element(at: point),
           let lines = feedbackLines(from: hit),
           !lines.isEmpty {
            return ["feedback": lines]
        }

        let candidates = treeSnapshots(root: root, limit: maxTreeNodes)
            .filter { $0.isInteractive }
            .compactMap { snapshot -> (Snapshot, CGFloat)? in
                guard let center = snapshot.center else { return nil }
                let distance = hypot(center.x - point.x, center.y - point.y)
                guard distance <= nearRadius else { return nil }
                return (snapshot, distance)
            }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
                return (lhs.0.text ?? "") < (rhs.0.text ?? "")
            }

        guard candidates.count == 1 else { return nil }

        let candidate = candidates[0]
        guard let center = candidate.0.center,
              let lines = feedbackLines(from: candidate.0.element),
              !lines.isEmpty else {
            return nil
        }

        return [
            "feedback": lines,
            "distance": Int(candidate.1.rounded()),
            "suggestedClick": CoordinateSupport.pointJSON(convert(point: center, resolution: resolution)),
        ]
    }

    static func element(at point: CGPoint) -> AXUIElement? {
        guard isAvailable() else { return nil }
        var hit: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(systemWideElement(), Float(point.x), Float(point.y), &hit)
        guard result == .success else { return nil }
        return hit
    }

    private static func systemWideElement() -> AXUIElement {
        AXUIElementCreateSystemWide()
    }

    private static func treeSnapshots(root: AXUIElement, limit: Int) -> [Snapshot] {
        var results: [Snapshot] = []
        var stack: [AXUIElement] = [root]
        var visited = Set<ObjectIdentifier>()

        while let element = stack.popLast(), results.count < limit {
            let identifier = ObjectIdentifier(element)
            guard visited.insert(identifier).inserted else { continue }
            if let snapshot = snapshot(for: element) {
                results.append(snapshot)
            }
            let children = (WindowSupport.axValue(element, kAXChildrenAttribute as String) as? [AXUIElement]) ?? []
            for child in children.reversed() {
                stack.append(child)
            }
        }

        return results
    }

    private static func snapshot(for element: AXUIElement) -> Snapshot? {
        let role = WindowSupport.axString(element, kAXRoleAttribute as String) ?? "AXUnknown"
        let position = WindowSupport.axPoint(element, kAXPositionAttribute as String)
        let size = WindowSupport.axSize(element, kAXSizeAttribute as String)
        let bounds = position.flatMap { origin in
            size.map { CGSize(width: max($0.width, 0), height: max($0.height, 0)) }.map { CGRect(origin: origin, size: $0) }
        }

        return Snapshot(
            element: element,
            role: role,
            subrole: WindowSupport.axString(element, kAXSubroleAttribute as String),
            text: preferredText(for: element),
            bounds: bounds,
            actionNames: actionNames(for: element),
            isFocused: WindowSupport.axBool(element, kAXFocusedAttribute as String) ?? false,
            isEnabled: WindowSupport.axBool(element, kAXEnabledAttribute as String)
        )
    }

    private static func preferredText(for element: AXUIElement) -> String? {
        candidateTexts(for: element).first
    }

    private static func candidateTexts(for element: AXUIElement) -> [String] {
        var results: [String] = []
        var seen = Set<String>()
        var visited = Set<ObjectIdentifier>()

        collectTextCandidates(
            for: element,
            results: &results,
            seen: &seen,
            visited: &visited,
            maxResults: maxTextCandidates
        )

        return results
    }

    private static func collectTextCandidates(
        for element: AXUIElement,
        results: inout [String],
        seen: inout Set<String>,
        visited: inout Set<ObjectIdentifier>,
        maxResults: Int
    ) {
        guard results.count < maxResults else { return }
        let identifier = ObjectIdentifier(element)
        guard visited.insert(identifier).inserted else { return }

        appendNormalized(
            primaryDirectTextCandidates(for: element),
            to: &results,
            seen: &seen,
            limit: maxResults
        )
        guard results.count < maxResults else { return }

        for attribute in [kAXTitleUIElementAttribute as String, kAXHeaderAttribute as String] {
            guard let related = WindowSupport.axElement(element, attribute) else { continue }
            collectTextCandidates(
                for: related,
                results: &results,
                seen: &seen,
                visited: &visited,
                maxResults: maxResults
            )
            guard results.count < maxResults else { return }
        }

        appendNormalized(
            descendantStaticTexts(for: element, limit: maxResults - results.count),
            to: &results,
            seen: &seen,
            limit: maxResults
        )
        guard results.count < maxResults else { return }

        appendNormalized(
            secondaryDirectTextCandidates(for: element),
            to: &results,
            seen: &seen,
            limit: maxResults
        )
    }

    private static func primaryDirectTextCandidates(for element: AXUIElement) -> [String?] {
        [
            WindowSupport.axString(element, kAXTitleAttribute as String),
            WindowSupport.axString(element, kAXLabelValueAttribute as String),
            stringValue(WindowSupport.axValue(element, kAXValueAttribute as String)),
            WindowSupport.axString(element, kAXPlaceholderValueAttribute as String),
            WindowSupport.axString(element, kAXDescriptionAttribute as String),
            WindowSupport.axString(element, kAXSelectedTextAttribute as String),
            parameterizedText(for: element),
        ]
    }

    private static func secondaryDirectTextCandidates(for element: AXUIElement) -> [String?] {
        [
            WindowSupport.axString(element, kAXHelpAttribute as String),
            WindowSupport.axString(element, kAXRoleDescriptionAttribute as String),
        ]
    }

    private static func descendantStaticTexts(for element: AXUIElement, limit: Int) -> [String] {
        guard limit > 0 else { return [] }
        var results: [String] = []
        var stack: [(AXUIElement, Int)] = [(element, 0)]
        var visited = Set<ObjectIdentifier>()

        while let (current, depth) = stack.popLast(),
              results.count < limit,
              visited.count < maxDescendantTextNodes {
            let identifier = ObjectIdentifier(current)
            guard visited.insert(identifier).inserted else { continue }
            guard depth <= maxDescendantTextDepth else { continue }

            if depth > 0,
               let role = WindowSupport.axString(current, kAXRoleAttribute as String),
               role == kAXStaticTextRole as String,
               let text = primaryDirectTextCandidates(for: current).compactMap(normalizedString).first {
                results.append(text)
            }

            let children = (WindowSupport.axValue(current, kAXChildrenAttribute as String) as? [AXUIElement]) ?? []
            for child in children.reversed() {
                stack.append((child, depth + 1))
            }
        }

        return results
    }

    private static func appendNormalized(
        _ candidates: [String?],
        to results: inout [String],
        seen: inout Set<String>,
        limit: Int
    ) {
        for candidate in candidates {
            guard results.count < limit else { break }
            guard let normalized = normalizedString(candidate) else { continue }
            guard seen.insert(normalized).inserted else { continue }
            results.append(normalized)
        }
    }

    private static func appendNormalized(
        _ candidates: [String],
        to results: inout [String],
        seen: inout Set<String>,
        limit: Int
    ) {
        for candidate in candidates {
            guard results.count < limit else { break }
            guard let normalized = normalizedString(candidate) else { continue }
            guard seen.insert(normalized).inserted else { continue }
            results.append(normalized)
        }
    }

    private static func parameterizedText(for element: AXUIElement) -> String? {
        let role = WindowSupport.axString(element, kAXRoleAttribute as String) ?? ""
        let subrole = WindowSupport.axString(element, kAXSubroleAttribute as String)
        guard parameterizedTextRoles.contains(role) || subrole == "AXSearchField" else {
            return nil
        }

        if let selectedText = normalizedString(WindowSupport.axString(element, kAXSelectedTextAttribute as String)) {
            return selectedText
        }

        if let selectedRange = WindowSupport.axValue(element, kAXSelectedTextRangeAttribute as String),
           let text = parameterizedString(
                for: element,
                attribute: kAXStringForRangeParameterizedAttribute as String,
                parameter: selectedRange
           ) {
            return text
        }

        if let visibleRange = WindowSupport.axValue(element, kAXVisibleCharacterRangeAttribute as String),
           let text = parameterizedString(
                for: element,
                attribute: kAXStringForRangeParameterizedAttribute as String,
                parameter: visibleRange
           ) {
            return text
        }

        return nil
    }

    private static func parameterizedString(for element: AXUIElement, attribute: String, parameter: CFTypeRef) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyParameterizedAttributeValue(
            element,
            attribute as CFString,
            parameter,
            &value
        )
        guard result == .success, let value else { return nil }

        if let string = value as? String {
            return normalizedString(truncateParameterizedText(string))
        }
        if let attributed = value as? NSAttributedString {
            return normalizedString(truncateParameterizedText(attributed.string))
        }
        return nil
    }

    private static func truncateParameterizedText(_ text: String) -> String {
        guard text.count > maxParameterizedTextLength else { return text }
        return String(text.prefix(maxParameterizedTextLength))
    }

    private static func normalizedString(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private static func stringValue(_ value: CFTypeRef?) -> String? {
        guard let value else { return nil }
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        if let bool = value as? Bool { return bool ? "true" : "false" }
        if CFGetTypeID(value) == AXValueGetTypeID() {
            let axValue = unsafeDowncast(value, to: AXValue.self)
            switch AXValueGetType(axValue) {
            case .cfRange:
                var range = CFRange()
                guard AXValueGetValue(axValue, .cfRange, &range) else { return nil }
                return "\(range.location),\(range.length)"
            default:
                return nil
            }
        }
        return nil
    }

    private static func actionNames(for element: AXUIElement) -> [String] {
        var names: CFArray?
        let result = AXUIElementCopyActionNames(element, &names)
        guard result == .success, let array = names as? [String] else { return [] }
        return array
    }

    private static func convert(point: CGPoint, resolution: CoordinateResolution) -> CGPoint {
        switch resolution.coordinateSpace {
        case .screen:
            return point
        case .window:
            return resolution.localPointer(fromScreenPoint: point) ?? point
        }
    }

    private static func feedbackLines(from element: AXUIElement) -> [String]? {
        let path = ancestorSnapshots(from: element, limit: 10)
        guard !path.isEmpty else { return nil }

        let inheritedText = nearestText(in: path)
        var lines: [String] = []
        var seen = Set<String>()

        for (index, snapshot) in path.enumerated() {
            guard shouldIncludeFeedbackSnapshot(snapshot, isHitNode: index == 0) else { continue }
            let line = formatFeedbackPathLine(snapshot: snapshot, inheritedText: inheritedText)
            guard seen.insert(line).inserted else { continue }
            lines.append(line)
            if lines.count == 3 { break }
        }

        return lines.isEmpty ? nil : lines
    }

    private static func ancestorSnapshots(from element: AXUIElement, limit: Int) -> [Snapshot] {
        var results: [Snapshot] = []
        var current: AXUIElement? = element
        var steps = 0

        while let currentElement = current, steps < limit {
            if let snapshot = snapshot(for: currentElement) {
                results.append(snapshot)
            }
            current = WindowSupport.axElement(currentElement, kAXParentAttribute)
            steps += 1
        }

        return results
    }

    private static func nearestText(in path: [Snapshot]) -> String? {
        path.lazy.compactMap(\.text).first
    }

    private static func shouldIncludeFeedbackSnapshot(_ snapshot: Snapshot, isHitNode: Bool) -> Bool {
        if isHitNode {
            if snapshot.text != nil { return true }
            if snapshot.isEditable || snapshot.isStrongInteractive { return true }
            return !feedbackRoleBlacklist.contains(snapshot.role)
        }

        if snapshot.isContainer {
            return !feedbackRoleBlacklist.contains(snapshot.role)
        }

        if feedbackRoleBlacklist.contains(snapshot.role) {
            return false
        }

        if snapshot.text != nil { return true }
        return snapshot.isEditable || snapshot.isStrongInteractive
    }

    private static func formatFeedbackPathLine(snapshot: Snapshot, inheritedText: String?) -> String {
        var line = snapshot.role
        if let subrole = snapshot.subrole, !subrole.isEmpty {
            line += "/\(subrole)"
        }

        let text = snapshot.text ?? inheritedText
        if let text, shouldIncludeTextInFeedback(snapshot: snapshot) {
            line += " \"\(truncate(text, limit: 30))\""
        }

        let actions = snapshot.actionNames.filter { interactiveActions.contains($0) }
        if !actions.isEmpty {
            line += " actions=" + actions.prefix(2).joined(separator: ",")
        }

        return line
    }

    private static func shouldIncludeTextInFeedback(snapshot: Snapshot) -> Bool {
        if snapshot.text != nil { return true }
        if snapshot.isContainer { return false }
        return snapshot.isInteractive
    }

    private static func truncate(_ value: String, limit: Int) -> String {
        guard value.count > limit else { return value }
        return String(value.prefix(max(0, limit - 1))) + "…"
    }
}
