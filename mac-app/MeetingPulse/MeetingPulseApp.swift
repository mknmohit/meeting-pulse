import AppKit
import MPCore
import MPDetection
import MPSupport
import MPSync
import Observation
import SwiftUI
import WebKit

typealias MeetingPulseState = MPCore.State

@main
struct MeetingPulseApp: App {
  @SwiftUI.State private var model = OwnerAppModel()
  @SwiftUI.State private var launchCoordinator = AppLaunchCoordinator()
  @NSApplicationDelegateAdaptor(MeetingPulseAppDelegate.self)
  private var appDelegate

  init() {
    if !NSApplication.shared.setActivationPolicy(.accessory) {
      NSLog("Meeting Pulse: failed to hide the Dock icon.")
    }
  }

  var body: some Scene {
    MenuBarExtra {
      MenuBarView(model: model)
    } label: {
      HeartThreadMenuIcon(state: model.state)
        .task {
          await launchCoordinator.start(model: model)
          appDelegate.terminationHandler = {
            await model.runtime?.gracefulQuit()
          }
        }
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
      SettingsWindow(model: model)
    }
    .windowResizability(.contentSize)

    Window("Recovery", id: "recovery") {
      RecoveryWindow(model: model)
    }
    .windowResizability(.contentSize)

    Window("Diagnostics", id: "diagnostics") {
      DiagnosticsWindow(model: model)
    }
    .windowResizability(.contentSize)
  }
}

@MainActor
final class MeetingPulseAppDelegate: NSObject, NSApplicationDelegate {
  var terminationHandler: (@MainActor () async -> Void)?
  private var terminationStarted = false

  func applicationShouldTerminate(
    _: NSApplication
  ) -> NSApplication.TerminateReply {
    guard let terminationHandler, !terminationStarted else {
      return .terminateNow
    }
    terminationStarted = true
    Task { @MainActor in
      await terminationHandler()
      NSApp.reply(toApplicationShouldTerminate: true)
    }
    return .terminateLater
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
  private let viewerOrigins: [URL]
  private var task: Task<Void, Never>?
  private var sync: SyncCoordinator?
  private var overrideStore: ManualOverrideStore?

  init(
    model: OwnerAppModel,
    transport: any StatusTransport,
    recovery: RecoveryService,
    secrets: any SecretStore,
    existingRegistration: DeviceRegistration?,
    viewerOrigins: [URL]
  ) {
    self.model = model
    self.transport = transport
    self.recovery = recovery
    self.secrets = secrets
    self.existingRegistration = existingRegistration
    self.viewerOrigins = viewerOrigins
    pairing = PairingService(transport: transport, secrets: secrets)
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
    overrideStore = ManualOverrideStore(
      publish: { [weak self] override in
        Task { @MainActor in
          await self?.overrideDidChange(override)
        }
      }
    )
    let savedOverride = await overrideStore?.load()
    model.applyLoadedOverride(savedOverride)
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
            override: self.model.manualOverride,
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
              overrideExpiresAt: self.model.manualOverride?.expiresAtWall
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

  func storedPairingCode() throws -> PairingCodeResult? {
    try pairing.storedCode()
  }

  func pairingLinks(for code: PairingCodeResult) throws -> [URL] {
    try viewerOrigins.map { origin in
      try pairing.link(for: code, viewerOrigin: origin)
    }
  }

  func rotatePairingCode() async throws -> PairingCodeResult {
    _ = try await transport.rotatePairingCodes()
    return try await pairing.createCode()
  }

  func revokePairingCode() async throws {
    _ = try await transport.rotatePairingCodes()
    try pairing.deleteStoredCode()
  }

  func refreshAndPublish() async {
    await scheduler.requestImmediateSample()
  }

  func updateDisplayName(_ name: String?) async throws {
    try await transport.updateDisplayName(name)
  }

  func updateLoginItem(_ enabled: Bool) throws {
    if enabled {
      _ = try LoginItem().register()
    } else {
      try LoginItem().unregister()
    }
  }

  func setOverride(
    state: MeetingPulseState,
    duration: ManualOverride.Duration
  ) async throws {
    guard let overrideStore else {
      throw OwnerRuntimeError.unavailable
    }
    let override = try await overrideStore.set(state: state, duration: duration)
    model.applyManualOverride(override)
    await publishOverride(override)
  }

  func clearOverride() async throws {
    guard let overrideStore else {
      throw OwnerRuntimeError.unavailable
    }
    try await overrideStore.clear()
    model.clearManualOverride()
    await scheduler.requestImmediateSample()
  }

  func recoveryPhrase() throws -> String? {
    switch try secrets.read(.deviceRecoveryPhrase) {
    case .missing:
      return nil
    case .temporarilyUnavailable:
      throw OwnerRuntimeError.unavailable
    case .present(let data):
      guard
        let raw = String(data: data, encoding: .utf8),
        MPCore.RecoveryPhraseFormat.length == raw.count
      else {
        throw OwnerRuntimeError.invalidRecoveryPhrase
      }
      return MPCore.RecoveryPhraseFormat.display(raw)
    }
  }

  func deleteEverything() async throws {
    try await transport.deleteDevice()
    try await overrideStore?.clear()
    await stop()
    for key in SecretKey.allCases {
      try secrets.delete(key)
    }
  }

  func gracefulQuit() async {
    let payload = StatusPayload(
      state: .unavailable,
      callOkay: false,
      overrideMode: nil,
      overrideExpiresAt: nil
    )
    if let sync {
      let publishTask = Task {
        await sync.submit(payload)
      }
      try? await Task.sleep(for: .seconds(3))
      publishTask.cancel()
    }
    await stop()
  }

  func stop() async {
    task?.cancel()
    task = nil
    await scheduler.stop()
    await sync?.stop()
  }

  private func publishOverride(_ override: ManualOverride) async {
    guard let sync else {
      return
    }
    await sync.submit(
      StatusPayload(
        state: override.state,
        callOkay: model.callOkay,
        overrideMode: override.state,
        overrideExpiresAt: override.expiresAtWall
      )
    )
  }

  private func overrideDidChange(_ override: ManualOverride?) async {
    if let override {
      model.applyManualOverride(override)
    } else {
      model.clearManualOverride()
    }
    await scheduler.requestImmediateSample()
  }
}

@MainActor
@Observable
final class OwnerAppModel {
  var state: MeetingPulseState = .unavailable
  var callOkay = false
  var statusLine = "Status unavailable"
  var connectionLine = "Can't reach the server. Retrying."
  var displayName = ""
  var launchAtLogin = false
  var recoveryPhrase: String?
  var pairingCode: PairingCodeResult?
  var pairingLinks: [URL] = []
  var showingRotateConfirmation = false
  var showingRevokeConfirmation = false
  var showingDeleteConfirmation = false
  var runtime: OwnerRuntime?
  var manualOverride: ManualOverride?
  private var pairingWindow: NSWindow?

  func setBusy(duration: ManualOverride.Duration = .m30) {
    requestOverride(state: .busy, duration: duration)
  }

  func setAvailable(duration: ManualOverride.Duration = .m30) {
    requestOverride(state: .available, duration: duration)
  }

  func clearOverride() {
    Task { @MainActor in
      do {
        guard let runtime else {
          throw OwnerRuntimeError.unavailable
        }
        try await runtime.clearOverride()
      } catch {
        connectionLine = "Can't reach the server. Retrying."
      }
    }
  }

  var manualOverrideState: MeetingPulseState? {
    manualOverride?.state
  }

  func setCallOkay(_ value: Bool) {
    callOkay = value
    refreshAndPublish()
  }

  func applyLoadedOverride(_ override: ManualOverride?) {
    manualOverride = override
    if let override {
      state = override.state
      statusLine = override.state == .busy ? "Busy" : "Available override"
    }
  }

  func applyManualOverride(_ override: ManualOverride) {
    manualOverride = override
    state = override.state
    statusLine = override.state == .busy ? "Busy" : "Available override"
  }

  func clearManualOverride() {
    manualOverride = nil
    statusLine = "Watching automatically"
  }

  private func requestOverride(
    state: MeetingPulseState,
    duration: ManualOverride.Duration
  ) {
    Task { @MainActor in
      do {
        guard let runtime else {
          throw OwnerRuntimeError.unavailable
        }
        try await runtime.setOverride(state: state, duration: duration)
      } catch {
        connectionLine = "Can't reach the server. Retrying."
      }
    }
  }

  func createPairingCode() {
    showPairingWindow()
    Task { @MainActor in
      do {
        guard let runtime else {
          throw OwnerRuntimeError.unavailable
        }
        let result = try await runtime.createPairingCode()
        pairingCode = result
        pairingLinks = try runtime.pairingLinks(for: result)
      } catch {
        connectionLine = "Can't reach the server. Retrying."
      }
    }
  }

  func loadStoredPairingCode() throws {
    guard let runtime else {
      return
    }
    guard let code = try runtime.storedPairingCode() else {
      pairingCode = nil
      pairingLinks = []
      return
    }
    pairingCode = code
    pairingLinks = try runtime.pairingLinks(for: code)
  }

  func rotatePairingCode() {
    Task { @MainActor in
      do {
        guard let runtime else {
          throw OwnerRuntimeError.unavailable
        }
        let code = try await runtime.rotatePairingCode()
        pairingCode = code
        pairingLinks = try runtime.pairingLinks(for: code)
      } catch {
        connectionLine = "Can't reach the server. Retrying."
      }
    }
  }

  func revokePairingCode() {
    Task { @MainActor in
      do {
        guard let runtime else {
          throw OwnerRuntimeError.unavailable
        }
        try await runtime.revokePairingCode()
        pairingCode = nil
        pairingLinks = []
      } catch {
        connectionLine = "Can't reach the server. Retrying."
      }
    }
  }

  func refreshAndPublish() {
    Task { @MainActor in
      guard let runtime else {
        connectionLine = "Meeting Pulse is still starting."
        return
      }
      await runtime.refreshAndPublish()
    }
  }

  func saveDisplayName() {
    Task { @MainActor in
      do {
        guard let runtime else {
          throw OwnerRuntimeError.unavailable
        }
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        try await runtime.updateDisplayName(trimmed.isEmpty ? nil : trimmed)
      } catch {
        connectionLine = "Can't reach the server. Retrying."
      }
    }
  }

  func loadLaunchAtLogin() {
    launchAtLogin = LoginItem().isEnabled
  }

  func setLaunchAtLogin(_ enabled: Bool) {
    do {
      guard let runtime else {
        throw OwnerRuntimeError.unavailable
      }
      try runtime.updateLoginItem(enabled)
      launchAtLogin = enabled
    } catch {
      connectionLine = "Meeting Pulse couldn't update launch at login."
    }
  }

  func loadRecoveryPhrase() throws {
    guard let runtime else {
      throw OwnerRuntimeError.unavailable
    }
    recoveryPhrase = try runtime.recoveryPhrase()
  }

  func deleteEverything() {
    Task { @MainActor in
      do {
        guard let runtime else {
          throw OwnerRuntimeError.unavailable
        }
        try await runtime.deleteEverything()
        state = .unavailable
        statusLine = "Status unavailable"
        connectionLine = "Meeting Pulse was reset."
        displayName = ""
        launchAtLogin = false
        recoveryPhrase = nil
        pairingCode = nil
        pairingLinks = []
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
      contentRect: NSRect(x: 0, y: 0, width: 460, height: 460),
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
    guard manualOverride == nil else {
      return
    }
    NSLog(
      "Meeting Pulse reducer state=%@ reason=%@",
      status.state.rawValue,
      status.reason.rawValue
    )
    state = status.state
    callOkay = status.callOkay
    statusLine =
      switch status.state {
      case .available:
        "Watching automatically"
      case .busy:
        "Busy"
      case .unavailable:
        "Status unavailable"
      }
  }

}

private enum OwnerRuntimeError: Error {
  case unavailable
  case invalidRecoveryPhrase
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
        existingRegistration: existingRegistration,
        viewerOrigins: configuration.viewerOrigins
      )
      self.runtime = runtime
      model.runtime = runtime
      model.loadLaunchAtLogin()
      try await runtime.start()
      try model.loadStoredPairingCode()
      try model.loadRecoveryPhrase()
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
    case (.present(let deviceData), .present(let nonceData)):
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
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    Text(model.statusLine)
      .confirmationDialog(
        "Delete everything?",
        isPresented: $model.showingDeleteConfirmation,
        titleVisibility: .visible
      ) {
        Button("Delete everything", role: .destructive) {
          model.deleteEverything()
        }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text("This removes the status, viewer access, and recovery data from this Mac.")
      }
    Text(model.connectionLine)
    Divider()
    Menu("Set busy…") {
      Button("15 minutes") { model.setBusy(duration: .m15) }
      Button("30 minutes") { model.setBusy(duration: .m30) }
      Button("45 minutes") { model.setBusy(duration: .m45) }
      Button("1 hour") { model.setBusy(duration: .h1) }
      Button("2 hours") { model.setBusy(duration: .h2) }
      Button("4 hours") { model.setBusy(duration: .h4) }
      Button("Until I clear it") { model.setBusy(duration: .untilCleared) }
    }
    Menu("Set available…") {
      Button("15 minutes") { model.setAvailable(duration: .m15) }
      Button("30 minutes") { model.setAvailable(duration: .m30) }
      Button("45 minutes") { model.setAvailable(duration: .m45) }
      Button("1 hour") { model.setAvailable(duration: .h1) }
      Button("2 hours") { model.setAvailable(duration: .h2) }
      Button("4 hours") { model.setAvailable(duration: .h4) }
      Button("Until I clear it") { model.setAvailable(duration: .untilCleared) }
    }
    Button("Clear override") { model.clearOverride() }
    Toggle(
      "Calls are okay",
      isOn: Binding(
        get: { model.callOkay },
        set: { model.setCallOkay($0) }
      )
    )
    Button("Check and publish now") { model.refreshAndPublish() }
    Divider()
    Button("Display name…") { openWindow(id: "settings") }
    Button("Create viewer link…") {
      model.createPairingCode()
    }
    Button("Rotate viewer link…") {
      model.showingRotateConfirmation = true
    }
    .disabled(model.pairingCode == nil)
    Button("Revoke viewer access…") {
      model.showingRevokeConfirmation = true
    }
    .disabled(model.pairingCode == nil)
    Button("Show recovery phrase…") { openWindow(id: "recovery") }
    Button("Diagnostics…") { openWindow(id: "diagnostics") }
    Button("Delete everything…") {
      model.showingDeleteConfirmation = true
    }
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
      Text(
        "macOS calls this Accessibility. Meeting Pulse uses it to check two things: whether Chrome has a Google Meet call open, and whether Slack has a huddle running."
      )
      Text(
        "It does not read page contents, meeting names, links, or anything you type. It never asks for screen recording, and it never touches your screen, microphone, or camera."
      )
      Text(
        "Three things leave this Mac: one word (free, on a call, or no signal), whether calls are okay right now, and the name you choose to show."
      )
      Button("Open Accessibility settings") {
        if let url = URL(
          string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) {
          NSWorkspace.shared.open(url)
        }
      }
    }
    .padding(24)
    .frame(width: 460)
  }
}

struct PairingWindow: View {
  @Bindable var model: OwnerAppModel

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Share the viewer link")
        .font(.title2.weight(.semibold))
      Text(
        "The link stays active until you rotate or revoke it. Anyone who has it can view the status."
      )
      if let pairingCode = model.pairingCode {
        Text(pairingCode.displayCode)
          .font(.system(.title, design: .monospaced))
        HStack {
          Button("Copy code") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(
              pairingCode.displayCode,
              forType: .string
            )
          }
        }
        ForEach(model.pairingLinks, id: \.absoluteString) { pairingLink in
          VStack(alignment: .leading, spacing: 8) {
            Text(pairingLink.absoluteString)
              .font(.caption)
              .textSelection(.enabled)
              .foregroundStyle(.secondary)
            Button("Copy \(pairingLink.host ?? "viewer") link") {
              NSPasteboard.general.clearContents()
              NSPasteboard.general.setString(
                pairingLink.absoluteString,
                forType: .string
              )
            }
          }
        }
        HStack {
          Button("Rotate viewer link…") {
            model.showingRotateConfirmation = true
          }
          Button("Revoke access…", role: .destructive) {
            model.showingRevokeConfirmation = true
          }
        }
      } else {
        Text("Create a viewer link from the menu bar to share it.")
          .foregroundStyle(.secondary)
      }
    }
    .padding(24)
    .frame(width: 460)
    .confirmationDialog(
      "Rotate viewer link?",
      isPresented: $model.showingRotateConfirmation,
      titleVisibility: .visible
    ) {
      Button("Rotate link", role: .destructive) {
        model.rotatePairingCode()
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("The current link and viewer session will stop working.")
    }
    .confirmationDialog(
      "Revoke viewer access?",
      isPresented: $model.showingRevokeConfirmation,
      titleVisibility: .visible
    ) {
      Button("Revoke access", role: .destructive) {
        model.revokePairingCode()
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("The current link will stop working. You can create a new one later.")
    }
  }
}

struct SettingsWindow: View {
  @Bindable var model: OwnerAppModel

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Display name")
        .font(.title2.weight(.semibold))
      TextField("Optional name", text: $model.displayName)
        .textFieldStyle(.roundedBorder)
      Button("Save name") {
        model.saveDisplayName()
      }
      Toggle(
        "Launch at login",
        isOn: Binding(
          get: { model.launchAtLogin },
          set: { model.setLaunchAtLogin($0) }
        )
      )
      Text("The name appears above the meeting status on the viewer.")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .padding(24)
    .frame(width: 420)
  }
}

struct RecoveryWindow: View {
  @Bindable var model: OwnerAppModel

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Save this phrase")
        .font(.title2.weight(.semibold))
      Text(
        "If this Mac is wiped or replaced, this phrase is the only way to keep your connection without asking her to pair again. Anyone who has it can take over publishing your status, so store it where you keep passwords."
      )
      if let recoveryPhrase = model.recoveryPhrase {
        Text(recoveryPhrase)
          .font(.system(.body, design: .monospaced))
          .textSelection(.enabled)
        Button("Copy phrase") {
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(recoveryPhrase, forType: .string)
        }
      } else {
        Text("The recovery phrase is not available.")
          .foregroundStyle(.secondary)
      }
    }
    .padding(24)
    .frame(width: 460)
  }
}

struct DiagnosticsWindow: View {
  let model: OwnerAppModel

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Diagnostics")
        .font(.title2.weight(.semibold))
      LabeledContent("State", value: model.state.rawValue)
      LabeledContent("Status", value: model.statusLine)
      LabeledContent("Connection", value: model.connectionLine)
      Text(
        "Meeting Pulse never records meeting titles, links, participants, audio, video, or screen contents."
      )
      .font(.caption)
      .foregroundStyle(.secondary)
    }
    .padding(24)
    .frame(width: 460)
  }
}
