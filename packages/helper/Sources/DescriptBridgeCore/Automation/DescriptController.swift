import AppKit
import Foundation

struct CommandOutcome {
    let ok: Bool
    let message: String?
    let status: HelperStatus
}

final class DescriptController {
    private let bundleId = "com.descript.beachcube"
    private let screenRecorderShortcutConfigPath = NSString(string: "~/Library/Application Support/Descript/screen-recorder-shortcut.json").expandingTildeInPath
    private let inspector = AccessibilityInspector()
    private let shortcutSynthesizer = ShortcutSynthesizer()

    func currentStatus(options: CommandOptions = CommandOptions()) -> HelperStatus {
        let app = runningApp()
        let permissions = PermissionStatus(accessibilityTrusted: inspector.isTrusted())

        guard let app else {
            return HelperStatus(
                descript: DescriptAppInfo(bundleId: bundleId, isRunning: false, version: nil),
                permissions: permissions,
                preferredRecorder: options.preferredRecorder,
                activeRecorder: nil,
                recorderState: .unavailable,
                supportedActions: SupportedActions(record: false, pauseResume: false, stop: false),
                detail: "Descript is not running."
            )
        }

        let snapshots = permissions.accessibilityTrusted
            ? inspector.captureWindowSnapshots(pid: app.processIdentifier)
            : []
        let inferredState = inferState(from: snapshots)
        let activeRecorder = inferRecorder(from: snapshots, preferred: options.preferredRecorder)

        let canRecord = permissions.accessibilityTrusted || options.allowHotkeyFallback
        let canControlSession = permissions.accessibilityTrusted
            && (inferredState == .recording || inferredState == .paused)

        return HelperStatus(
            descript: DescriptAppInfo(
                bundleId: bundleId,
                isRunning: true,
                version: appVersion(for: app)
            ),
            permissions: permissions,
            preferredRecorder: options.preferredRecorder,
            activeRecorder: activeRecorder,
            recorderState: inferredState,
            supportedActions: SupportedActions(
                record: canRecord,
                pauseResume: canControlSession,
                stop: canControlSession
            ),
            detail: detailMessage(
                permissions: permissions,
                state: inferredState,
                options: options
            )
        )
    }

    func record(options: CommandOptions) -> CommandOutcome {
        guard let app = runningApp() else {
            return CommandOutcome(
                ok: false,
                message: "Descript is not running.",
                status: currentStatus(options: options)
            )
        }

        if options.bringDescriptToFront {
            _ = app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
            Thread.sleep(forTimeInterval: 0.2)
        }

        let beforeStatus = currentStatus(options: options)
        let beforeSnapshots = snapshots(for: app, trusted: beforeStatus.permissions.accessibilityTrusted)
        let target = resolveRecordTarget(for: options)

        switch target {
        case .screen:
            if beforeStatus.recorderState == .recording || beforeStatus.recorderState == .paused {
                return CommandOutcome(
                    ok: true,
                    message: "A Descript recording session is already active.",
                    status: beforeStatus
                )
            }

            if beforeStatus.permissions.accessibilityTrusted {
                let started = startScreenRecordingViaUI(
                    app: app,
                    options: options
                )
                let afterStatus = waitForStatus(
                    options: options,
                    timeout: started ? 2.5 : 1.0
                )
                let afterSnapshots = snapshots(
                    for: app,
                    trusted: afterStatus.permissions.accessibilityTrusted
                )
                let observedTransition = recordTransitionObserved(
                    before: beforeStatus,
                    after: afterStatus,
                    beforeSnapshots: beforeSnapshots,
                    afterSnapshots: afterSnapshots
                )

                if afterStatus.recorderState == .recording {
                    return CommandOutcome(
                        ok: true,
                        message: "Started the Descript Screen Recorder.",
                        status: afterStatus
                    )
                }

                if started || observedTransition {
                    return CommandOutcome(
                        ok: false,
                        message: "Descript reacted, but the Screen Recorder did not reach a live recording state.",
                        status: afterStatus
                    )
                }

                return CommandOutcome(
                    ok: false,
                    message: "Could not find the Screen Recorder controls needed to start recording.",
                    status: afterStatus
                )
            }

            if options.allowHotkeyFallback {
                do {
                    try shortcutSynthesizer.send(options.screenRecorderShortcut)
                    Thread.sleep(forTimeInterval: 0.35)
                    let afterStatus = currentStatus(options: options)
                    let afterSnapshots = snapshots(
                        for: app,
                        trusted: afterStatus.permissions.accessibilityTrusted
                    )
                    let observedTransition = recordTransitionObserved(
                        before: beforeStatus,
                        after: afterStatus,
                        beforeSnapshots: beforeSnapshots,
                        afterSnapshots: afterSnapshots
                    )
                    let shortcutCanceled = defaultScreenRecorderShortcutCanceled(options: options)
                    return CommandOutcome(
                        ok: observedTransition || !afterStatus.permissions.accessibilityTrusted,
                        message: observedTransition
                            ? "Screen Recorder reacted to the Stream Deck command."
                            : shortcutCanceled
                                ? "Descript's Screen Recorder shortcut appears disabled locally, so the command had nothing to trigger."
                            : afterStatus.permissions.accessibilityTrusted
                                ? "Sent the Screen Recorder shortcut, but Descript did not appear to change recorder state."
                                : "Sent the Screen Recorder shortcut to Descript. The result could not be verified without Accessibility access.",
                        status: afterStatus
                    )
                } catch {
                    return CommandOutcome(
                        ok: false,
                        message: "Unable to send the Screen Recorder shortcut: \(error).",
                        status: currentStatus(options: options)
                    )
                }
            }

            return permissionBlockedOutcome(options: options)

        case .editor:
            guard requireAccessibility(for: options) else {
                return permissionBlockedOutcome(options: options)
            }

            let started = inspector.clickFirstButton(
                matching: [
                    "Record",
                    "Start recording",
                    "Start Recording",
                    "Open recorder",
                    "Editor recorder"
                ],
                pid: app.processIdentifier
            )

            Thread.sleep(forTimeInterval: 0.35)
            return CommandOutcome(
                ok: started,
                message: started
                    ? "Tried to start the Editor Recorder from the Descript UI."
                    : "Could not find an Editor Recorder button to press.",
                status: currentStatus(options: options)
            )

        case .auto:
            return record(
                options: CommandOptions(
                    preferredRecorder: .screen,
                    bringDescriptToFront: options.bringDescriptToFront,
                    allowHotkeyFallback: options.allowHotkeyFallback,
                    openPermissionsIfNeeded: options.openPermissionsIfNeeded,
                    screenRecorderShortcut: options.screenRecorderShortcut
                )
            )
        }
    }

    func pauseResume(options: CommandOptions) -> CommandOutcome {
        guard requireAccessibility(for: options) else {
            return permissionBlockedOutcome(options: options)
        }

        guard let app = runningApp() else {
            return CommandOutcome(
                ok: false,
                message: "Descript is not running.",
                status: currentStatus(options: options)
            )
        }

        if options.bringDescriptToFront {
            _ = app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
            Thread.sleep(forTimeInterval: 0.2)
        }

        let beforeStatus = currentStatus(options: options)
        let labels = beforeStatus.recorderState == .paused
            ? ["Resume", "Resume recording", "Resume Recording"]
            : ["Pause", "Pause recording", "Pause Recording", "Resume"]

        var pressed = false
        var afterStatus = beforeStatus

        let attempts: [() -> Bool] = [
            {
                self.inspector.clickFirstButton(
                    matching: labels,
                    pid: app.processIdentifier,
                    method: .click,
                    preference: .first,
                    preferredWindowTitles: ["Descript"]
                )
            },
            {
                self.inspector.clickFirstButton(
                    matching: labels,
                    pid: app.processIdentifier,
                    method: .press,
                    preference: .first,
                    preferredWindowTitles: ["Descript"]
                )
            },
            {
                self.inspector.clickFirstControl(
                    matching: labels,
                    pid: app.processIdentifier,
                    method: .click,
                    preference: .deepest
                )
            }
        ]

        for attempt in attempts {
            guard attempt() else {
                continue
            }

            pressed = true
            afterStatus = waitForRecorderStateChange(
                from: beforeStatus.recorderState,
                options: options,
                timeout: 1.0
            )

            if afterStatus.recorderState != beforeStatus.recorderState {
                break
            }
        }

        let changedState = afterStatus.recorderState != beforeStatus.recorderState

        return CommandOutcome(
            ok: pressed && changedState,
            message: !pressed
                ? "Could not find a pause or resume control in Descript."
                : changedState
                    ? "Changed the Descript recording between pause and resume."
                    : "Clicked the pause or resume control, but Descript did not change recorder state.",
            status: afterStatus
        )
    }

    func stop(options: CommandOptions) -> CommandOutcome {
        guard requireAccessibility(for: options) else {
            return permissionBlockedOutcome(options: options)
        }

        guard let app = runningApp() else {
            return CommandOutcome(
                ok: false,
                message: "Descript is not running.",
                status: currentStatus(options: options)
            )
        }

        if options.bringDescriptToFront {
            _ = app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
            Thread.sleep(forTimeInterval: 0.2)
        }

        let stopLabels = [
            "Stop",
            "Stop recording",
            "Stop Recording",
            "Finish"
        ]
        var pressed = false
        var afterStatus = currentStatus(options: options)

        let attempts: [() -> Bool] = [
            {
                self.inspector.clickFirstButton(
                    matching: stopLabels,
                    pid: app.processIdentifier,
                    method: .click,
                    preference: .first,
                    preferredWindowTitles: ["Descript"]
                )
            },
            {
                self.inspector.clickFirstButton(
                    matching: stopLabels,
                    pid: app.processIdentifier,
                    method: .press,
                    preference: .first,
                    preferredWindowTitles: ["Descript"]
                )
            },
            {
                self.inspector.clickFirstControl(
                    matching: stopLabels,
                    pid: app.processIdentifier,
                    method: .click,
                    preference: .deepest
                )
            },
            {
                self.inspector.clickRecorderTimerButton(
                    pid: app.processIdentifier
                )
            },
            {
                self.inspector.clickInteractiveElementBetween(
                    leftLabels: [
                        "Pause",
                        "Pause Recording",
                        "Resume",
                        "Resume Recording",
                        "Restart recording"
                    ],
                    rightLabels: ["Teleprompter", "Recorder settings"],
                    pid: app.processIdentifier
                )
            }
        ]

        for attempt in attempts {
            guard attempt() else {
                continue
            }

            pressed = true
            afterStatus = waitForStatus(options: options, timeout: 1.25)
            if afterStatus.recorderState == .idle {
                break
            }
        }

        let stopped = afterStatus.recorderState == .idle

        return CommandOutcome(
            ok: pressed && stopped,
            message: !pressed
                ? "Could not find a stop control in Descript."
                : stopped
                    ? "Stopped the Descript recording."
                    : "Clicked the stop control, but Descript still appears to be recording.",
            status: afterStatus
        )
    }

    func openAccessibilitySettings() -> Bool {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else {
            return false
        }

        return NSWorkspace.shared.open(url)
    }

    func debugSnapshot() -> DebugSnapshotPayload {
        guard let app = runningApp() else {
            return DebugSnapshotPayload(
                summary: "Descript is not running.",
                windows: []
            )
        }

        let snapshots = inspector.captureWindowSnapshots(pid: app.processIdentifier)
        return DebugSnapshotPayload(
            summary: "Captured \(snapshots.count) Descript window snapshots.",
            windows: snapshots.map { snapshot in
                WindowDebugSnapshot(
                    title: snapshot.title,
                    role: snapshot.role,
                    buttons: snapshot.buttons,
                    elements: snapshot.elements.map { element in
                        DebugElementSnapshot(
                            role: element.role,
                            label: element.label,
                            depth: element.depth
                        )
                    }
                )
            }
        )
    }

    private func runningApp() -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first
    }

    private func snapshots(
        for app: NSRunningApplication,
        trusted: Bool
    ) -> [AccessibilityWindowSnapshot] {
        trusted
            ? inspector.captureWindowSnapshots(pid: app.processIdentifier)
            : []
    }

    private func requireAccessibility(for options: CommandOptions) -> Bool {
        let trusted = inspector.isTrusted()
        if !trusted && options.openPermissionsIfNeeded {
            _ = inspector.requestTrustPrompt()
            _ = openAccessibilitySettings()
        }
        return trusted
    }

    private func permissionBlockedOutcome(options: CommandOptions) -> CommandOutcome {
        CommandOutcome(
            ok: false,
            message: "Accessibility access is required for this control.",
            status: currentStatus(options: options)
        )
    }

    private func appVersion(for app: NSRunningApplication) -> String? {
        guard let url = app.bundleURL, let bundle = Bundle(url: url) else {
            return nil
        }

        return bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    private func startScreenRecordingViaUI(
        app: NSRunningApplication,
        options: CommandOptions
    ) -> Bool {
        let pid = app.processIdentifier
        var progressed = false

        if screenRecorderMenuIsVisible(pid: pid) {
            progressed = selectScreenRecorderMenuItem(pid: pid) || progressed
            Thread.sleep(forTimeInterval: 0.4)
        }

        if !screenRecorderControlsAreVisible(pid: pid) {
            let openedMenu = inspector.clickFirstControl(
                matching: ["Record"],
                pid: pid,
                method: .click,
                preference: .deepest
            )
            progressed = openedMenu || progressed
            Thread.sleep(forTimeInterval: 0.4)

            if screenRecorderMenuIsVisible(pid: pid) {
                progressed = selectScreenRecorderMenuItem(pid: pid) || progressed
                Thread.sleep(forTimeInterval: 0.5)
            }

            if screenRecorderInsertionMenuIsVisible(pid: pid) {
                progressed = selectScreenRecorderInsertionTarget(pid: pid) || progressed
                Thread.sleep(forTimeInterval: 0.5)
            }
        }

        if screenRecorderControlsAreVisible(pid: pid) {
            if inspector.clickFirstButton(
                matching: ["1"],
                pid: pid,
                method: .click
            ) {
                progressed = true
                Thread.sleep(forTimeInterval: 0.5)
            } else if inspector.containsElement(
                matching: ["Press space to start"],
                roles: screenRecorderTriggerRoles,
                pid: pid
            ) {
                do {
                    try shortcutSynthesizer.send("space")
                    progressed = true
                    Thread.sleep(forTimeInterval: 0.5)
                } catch {
                    return progressed
                }
            }
        }

        return progressed
    }

    private func screenRecorderMenuIsVisible(pid: pid_t) -> Bool {
        inspector.containsElement(
            matching: [
                "screen mode Screen",
                "camera mode Camera",
                "Audio only",
                "rooms Record with others"
            ],
            roles: [menuItemRole],
            pid: pid
        )
    }

    private func screenRecorderControlsAreVisible(pid: pid_t) -> Bool {
        inspector.containsElement(
            matching: [
                "Screen recorder open",
                "Press space to start",
                "Screen sharing",
                "No screen shared",
                "Pause recording",
                "Resume recording"
            ],
            roles: screenRecorderTriggerRoles,
            pid: pid
        )
    }

    private func selectScreenRecorderMenuItem(pid: pid_t) -> Bool {
        if inspector.focusFirstElement(
            matching: ["screen mode Screen"],
            roles: [menuItemRole],
            pid: pid
        ) {
            do {
                try shortcutSynthesizer.send("return")
                return true
            } catch {
                return false
            }
        }

        return inspector.clickFirstElement(
            matching: ["screen mode Screen"],
            roles: [menuItemRole],
            pid: pid
        )
    }

    private func screenRecorderInsertionMenuIsVisible(pid: pid_t) -> Bool {
        inspector.containsElement(
            matching: [
                "Insert into script This recording will be transcribed and added to your script",
                "New layer This recording will be added on top of your current scene"
            ],
            roles: [menuItemRole],
            pid: pid
        )
    }

    private func selectScreenRecorderInsertionTarget(pid: pid_t) -> Bool {
        if inspector.focusFirstElement(
            matching: ["Insert into script This recording will be transcribed and added to your script"],
            roles: [menuItemRole],
            pid: pid
        ) {
            do {
                try shortcutSynthesizer.send("return")
                return true
            } catch {
                return false
            }
        }

        return inspector.clickFirstElement(
            matching: ["Insert into script This recording will be transcribed and added to your script"],
            roles: [menuItemRole],
            pid: pid
        )
    }

    private func waitForStatus(
        options: CommandOptions,
        timeout: TimeInterval,
        pollInterval: TimeInterval = 0.2
    ) -> HelperStatus {
        let deadline = Date().addingTimeInterval(timeout)
        var latest = currentStatus(options: options)

        while Date() < deadline {
            Thread.sleep(forTimeInterval: pollInterval)
            latest = currentStatus(options: options)
        }

        return latest
    }

    private func waitForRecorderStateChange(
        from initialState: RecorderState,
        options: CommandOptions,
        timeout: TimeInterval,
        pollInterval: TimeInterval = 0.2
    ) -> HelperStatus {
        let deadline = Date().addingTimeInterval(timeout)
        var latest = currentStatus(options: options)

        while Date() < deadline {
            if latest.recorderState != initialState {
                return latest
            }

            Thread.sleep(forTimeInterval: pollInterval)
            latest = currentStatus(options: options)
        }

        return latest
    }

    private func inferState(from snapshots: [AccessibilityWindowSnapshot]) -> RecorderState {
        let prioritizedSnapshots = prioritizedStateSnapshots(from: snapshots)

        let controlLabels = prioritizedSnapshots
            .flatMap(\.elements)
            .filter { recorderSignalRoles.contains($0.role) }
            .map(\.label)
            .map(normalize)

        let buttonNames = prioritizedSnapshots
            .flatMap(\.buttons)
            .map(normalize)

        let signalLabels = controlLabels + buttonNames

        if signalLabels.contains(where: { $0 == "resume" || $0.contains("resume recording") }) {
            return .paused
        }

        if signalLabels.contains(where: {
            $0 == "pause"
                || $0 == "stop"
                || $0.contains("pause recording")
                || $0.contains("stop recording")
        }) {
            return .recording
        }

        return .idle
    }

    private func prioritizedStateSnapshots(
        from snapshots: [AccessibilityWindowSnapshot]
    ) -> [AccessibilityWindowSnapshot] {
        let dedicatedControlWindows = snapshots.filter(isDedicatedRecorderControlWindow)
        return dedicatedControlWindows.isEmpty ? snapshots : dedicatedControlWindows
    }

    private func isDedicatedRecorderControlWindow(
        _ snapshot: AccessibilityWindowSnapshot
    ) -> Bool {
        let title = normalize(snapshot.title)
        guard title == "descript" else {
            return false
        }

        let labels = snapshot.buttons.map(normalize)
            + snapshot.elements.map(\.label).map(normalize)

        return labels.contains(where: { label in
            label == "pause recording"
                || label == "resume recording"
                || label == "stop recording"
                || label == "restart recording"
        })
    }

    private func inferRecorder(
        from snapshots: [AccessibilityWindowSnapshot],
        preferred: RecorderKind
    ) -> RecorderKind? {
        let titles = snapshots.map(\.title).map(normalize)

        if titles.contains(where: { $0.contains("screen recorder") || $0 == "descript recorder" }) {
            return .screen
        }

        if titles.contains(where: { $0.contains("editor recorder") }) {
            return .editor
        }

        return preferred == .auto ? nil : preferred
    }

    private func detailMessage(
        permissions: PermissionStatus,
        state: RecorderState,
        options: CommandOptions
    ) -> String? {
        if !permissions.accessibilityTrusted {
            return "Accessibility access is missing, so pause, resume, and stop are unavailable."
        }

        if defaultScreenRecorderShortcutCanceled(options: options) {
            return "Descript's local Screen Recorder shortcut appears disabled, so the default record hotkey fallback will not work."
        }

        if state == .idle {
            return "Descript is running and waiting for a recording session."
        }

        return nil
    }

    private func resolveRecordTarget(for options: CommandOptions) -> RecorderKind {
        switch options.preferredRecorder {
        case .screen, .editor:
            return options.preferredRecorder
        case .auto:
            return .screen
        }
    }

    private func recordTransitionObserved(
        before: HelperStatus,
        after: HelperStatus,
        beforeSnapshots: [AccessibilityWindowSnapshot],
        afterSnapshots: [AccessibilityWindowSnapshot]
    ) -> Bool {
        if after.recorderState != before.recorderState {
            return true
        }

        if after.activeRecorder != before.activeRecorder {
            return true
        }

        return snapshotFingerprint(beforeSnapshots) != snapshotFingerprint(afterSnapshots)
    }

    private func snapshotFingerprint(_ snapshots: [AccessibilityWindowSnapshot]) -> [String] {
        snapshots
            .map { snapshot in
                let buttons = snapshot.buttons.map(normalize).sorted().joined(separator: "|")
                return "\(normalize(snapshot.title))::\(normalize(snapshot.role))::\(buttons)"
            }
            .sorted()
    }

    private func defaultScreenRecorderShortcutCanceled(options: CommandOptions) -> Bool {
        guard normalize(options.screenRecorderShortcut) == "cmd+shift+2" else {
            return false
        }

        guard let data = FileManager.default.contents(atPath: screenRecorderShortcutConfigPath),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return false
        }

        return object["canceled"] as? Bool == true
    }

    private func normalize(_ value: String) -> String {
        value
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private let menuItemRole = "AXMenuItem"
    private let recorderSignalRoles: Set<String> = [
        "AXButton",
        "AXCheckBox",
        "AXGroup",
        "AXMenuButton",
        "AXPopUpButton"
    ]
    private let screenRecorderTriggerRoles: Set<String> = [
        "AXButton",
        "AXStaticText",
        "AXMenuItem"
    ]
}
