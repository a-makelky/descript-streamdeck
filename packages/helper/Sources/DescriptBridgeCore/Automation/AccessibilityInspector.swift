import ApplicationServices
import Foundation

struct AccessibilityWindowSnapshot {
    let title: String
    let role: String
    let buttons: [String]
    let elements: [AccessibilityElementSnapshot]
}

struct AccessibilityElementSnapshot {
    let role: String
    let label: String
    let depth: Int
}

enum MatchPreference {
    case first
    case deepest
}

enum ActivationMethod {
    case press
    case click
}

private struct MatchedElement {
    let element: AXUIElement
    let depth: Int
}

final class AccessibilityInspector {
    private let maxDepth = 20
    private let maxInterestingElements = 80

    func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    func requestTrustPrompt() -> Bool {
        let options = [
            "AXTrustedCheckOptionPrompt": true
        ] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func captureWindowSnapshots(pid: pid_t) -> [AccessibilityWindowSnapshot] {
        let appElement = AXUIElementCreateApplication(pid)
        guard let windows = copyAttribute(appElement, attribute: kAXWindowsAttribute as String) as? [AXUIElement] else {
            return []
        }

        return windows.map { window in
            let title = (copyAttribute(window, attribute: kAXTitleAttribute as String) as? String) ?? ""
            let role = (copyAttribute(window, attribute: kAXRoleAttribute as String) as? String) ?? "AXUnknown"
            let buttons = collectButtons(from: window, depth: 0)
            let elements = collectInterestingElements(from: window, depth: 0)
            return AccessibilityWindowSnapshot(
                title: title,
                role: role,
                buttons: buttons,
                elements: elements
            )
        }
    }

    func clickFirstButton(
        matching labels: [String],
        pid: pid_t,
        method: ActivationMethod = .press,
        preference: MatchPreference = .first
    ) -> Bool {
        activateFirstElement(
            matching: labels,
            roles: [kAXButtonRole as String],
            pid: pid,
            method: method,
            preference: preference
        )
    }

    func clickFirstControl(
        matching labels: [String],
        pid: pid_t,
        method: ActivationMethod = .press,
        preference: MatchPreference = .first
    ) -> Bool {
        activateFirstElement(
            matching: labels,
            roles: interestingControlRoles,
            pid: pid,
            method: method,
            preference: preference
        )
    }

    func clickFirstElement(
        matching labels: [String],
        roles: Set<String>,
        pid: pid_t,
        preference: MatchPreference = .first
    ) -> Bool {
        activateFirstElement(
            matching: labels,
            roles: roles,
            pid: pid,
            method: .click,
            preference: preference
        )
    }

    func containsElement(
        matching labels: [String],
        roles: Set<String>,
        pid: pid_t
    ) -> Bool {
        findMatchingElement(
            matching: labels,
            roles: roles,
            pid: pid,
            preference: .first
        ) != nil
    }

    func focusFirstElement(
        matching labels: [String],
        roles: Set<String>,
        pid: pid_t,
        preference: MatchPreference = .first
    ) -> Bool {
        guard let match = findMatchingElement(
            matching: labels,
            roles: roles,
            pid: pid,
            preference: preference
        ) else {
            return false
        }

        return AXUIElementSetAttributeValue(
            match.element,
            kAXFocusedAttribute as CFString,
            kCFBooleanTrue
        ) == .success
    }

    private func collectButtons(from element: AXUIElement, depth: Int) -> [String] {
        guard depth <= maxDepth else {
            return []
        }

        var buttons: [String] = []
        if let role = copyAttribute(element, attribute: kAXRoleAttribute as String) as? String,
           role == kAXButtonRole as String,
           let label = firstNonEmptyLabel(for: element)
        {
            buttons.append(label)
        }

        if let children = copyAttribute(element, attribute: kAXChildrenAttribute as String) as? [AXUIElement] {
            for child in children {
                buttons.append(contentsOf: collectButtons(from: child, depth: depth + 1))
            }
        }

        return buttons
    }

    private func collectInterestingElements(
        from element: AXUIElement,
        depth: Int
    ) -> [AccessibilityElementSnapshot] {
        guard depth <= maxDepth else {
            return []
        }

        var elements: [AccessibilityElementSnapshot] = []
        if let role = copyAttribute(element, attribute: kAXRoleAttribute as String) as? String,
           let label = firstInterestingLabel(for: element)
        {
            elements.append(
                AccessibilityElementSnapshot(
                    role: role,
                    label: label,
                    depth: depth
                )
            )
        }

        if elements.count >= maxInterestingElements {
            return Array(elements.prefix(maxInterestingElements))
        }

        if let children = copyAttribute(element, attribute: kAXChildrenAttribute as String) as? [AXUIElement] {
            for child in children {
                elements.append(contentsOf: collectInterestingElements(from: child, depth: depth + 1))
                if elements.count >= maxInterestingElements {
                    return Array(elements.prefix(maxInterestingElements))
                }
            }
        }

        return elements
    }

    private func activateFirstElement(
        matching labels: [String],
        roles: Set<String>,
        pid: pid_t,
        method: ActivationMethod,
        preference: MatchPreference
    ) -> Bool {
        guard let match = findMatchingElement(
            matching: labels,
            roles: roles,
            pid: pid,
            preference: preference
        ) else {
            return false
        }

        switch method {
        case .press:
            return AXUIElementPerformAction(
                match.element,
                kAXPressAction as CFString
            ) == .success
        case .click:
            return clickElement(match.element)
        }
    }

    private func findMatchingElement(
        matching labels: [String],
        roles: Set<String>,
        pid: pid_t,
        preference: MatchPreference
    ) -> MatchedElement? {
        let normalizedLabels = Set(labels.map(normalize))
        let appElement = AXUIElementCreateApplication(pid)
        guard let windows = copyAttribute(
            appElement,
            attribute: kAXWindowsAttribute as String
        ) as? [AXUIElement] else {
            return nil
        }

        var matches: [MatchedElement] = []
        for window in windows {
            collectMatches(
                from: window,
                labels: normalizedLabels,
                roles: roles,
                depth: 0,
                into: &matches
            )
        }

        switch preference {
        case .first:
            return matches.first
        case .deepest:
            return matches.max(by: { $0.depth < $1.depth })
        }
    }

    private func collectMatches(
        from element: AXUIElement,
        labels: Set<String>,
        roles: Set<String>,
        depth: Int,
        into matches: inout [MatchedElement]
    ) {
        guard depth <= maxDepth else {
            return
        }

        if let role = copyAttribute(element, attribute: kAXRoleAttribute as String) as? String,
           roles.contains(role),
           let label = firstInterestingLabel(for: element),
           labels.contains(normalize(label))
        {
            matches.append(MatchedElement(element: element, depth: depth))
        }

        if let children = copyAttribute(element, attribute: kAXChildrenAttribute as String) as? [AXUIElement] {
            for child in children {
                collectMatches(
                    from: child,
                    labels: labels,
                    roles: roles,
                    depth: depth + 1,
                    into: &matches
                )
            }
        }
    }

    private func firstNonEmptyLabel(for element: AXUIElement) -> String? {
        let candidates = [
            copyAttribute(element, attribute: kAXTitleAttribute as String) as? String,
            copyAttribute(element, attribute: kAXDescriptionAttribute as String) as? String,
            copyAttribute(element, attribute: kAXHelpAttribute as String) as? String
        ]

        return candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })
    }

    private func firstInterestingLabel(for element: AXUIElement) -> String? {
        let candidates: [String?] = [
            copyAttribute(element, attribute: kAXTitleAttribute as String) as? String,
            copyAttribute(element, attribute: kAXDescriptionAttribute as String) as? String,
            copyAttribute(element, attribute: kAXHelpAttribute as String) as? String,
            copyAttribute(element, attribute: kAXValueAttribute as String) as? String
        ]

        for candidate in candidates {
            guard let text = candidate?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
                continue
            }

            return text
        }

        return nil
    }

    private let interestingControlRoles: Set<String> = [
        kAXButtonRole as String,
        kAXPopUpButtonRole as String,
        kAXMenuButtonRole as String
    ]

    private func copyAttribute(
        _ element: AXUIElement,
        attribute: String
    ) -> CFTypeRef? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            attribute as CFString,
            &value
        )

        guard result == .success else {
            return nil
        }

        return value
    }

    private func clickElement(_ element: AXUIElement) -> Bool {
        guard let position = point(from: copyAttribute(element, attribute: kAXPositionAttribute as String)),
              let size = size(from: copyAttribute(element, attribute: kAXSizeAttribute as String))
        else {
            return false
        }

        let center = CGPoint(
            x: position.x + (size.width / 2),
            y: position.y + (size.height / 2)
        )

        return postMouseClick(at: center)
    }

    private func point(from value: CFTypeRef?) -> CGPoint? {
        guard let value else {
            return nil
        }

        let axValue = unsafeDowncast(value as AnyObject, to: AXValue.self)
        guard AXValueGetType(axValue) == .cgPoint else {
            return nil
        }

        var point = CGPoint.zero
        return AXValueGetValue(axValue, .cgPoint, &point) ? point : nil
    }

    private func size(from value: CFTypeRef?) -> CGSize? {
        guard let value else {
            return nil
        }

        let axValue = unsafeDowncast(value as AnyObject, to: AXValue.self)
        guard AXValueGetType(axValue) == .cgSize else {
            return nil
        }

        var size = CGSize.zero
        return AXValueGetValue(axValue, .cgSize, &size) ? size : nil
    }

    private func postMouseClick(at point: CGPoint) -> Bool {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let move = CGEvent(
            mouseEventSource: source,
            mouseType: .mouseMoved,
            mouseCursorPosition: point,
            mouseButton: .left
        ),
        let down = CGEvent(
            mouseEventSource: source,
            mouseType: .leftMouseDown,
            mouseCursorPosition: point,
            mouseButton: .left
        ),
        let up = CGEvent(
            mouseEventSource: source,
            mouseType: .leftMouseUp,
            mouseCursorPosition: point,
            mouseButton: .left
        ) else {
            return false
        }

        move.post(tap: .cghidEventTap)
        usleep(120_000)
        down.post(tap: .cghidEventTap)
        usleep(80_000)
        up.post(tap: .cghidEventTap)
        return true
    }

    private func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "…", with: "")
    }
}
