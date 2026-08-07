import AppKit
import Observation
import MPCore
import MPDetection
import MPSupport
import MPSync
import SwiftUI
import WebKit

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
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(model: model)
                .task {
                    await launchCoordinator.start(model: model)
                }
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
            PairingWindow(model: model)
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
final class OwnerRuntime {
    private let model: OwnerAppModel
    private let scheduler: DetectionScheduler
    private let transport: any StatusTransport
    private let recovery: RecoveryService
    private let secrets: any SecretStore
    private let existingRegistration: DeviceRegistration?
    private let pairing: PairingService
    private var task: Task<Void, Never>?
    private var sync: SyncCoordinator?

    init(
        model: OwnerAppModel,
        transport: any StatusTransport,
        recovery: RecoveryService,
        secrets: any SecretStore,
        existingRegistration: DeviceRegistration?
    ) {
        self.model = model
        self.transport = transport
        self.recovery = recovery
        self.secrets = secrets
        self.existingRegistration = existingRegistration
        pairing = PairingService(transport: transport)
        let meet = GoogleMeetDetector()
        let slack = SlackHuddleDetector()
        scheduler = DetectionScheduler(meet: meet, slack: slack)
    }

    func start() async throws {
        let registration = try await registration()
        sync = SyncCoordinator(
            transport: transport,
            nonce: registration.instanceNonce
        )
        let stream = await scheduler.readings
        task = Task { [weak self] in
            guard let self else {
                return
            }
            await self.scheduler.start()
            NSLog("Meeting Pulse scheduler started")
            for await reading in stream {
                NSLog(
                    "Meeting Pulse reading meet=%@ slack=%@ permission=%d",
                    reading.meet.rawValue,
                    reading.slack.rawValue,
                    reading.accessibilityGranted
                )
                let status = StatusReducer.reduce(
                    ReducerInput(
                        meet: reading.meet,
                        slack: reading.slack,
                        accessibilityGranted: reading.accessibilityGranted,
                        override: nil,
                        callOkay: self.model.callOkay,
                        monotonicNow: SystemMonotonicClock().now()
                    )
                )
                self.model.applyAutomatic(status)
                if let sync = self.sync {
                    await sync.submit(
                        StatusPayload(
                            state: status.state,
                            callOkay: status.callOkay,
                            overrideMode: self.model.manualOverrideState,
                            overrideExpiresAt: nil
                        )
                    )
                    if await sync.currentState == .idle {
                        self.model.connectionLine = "Last published just now"
                    }
                }
            }
        }
    }

    private func registration() async throws -> DeviceRegistration {
        if let existingRegistration {
            return existingRegistration
        }
        return try await recovery.registerDevice().registration
    }

    func createPairingCode() async throws -> PairingCodeResult {
        try await pairing.createCode()
    }

    func stop() async {
        task?.cancel()
        task = nil
        await scheduler.stop()
    }
}

@MainActor
@Observable
final class OwnerAppModel {
    var state: MeetingPulseState = .unavailable
    var callOkay = false
    var statusLine = "Status unavailable"
    var connectionLine = "Can't reach the server. Retrying."
    var pairingCode: PairingCodeResult?
    var pairingExpiresAt: Date?
    var runtime: OwnerRuntime?
    private var pairingWindow: NSWindow?

    func setBusy() {
        state = .busy
        manualState = .busy
        statusLine = "Busy for another 30 minutes"
    }

    func setAvailable() {
        state = .available
        manualState = .available
        statusLine = "Watching automatically"
    }

    func clearOverride() {
        manualState = nil
        statusLine = "Watching automatically"
    }

    var manualOverrideState: MeetingPulseState? {
        manualState
    }

    func createPairingCode() {
        showPairingWindow()
        Task { @MainActor in
            do {
                let result = try await runtime?.createPairingCode()
                pairingCode = result
                pairingExpiresAt = result.map { _ in Date().addingTimeInterval(600) }
            } catch {
                connectionLine = "Can't reach the server. Retrying."
            }
        }
    }

    private func showPairingWindow() {
        if let pairingWindow {
            pairingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 260),
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        window.title = "Pairing"
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.contentViewController = NSHostingController(
            rootView: PairingWindow(model: self)
        )
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        pairingWindow = window
    }

    func applyAutomatic(_ status: EffectiveStatus) {
        guard manualState == nil else {
            return
        }
        NSLog(
            "Meeting Pulse reducer state=%@ reason=%@",
            status.state.rawValue,
            status.reason.rawValue
        )
        state = status.state
        callOkay = status.callOkay
        statusLine = switch status.state {
        case .available:
            "Watching automatically"
        case .busy:
            "Busy"
        case .unavailable:
            "Status unavailable"
        }
    }

    private var manualState: MeetingPulseState?
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
    private var runtime: OwnerRuntime?
    private var turnstilePanel: NSPanel?
    private(set) var state: LaunchState = .starting

    func start(model: OwnerAppModel) async {
        NSLog("Meeting Pulse launch sequence started")
        guard state == .starting else {
            return
        }
        do {
            instanceLock = try SingleInstanceLock()
            let configuration = try AppConfiguration.load()
            NSLog("Meeting Pulse configuration loaded")
            guard InstallLocation().isValid() else {
                NSLog("Meeting Pulse install location is invalid")
                state = .wrongInstallLocation
                return
            }
            let coordinator = PermissionCoordinator()
            permissionCoordinator = coordinator
            await coordinator.start()
            NSLog("Meeting Pulse permission coordinator started")
            let secrets = KeychainStore()
            let existingRegistration = try existingRegistration(from: secrets)
            let provider: any TurnstileProvider
            if existingRegistration == nil {
                guard
                    let htmlURL = Bundle.main.url(
                        forResource: "turnstile",
                        withExtension: "html"
                    )
                else {
                    throw LaunchError.turnstileResourceMissing
                }
                let webProvider = WKTurnstileProvider(
                    siteKey: configuration.turnstileSiteKey,
                    htmlURL: htmlURL,
                    baseURL: URL(string: "https://localhost")
                )
                provider = webProvider
                showTurnstile(webProvider.view)
            } else {
                provider = UnavailableTurnstileProvider()
            }
            let gate = TurnstileGate(provider: provider)
            let transport = SupabaseStatusTransport(
                configuration: configuration,
                turnstile: gate
            )
            let recovery = RecoveryService(transport: transport, secrets: secrets)
            let runtime = OwnerRuntime(
                model: model,
                transport: transport,
                recovery: recovery,
                secrets: secrets,
                existingRegistration: existingRegistration
            )
            self.runtime = runtime
            model.runtime = runtime
            try await runtime.start()
            turnstilePanel?.close()
            turnstilePanel = nil
            NSLog("Meeting Pulse detection runtime started")
            state = .running
        } catch let error as AppConfiguration.ConfigurationError {
            NSLog("Meeting Pulse configuration error: %@", error.description)
            state = .setupRequired(error.description)
        } catch {
            NSLog("Meeting Pulse launch error: %@", String(describing: error))
            state = .setupRequired("Meeting Pulse is not configured yet.")
        }
    }

    private enum LaunchError: Error {
        case turnstileResourceMissing
        case keychainLocked
        case invalidDeviceIdentity
    }

    private func existingRegistration(
        from secrets: any SecretStore
    ) throws -> DeviceRegistration? {
        let deviceID = try secrets.read(.deviceID)
        let nonce = try secrets.read(.deviceInstanceNonce)
        switch (deviceID, nonce) {
        case (.missing, .missing):
            return nil
        case let (.present(deviceData), .present(nonceData)):
            guard
                let device = UUID(
                    uuidString: String(decoding: deviceData, as: UTF8.self)
                ),
                let instanceNonce = UUID(
                    uuidString: String(decoding: nonceData, as: UTF8.self)
                )
            else {
                throw LaunchError.invalidDeviceIdentity
            }
            return DeviceRegistration(deviceID: device, instanceNonce: instanceNonce)
        case (.temporarilyUnavailable, _), (_, .temporarilyUnavailable):
            throw LaunchError.keychainLocked
        default:
            throw LaunchError.invalidDeviceIdentity
        }
    }

    private func showTurnstile(_ webView: WKWebView) {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 260),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Meeting Pulse"
        webView.frame = NSRect(origin: .zero, size: NSSize(width: 420, height: 260))
        webView.autoresizingMask = [.width, .height]
        panel.contentView = webView
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        turnstilePanel = panel
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
        Button("Clear override") { model.clearOverride() }
        Toggle("Calls are okay", isOn: $model.callOkay)
        Button("Check and publish now") {}
        Divider()
        Button("Display name…") {}
        Button("Create pairing code…") {
            model.createPairingCode()
        }
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
    @Bindable var model: OwnerAppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Give her this code")
                .font(.title2.weight(.semibold))
            Text("It works once and expires in ten minutes. If she needs another one later, come back here and make a new one.")
            if let pairingCode = model.pairingCode {
                Text(pairingCode.displayCode)
                    .font(.system(.title, design: .monospaced))
                HStack {
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(
                            pairingCode.displayCode,
                            forType: .string
                        )
                    }
                    if let expiresAt = model.pairingExpiresAt {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text("Expires in \(countdown(for: expiresAt, at: context.date))")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                Text("Create pairing code…")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .frame(width: 420)
    }

    private func countdown(for date: Date, at now: Date) -> String {
        let seconds = max(0, Int(date.timeIntervalSince(now)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
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
