import AppKit
import Observation
import MPCore
import MPSupport
import SwiftUI

typealias MeetingPulseState = MPCore.State

@main
struct MeetingPulseApp: App {
    @SwiftUI.State private var model = OwnerAppModel()
    @SwiftUI.State private var launchCoordinator: AppLaunchCoordinator

    init() {
        if !NSApplication.shared.setActivationPolicy(.accessory) {
            NSLog("Meeting Pulse: failed to hide the Dock icon.")
        }
        let coordinator = AppLaunchCoordinator()
        _launchCoordinator = SwiftUI.State(initialValue: coordinator)
        Task {
            await coordinator.start()
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(model: model)
        }
        label: {
            HeartThreadMenuIcon(state: model.state)
        }
        .menuBarExtraStyle(.menu)

        Window("Welcome to Meeting Pulse", id: "onboarding") {
            OnboardingWindow()
        }
        .windowResizability(.contentSize)

        Window("Pairing", id: "pairing") {
            PairingWindow()
        }
        .windowResizability(.contentSize)

        Window("Meeting Pulse Settings", id: "settings") {
            SettingsWindow()
        }
        .windowResizability(.contentSize)

        Window("Recovery", id: "recovery") {
            RecoveryWindow()
        }
        .windowResizability(.contentSize)
    }
}

@MainActor
@Observable
final class OwnerAppModel {
    var state: MeetingPulseState = .unavailable
    var callOkay = false
    var statusLine = "Status unavailable"
    var connectionLine = "Can't reach the server. Retrying."

    func setBusy() {
        state = .busy
        statusLine = "Busy for another 30 minutes"
    }

    func setAvailable() {
        state = .available
        statusLine = "Watching automatically"
    }
}

@MainActor
final class AppLaunchCoordinator {
    enum LaunchState: Equatable {
        case starting
        case setupRequired(String)
        case wrongInstallLocation
        case running
    }

    private var instanceLock: SingleInstanceLock?
    private var permissionCoordinator: PermissionCoordinator?
    private(set) var state: LaunchState = .starting

    func start() async {
        do {
            instanceLock = try SingleInstanceLock()
            _ = try AppConfiguration.load()
            guard InstallLocation().isValid() else {
                state = .wrongInstallLocation
                return
            }
            let coordinator = PermissionCoordinator()
            permissionCoordinator = coordinator
            await coordinator.start()
            state = .running
        } catch let error as AppConfiguration.ConfigurationError {
            state = .setupRequired(error.description)
        } catch {
            state = .setupRequired("Meeting Pulse is not configured yet.")
        }
    }
}

struct MenuBarView: View {
    @Bindable var model: OwnerAppModel

    var body: some View {
        Text(model.statusLine)
        Text(model.connectionLine)
        Divider()
        Menu("Set busy…") {
            Button("15 minutes") { model.setBusy() }
            Button("30 minutes") { model.setBusy() }
            Button("45 minutes") { model.setBusy() }
            Button("1 hour") { model.setBusy() }
            Button("2 hours") { model.setBusy() }
            Button("4 hours") { model.setBusy() }
            Button("Until I clear it") { model.setBusy() }
        }
        Menu("Set available…") {
            Button("15 minutes") { model.setAvailable() }
            Button("30 minutes") { model.setAvailable() }
            Button("45 minutes") { model.setAvailable() }
            Button("1 hour") { model.setAvailable() }
            Button("2 hours") { model.setAvailable() }
            Button("4 hours") { model.setAvailable() }
            Button("Until I clear it") { model.setAvailable() }
        }
        Button("Clear override") { model.setAvailable() }
        Toggle("Calls are okay", isOn: $model.callOkay)
        Button("Check and publish now") {}
        Divider()
        Button("Display name…") {}
        Button("Create pairing code…") {}
        Button("Rotate codes") {}
        Button("Disconnect viewer") {}
        Button("Show recovery phrase…") {}
        Button("Diagnostics…") {}
        Button("Delete everything…") {}
        Divider()
        Button("Quit Meeting Pulse") {
            NSApplication.shared.terminate(nil)
        }
    }
}

struct HeartThreadMenuIcon: View {
    let state: MeetingPulseState
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    var body: some View {
        Image(nsImage: menuBarImage)
            .animation(
                accessibilityReduceMotion ? nil : .easeInOut(duration: 0.18),
                value: state
            )
        .frame(width: 22, height: 22)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(statusAccessibilityLabel)
        .accessibilityIdentifier("meetingpulse.menu-bar-status")
    }

    private var menuBarImage: NSImage {
        let image = NSImage(size: NSSize(width: 22, height: 22))
        image.lockFocusFlipped(true)
        defer {
            image.unlockFocus()
            image.isTemplate = false
        }

        let foregroundColor = NSColor.labelColor
        let scale: CGFloat = 24 / 96
        let menuPoint: (CGFloat, CGFloat) -> NSPoint = { x, y in
            NSPoint(x: x * scale, y: y * scale)
        }

        let upperThread = NSBezierPath()
        upperThread.move(to: menuPoint(31, 32))
        upperThread.curve(
            to: menuPoint(48, 33),
            controlPoint1: menuPoint(36, 36),
            controlPoint2: menuPoint(42, 37)
        )
        upperThread.curve(
            to: menuPoint(65, 34),
            controlPoint1: menuPoint(54, 29),
            controlPoint2: menuPoint(60, 30)
        )
        upperThread.lineWidth = 3.2 * scale
        upperThread.lineCapStyle = .round
        foregroundColor.withAlphaComponent(0.42).setStroke()
        upperThread.stroke()

        let heart = NSBezierPath()
        heart.move(to: menuPoint(48, 76))
        heart.curve(
            to: menuPoint(24, 43),
            controlPoint1: menuPoint(48, 76),
            controlPoint2: menuPoint(24, 60)
        )
        heart.curve(
            to: menuPoint(41, 36),
            controlPoint1: menuPoint(24, 34),
            controlPoint2: menuPoint(34, 29)
        )
        heart.line(to: menuPoint(48, 43))
        heart.line(to: menuPoint(55, 36))
        heart.curve(
            to: menuPoint(72, 43),
            controlPoint1: menuPoint(62, 29),
            controlPoint2: menuPoint(72, 34)
        )
        heart.curve(
            to: menuPoint(48, 76),
            controlPoint1: menuPoint(72, 60),
            controlPoint2: menuPoint(48, 76)
        )
        heart.close()
        heart.lineWidth = 5.8 * scale
        heart.lineCapStyle = .round
        heart.lineJoinStyle = .round
        foregroundColor.setStroke()
        heart.stroke()

        let lowerWave = NSBezierPath()
        lowerWave.move(to: menuPoint(22, 61))
        lowerWave.curve(
            to: menuPoint(48, 61),
            controlPoint1: menuPoint(32, 55),
            controlPoint2: menuPoint(40, 55)
        )
        lowerWave.curve(
            to: menuPoint(74, 61),
            controlPoint1: menuPoint(56, 67),
            controlPoint2: menuPoint(64, 67)
        )
        lowerWave.lineWidth = 4.2 * scale
        lowerWave.lineCapStyle = .round
        lowerWave.lineJoinStyle = .round
        NSColor(calibratedRed: 1, green: 0.8667, blue: 0.4824, alpha: 1).setStroke()
        lowerWave.stroke()

        let dotRadius = 7 * scale
        let dot = NSBezierPath(
            ovalIn: NSRect(
                x: 76 * scale - dotRadius,
                y: 25 * scale - dotRadius,
                width: dotRadius * 2,
                height: dotRadius * 2
            )
        )
        dot.lineWidth = 3 * scale
        foregroundColor.setStroke()
        statusDotColor.setFill()
        dot.stroke()
        dot.fill()

        return image
    }

    private var statusDotColor: NSColor {
        switch state {
        case .busy:
            return NSColor(calibratedRed: 0.45, green: 0.94, blue: 0.68, alpha: 1)
        case .available:
            return NSColor(calibratedRed: 0.99, green: 0.48, blue: 0.57, alpha: 1)
        case .unavailable:
            return NSColor(calibratedRed: 0.62, green: 0.65, blue: 0.71, alpha: 1)
        }
    }

    private var statusAccessibilityLabel: String {
        switch state {
        case .busy:
            return "Meeting Pulse, meeting active"
        case .available:
            return "Meeting Pulse, no active meeting"
        case .unavailable:
            return "Meeting Pulse, status unavailable"
        }
    }
}

struct OnboardingWindow: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Meeting Pulse needs to see your windows")
                .font(.title2.weight(.semibold))
            Text("macOS calls this Accessibility. Meeting Pulse uses it to check two things: whether Chrome has a Google Meet call open, and whether Slack has a huddle running.")
            Text("It does not read page contents, meeting names, links, or anything you type. It never asks for screen recording, and it never touches your screen, microphone, or camera.")
            Text("Three things leave this Mac: one word (free, on a call, or no signal), whether calls are okay right now, and the name you choose to show.")
            Button("Open Accessibility settings") {}
        }
        .padding(24)
        .frame(width: 460)
    }
}

struct PairingWindow: View {
    var body: some View {
        let exampleCode = ["ABCDE", "FGHJK"].joined(separator: "-")
        VStack(alignment: .leading, spacing: 16) {
            Text("Give her this code")
                .font(.title2.weight(.semibold))
            Text("It works once and expires in ten minutes. If she needs another one later, come back here and make a new one.")
            Text(exampleCode)
                .font(.system(.title, design: .monospaced))
            HStack {
                Button("Copy") {}
                Text("Expires in 9:42")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}

struct SettingsWindow: View {
    var body: some View {
        Form {
            Text("Display name…")
            Text("Create pairing code…")
            Text("Launch at login")
        }
        .padding(24)
        .frame(width: 360)
    }
}

struct RecoveryWindow: View {
    var body: some View {
        let examplePhrase = ["ABCDE", "FGHJK", "MNPQR", "STVWX", "YZ012", "3"].joined(separator: "-")
        VStack(alignment: .leading, spacing: 16) {
            Text("Save this phrase")
                .font(.title2.weight(.semibold))
            Text("If this Mac is wiped or replaced, this phrase is the only way to keep your connection without asking her to pair again. Anyone who has it can take over publishing your status, so store it where you keep passwords.")
            Text(examplePhrase)
                .font(.system(.body, design: .monospaced))
            Button("I've saved it") {}
        }
        .padding(24)
        .frame(width: 460)
    }
}
