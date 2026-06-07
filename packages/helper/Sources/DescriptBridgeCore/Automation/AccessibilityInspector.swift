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

private struct FramedElement {
    let element: AXUIElement
    let role: String
    let label: String?
    let frame: CGRect
}

final class AccessibilityInspector {
    private let maxDepth = 30
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
        preference: MatchPreference = .first,
        preferredWindowTitles: [String] = []
    ) -> Bool {
        activateFirstElement(
            matching: labels,
            roles: [kAXButtonRole as String],
            pid: pid,
            method: method,
            preference: preference,
            preferredWindowTitles: preferredWindowTitles
        )
    }

    func clickFirstControl(
        matching labels: [String],
        pid: pid_t,
        method: ActivationMethod = .press,
        preference: MatchPreference = .first,
        preferredWindowTitles: [String] = []
    ) -> Bool {
        activateFirstElement(
            matching: labels,
            roles: interestingControlRoles,
            pid: pid,
            method: method,
            preference: preference,
            preferredWindowTitles: preferredWindowTitles
        )
    }

    func clickFirstElement(
        matching labels: [String],
        roles: Set<String>,
        pid: pid_t,
        preference: MatchPreference = .first,
        preferredWindowTitles: [String] = []
    ) -> Bool {
        activateFirstElement(
            matching: labels,
            roles: roles,
            pid: pid,
            method: .click,
            preference: preference,
            preferredWindowTitles: preferredWindowTitles
        )
    }

    func clickSiblingBeforeElement(
        matching labels: [String],
        roles: Set<String>,
        pid: pid_t,
        siblingRoles: Set<String> = [kAXButtonRole as String],
        method: ActivationMethod = .click
    ) -> Bool {
        let normalizedLabels = Set(labels.map(normalize))
        let appElement = AXUIElementCreateApplication(pid)
        guard let windows = copyAttribute(
            appElement,
            attribute: kAXWindowsAttribute as String
        ) as? [AXUIElement] else {
            return false
        }

        for window in windows {
            guard let match = findSiblingBeforeMatch(
                in: window,
                labels: normalizedLabels,
                roles: roles,
                siblingRoles: siblingRoles,
                depth: 0
            ) else {
                continue
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

        return false
    }

    func clickInteractiveElementBetween(
        leftLabels: [String],
        rightLabels: [String],
        pid: pid_t,
        allowedRoles: Set<String> = [kAXButtonRole as String, kAXPopUpButtonRole as String]
    ) -> Bool {
        let appElement = AXUIElementCreateApplication(pid)
        guard let windows = copyAttribute(
            appElement,
            attribute: kAXWindowsAttribute as String
        ) as? [AXUIElement] else {
            return false
        }

        let normalizedLeftLabels = Set(leftLabels.map(normalize))
        let normalizedRightLabels = Set(rightLabels.map(normalize))

        var interactiveElements: [FramedElement] = []
        for window in windows {
            collectFramedElements(
                from: window,
                allowedRoles: allowedRoles,
                depth: 0,
                into: &interactiveElements
            )
        }

        guard
            let left = interactiveElements.first(where: {
                guard let label = $0.label else { return false }
                return normalizedLeftLabels.contains(normalize(label))
            }),
            let right = interactiveElements.first(where: {
                guard let label = $0.label else { return false }
                return normalizedRightLabels.contains(normalize(label))
            })
        else {
            return false
        }

        let minX = min(left.frame.maxX, right.frame.maxX)
        let maxX = max(left.frame.minX, right.frame.minX)
        let referenceY = (left.frame.midY + right.frame.midY) / 2

        let candidates = interactiveElements.filter { candidate in
            let centerX = candidate.frame.midX
            let centerY = candidate.frame.midY
            let normalizedLabel = candidate.label.map(normalize)
            let isKnownAnchor = normalizedLabel.map {
                normalizedLeftLabels.contains($0) || normalizedRightLabels.contains($0)
            } ?? false

            return !isKnownAnchor
                && centerX > minX
                && centerX < maxX
                && abs(centerY - referenceY) <= 24
        }

        guard let target = candidates.sorted(by: {
            abs($0.frame.midX - ((left.frame.midX + right.frame.midX) / 2))
                < abs($1.frame.midX - ((left.frame.midX + right.frame.midX) / 2))
        }).first else {
            return false
        }

        return clickElement(target.element)
    }

    func clickRecorderTimerButton(pid: pid_t) -> Bool {
        let appElement = AXUIElementCreateApplication(pid)
        guard let windows = copyAttribute(
            appElement,
            attribute: kAXWindowsAttribute as String
        ) as? [AXUIElement] else {
            return false
        }

        for window in windows {
            var controls: [FramedElement] = []
            collectFramedElements(
                from: window,
                allowedRoles: [kAXButtonRole as String, kAXPopUpButtonRole as String],
                depth: 0,
                into: &controls
            )

            let recorderAnchors = controls.filter { control in
                guard let label = control.label else {
                    return false
                }

                return recorderAnchorLabels.contains(normalize(label))
            }

            guard let recorderRowMidY = recorderAnchors.map(\.frame.midY).max() else {
                continue
            }

            let recorderRow = controls.filter {
                abs($0.frame.midY - recorderRowMidY) <= 16
            }

            let recorderButtons = recorderRow.filter {
                $0.role == kAXButtonRole as String
            }

            let knownActionRightEdge = recorderButtons
                .filter { button in
                    guard let label = button.label else {
                        return false
                    }

                    return recorderActionLabels.contains(normalize(label))
                }
                .map(\.frame.maxX)
                .max() ?? recorderRow.map(\.frame.minX).min() ?? 0

            let teleprompterLeftEdge = recorderRow
                .filter { control in
                    guard let label = control.label else {
                        return false
                    }

                    return normalize(label) == "teleprompter"
                }
                .map(\.frame.minX)
                .min()

            let settingsLeftEdge = recorderRow
                .filter { control in
                    guard let label = control.label else {
                        return false
                    }

                    return normalize(label) == "recorder settings"
                }
                .map(\.frame.minX)
                .min()

            let rightBoundary = teleprompterLeftEdge ?? settingsLeftEdge ?? .greatestFiniteMagnitude

            let timerButtons = recorderButtons.filter { button in
                guard let label = button.label else {
                    return false
                }

                return isRecorderTimerLabel(label)
                    && button.frame.minX >= knownActionRightEdge - 8
                    && button.frame.maxX <= rightBoundary + 8
                    && button.frame.width >= 48
                    && button.frame.height >= 24
            }

            if let target = timerButtons.max(by: {
                if $0.frame.width == $1.frame.width {
                    return $0.frame.maxX < $1.frame.maxX
                }
                return $0.frame.width < $1.frame.width
            }) {
                return clickElement(target.element)
            }

            let fallbackButtons = recorderButtons.filter { button in
                let normalizedLabel = button.label.map(normalize)
                let isKnownControl = normalizedLabel.map {
                    recorderAnchorLabels.contains($0)
                } ?? false

                return !isKnownControl
                    && button.frame.minX >= knownActionRightEdge - 8
                    && button.frame.maxX <= rightBoundary + 8
                    && button.frame.width >= 48
                    && button.frame.height >= 24
            }

            if let target = fallbackButtons.max(by: {
                if $0.frame.width == $1.frame.width {
                    return $0.frame.maxX < $1.frame.maxX
                }
                return $0.frame.width < $1.frame.width
            }) {
                return clickElement(target.element)
            }
        }

        return false
    }

    func clickRecorderDockPrimaryButton(pid: pid_t) -> Bool {
        let appElement = AXUIElementCreateApplication(pid)
        guard let windows = copyAttribute(
            appElement,
            attribute: kAXWindowsAttribute as String
        ) as? [AXUIElement] else {
            return false
        }

        for window in windows {
            let title = (copyAttribute(window, attribute: kAXTitleAttribute as String) as? String) ?? ""
            guard normalize(title) == "descript recorder" else {
                continue
            }

            var buttons: [FramedElement] = []
            collectFramedElements(
                from: window,
                allowedRoles: [kAXButtonRole as String],
                depth: 0,
                into: &buttons
            )

            let unlabeledCandidates = buttons.filter { button in
                let hasLabel = button.label.map { !normalize($0).isEmpty } ?? false
                return !hasLabel
                    && button.frame.width >= 24
                    && button.frame.width <= 96
                    && button.frame.height >= 24
                    && button.frame.height <= 96
            }

            if let target = unlabeledCandidates.max(by: {
                let leftArea = $0.frame.width * $0.frame.height
                let rightArea = $1.frame.width * $1.frame.height
                if leftArea == rightArea {
                    return $0.frame.midY < $1.frame.midY
                }
                return leftArea < rightArea
            }) {
                return clickElement(target.element)
            }

            if let frame = frame(for: window) {
                return postMouseClick(
                    at: CGPoint(
                        x: frame.midX,
                        y: frame.minY + (frame.height * 0.72)
                    )
                )
            }
        }

        return false
    }

    func containsElement(
        matching labels: [String],
        roles: Set<String>,
        pid: pid_t,
        preferredWindowTitles: [String] = []
    ) -> Bool {
        findMatchingElement(
            matching: labels,
            roles: roles,
            pid: pid,
            preference: .first,
            preferredWindowTitles: preferredWindowTitles
        ) != nil
    }

    func focusFirstElement(
        matching labels: [String],
        roles: Set<String>,
        pid: pid_t,
        preference: MatchPreference = .first,
        preferredWindowTitles: [String] = []
    ) -> Bool {
        guard let match = findMatchingElement(
            matching: labels,
            roles: roles,
            pid: pid,
            preference: preference,
            preferredWindowTitles: preferredWindowTitles
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
        preference: MatchPreference,
        preferredWindowTitles: [String]
    ) -> Bool {
        guard let match = findMatchingElement(
            matching: labels,
            roles: roles,
            pid: pid,
            preference: preference,
            preferredWindowTitles: preferredWindowTitles
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
        preference: MatchPreference,
        preferredWindowTitles: [String]
    ) -> MatchedElement? {
        let normalizedLabels = Set(labels.map(normalize))
        let normalizedPreferredTitles = Set(preferredWindowTitles.map(normalize))
        let appElement = AXUIElementCreateApplication(pid)
        guard let windows = copyAttribute(
            appElement,
            attribute: kAXWindowsAttribute as String
        ) as? [AXUIElement] else {
            return nil
        }

        var matches: [MatchedElement] = []
        let orderedWindows = windows.sorted { left, right in
            let leftTitle = normalize(
                (copyAttribute(left, attribute: kAXTitleAttribute as String) as? String) ?? ""
            )
            let rightTitle = normalize(
                (copyAttribute(right, attribute: kAXTitleAttribute as String) as? String) ?? ""
            )
            let leftPreferred = normalizedPreferredTitles.contains(leftTitle)
            let rightPreferred = normalizedPreferredTitles.contains(rightTitle)

            if leftPreferred != rightPreferred {
                return leftPreferred && !rightPreferred
            }

            return false
        }

        for window in orderedWindows {
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

    private func findSiblingBeforeMatch(
        in element: AXUIElement,
        labels: Set<String>,
        roles: Set<String>,
        siblingRoles: Set<String>,
        depth: Int
    ) -> MatchedElement? {
        guard depth <= maxDepth else {
            return nil
        }

        if let children = copyAttribute(
            element,
            attribute: kAXChildrenAttribute as String
        ) as? [AXUIElement] {
            for (index, child) in children.enumerated() {
                if let role = copyAttribute(child, attribute: kAXRoleAttribute as String) as? String,
                   roles.contains(role),
                   let label = firstInterestingLabel(for: child),
                   labels.contains(normalize(label))
                {
                    for siblingIndex in stride(from: index - 1, through: 0, by: -1) {
                        let sibling = children[siblingIndex]
                        guard let siblingRole = copyAttribute(
                            sibling,
                            attribute: kAXRoleAttribute as String
                        ) as? String,
                        siblingRoles.contains(siblingRole) else {
                            continue
                        }

                        return MatchedElement(
                            element: sibling,
                            depth: depth + 1
                        )
                    }
                }
            }

            for child in children {
                if let match = findSiblingBeforeMatch(
                    in: child,
                    labels: labels,
                    roles: roles,
                    siblingRoles: siblingRoles,
                    depth: depth + 1
                ) {
                    return match
                }
            }
        }

        return nil
    }

    private func collectFramedElements(
        from element: AXUIElement,
        allowedRoles: Set<String>,
        depth: Int,
        into elements: inout [FramedElement]
    ) {
        guard depth <= maxDepth else {
            return
        }

        if let role = copyAttribute(element, attribute: kAXRoleAttribute as String) as? String,
           allowedRoles.contains(role),
           let frame = frame(for: element)
        {
            elements.append(
                FramedElement(
                    element: element,
                    role: role,
                    label: firstInterestingLabel(for: element),
                    frame: frame
                )
            )
        }

        if let children = copyAttribute(element, attribute: kAXChildrenAttribute as String) as? [AXUIElement] {
            for child in children {
                collectFramedElements(
                    from: child,
                    allowedRoles: allowedRoles,
                    depth: depth + 1,
                    into: &elements
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
        kAXCheckBoxRole as String,
        kAXGroupRole as String,
        kAXMenuItemRole as String,
        kAXPopUpButtonRole as String,
        kAXMenuButtonRole as String
    ]

    private let recorderActionLabels: Set<String> = [
        "cancel recording",
        "restart recording",
        "pause",
        "pause recording",
        "resume",
        "resume recording"
    ]

    private lazy var recorderAnchorLabels: Set<String> = {
        recorderActionLabels.union([
            "teleprompter",
            "recorder settings"
        ])
    }()

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
        guard let frame = frame(for: element)
        else {
            return false
        }

        let center = CGPoint(
            x: frame.midX,
            y: frame.midY
        )

        return postMouseClick(at: center)
    }

    private func frame(for element: AXUIElement) -> CGRect? {
        guard let position = point(from: copyAttribute(element, attribute: kAXPositionAttribute as String)),
              let size = size(from: copyAttribute(element, attribute: kAXSizeAttribute as String))
        else {
            return nil
        }

        return CGRect(origin: position, size: size)
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

    private func isRecorderTimerLabel(_ value: String) -> Bool {
        let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let components = normalizedValue.split(separator: ":")

        guard components.count == 2 || components.count == 3 else {
            return false
        }

        return components.allSatisfy { component in
            component.count == 2 && component.allSatisfy(\.isNumber)
        }
    }
}
