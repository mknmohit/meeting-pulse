import AppKit
import MPCore
import MPDetection
import MPSupport
import MPSync
import MPUI
import Observation
import SwiftUI
import WebKit

typealias MeetingPulseState = MPCore.State

@main
struct MeetingPulseApp: App {
  @SwiftUI.State private var model: OwnerAppModel
  @SwiftUI.State private var launchCoordinator: AppLaunchCoordinator
  @SwiftUI.State private var store: PulseStore
  @SwiftUI.State private var actions: AppPulseActions
  @NSApplicationDelegateAdaptor(MeetingPulseAppDelegate.self)
  private var appDelegate

  init() {
    let model = OwnerAppModel()
    let store = PulseStore()
    _model = SwiftUI.State(initialValue: model)
    _launchCoordinator = SwiftUI.State(initialValue: AppLaunchCoordinator())
    _store = SwiftUI.State(initialValue: store)
    _actions = SwiftUI.State(initialValue: AppPulseActions(store: store, model: model))
    if !NSApplication.shared.setActivationPolicy(.regular) {
      NSLog("Meeting Pulse: failed to show the Dock icon.")
    }
  }

  @SceneBuilder
  var body: some Scene {
    MenuBarExtra {
      if FeatureFlag.macNative {
        MPUI.MenuBarContent(store: store, actions: actions)
      } else {
        MenuBarView(model: model)
      }
    } label: {
      NativeMenuBarLabel(store: store, model: model, actions: actions) {
        await launchCoordinator.start(
          model: model,
          store: FeatureFlag.macNative ? store : nil
        )
        appDelegate.terminationHandler = {
          await model.runtime?.gracefulQuit()
        }
      }
    }
    .menuBarExtraStyle(.menu)

    Window(MPString.station.windowTitle, id: "station") {
      MPUI.StationWindow(store: store, actions: actions)
    }
    .defaultSize(width: 940, height: 620)
    .windowResizability(.contentMinSize)
    .commands {
      MPUI.StationCommands(actions: actions)
    }

    Window(MPString.onboardingStep1.headline, id: "onboarding") {
      if FeatureFlag.macNative {
        MPUI.OnboardingWindow(store: store, actions: actions)
      } else {
        OnboardingWindow()
      }
    }
    .defaultSize(width: 560, height: 480)
    .windowResizability(.contentSize)

    Window(MPString.pairing, id: "pairing") {
      if FeatureFlag.macNative {
        MPUI.PairingWindow(store: store, actions: actions)
      } else {
        PairingWindow(model: model)
      }
    }
    .windowResizability(.contentSize)

    Window(MPString.settings, id: "settings") {
      if FeatureFlag.macNative {
        MPUI.SettingsWindow(store: store, actions: actions)
      } else {
        SettingsWindow(model: model)
      }
    }
    .windowResizability(.contentMinSize)

    Window(MPString.recovery, id: "recovery") {
      if FeatureFlag.macNative {
        MPUI.RecoveryWindow(store: store, actions: actions)
      } else {
        RecoveryWindow(model: model)
      }
    }
    .windowResizability(.contentSize)

    Window(MPString.diagnostics.headline, id: "diagnostics") {
      if FeatureFlag.macNative {
        MPUI.DiagnosticsWindow(store: store)
      } else {
        DiagnosticsWindow(model: model)
      }
    }
    .windowResizability(.contentSize)
  }
}

private struct NativeMenuBarLabel: View {
  let store: PulseStore
  let model: OwnerAppModel
  let actions: AppPulseActions
  let start: @MainActor () async -> Void
  @Environment(\.openWindow) private var openWindow

  init(
    store: PulseStore,
    model: OwnerAppModel,
    actions: AppPulseActions,
    start: @escaping @MainActor () async -> Void
  ) {
    self.store = store
    self.model = model
    self.actions = actions
    self.start = start
  }

  private var menuBarState: MeetingPulseState {
    FeatureFlag.macNative ? store.effectiveState : model.state
  }

  var body: some View {
    Group {
      HeartThreadMenuIcon(state: menuBarState)
        .opacity(FeatureFlag.macNative && store.deleteCompleted ? 0.4 : 1)
    }
    .task {
      if FeatureFlag.macNative {
        actions.configure(openWindow: { id in
          NSApp.activate()
          openWindow(id: id)
        })
      }
      await start()
      if FeatureFlag.macNative,
         !store.hasCompletedOnboarding || store.setupFailure != nil {
        actions.showOnboarding()
      }
    }
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
  private let store: PulseStore?
  private let scheduler: DetectionScheduler
  private let transport: any StatusTransport
  private let recovery: RecoveryService
  private let secrets: any SecretStore
  private let existingRegistration: DeviceRegistration?
  private let pairing: PairingService
  private let viewerOrigins: [URL]
  private let networkMonitor: NetworkMonitor
  private var task: Task<Void, Never>?
  private var networkTask: Task<Void, Never>?
  private var sync: SyncCoordinator?
  private var overrideStore: ManualOverrideStore?

  init(
    model: OwnerAppModel,
    store: PulseStore? = nil,
    transport: any StatusTransport,
    recovery: RecoveryService,
    secrets: any SecretStore,
    existingRegistration: DeviceRegistration?,
    viewerOrigins: [URL]
  ) {
    self.model = model
    self.store = store
    self.transport = transport
    self.recovery = recovery
    self.secrets = secrets
    self.existingRegistration = existingRegistration
    self.viewerOrigins = viewerOrigins
    networkMonitor = NetworkMonitor()
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
    await restartHeartbeat()
    networkMonitor.start()
    let networkChanges = networkMonitor.changes
    networkTask = Task { [weak self] in
      for await online in networkChanges {
        guard let self else {
          return
        }
        self.store?.isOnline = online
        if !online {
          self.store?.publishState = .offline
        }
      }
    }
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
        let readingSnapshot = SchedulerReadingSnapshot(
          meet: reading.meet,
          slack: reading.slack,
          accessibilityGranted: reading.accessibilityGranted
        )
        if let sync = self.sync {
          self.store?.publishState = .publishing
          await sync.submit(
            StatusPayload(
              state: status.state,
              callOkay: status.callOkay,
              overrideMode: self.model.manualOverrideState,
              overrideExpiresAt: self.model.manualOverride?.expiresAtWall
            )
          )
          let syncState = await sync.currentState
          self.store?.syncState = Self.mapSyncState(syncState)
          self.store?.lastPublished = await sync.lastSuccessfulSync
          self.store?.publishState = Self.mapPublishState(
            syncState: syncState,
            lastPublished: await sync.lastSuccessfulSync
          )
          if syncState == .idle {
            self.model.connectionLine = MPString.mast.lastPublishedJustNow
          }
        }
        self.store?.apply(
          status: status,
          reading: readingSnapshot,
          publishedAt: await self.sync?.lastSuccessfulSync
        )
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

  func listViewers() async throws -> [ViewerRecord] {
    try await transport.listViewers()
  }

  func revokeViewer(_ id: UUID) async throws {
    try await transport.revokeViewer(id)
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
    networkTask?.cancel()
    networkTask = nil
    networkMonitor.stop()
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
    await restartHeartbeat()
    await scheduler.requestImmediateSample()
  }

  private func restartHeartbeat() async {
    guard let sync else {
      return
    }
    let interval: Duration
    if store?.mode != .automatic {
      interval = .seconds(30)
    } else if store?.stationVisible == false {
      interval = .seconds(300)
    } else {
      interval = .seconds(60)
    }
    await sync.startHeartbeat(interval: interval) { [weak self] in
      guard let self else {
        return StatusPayload(
          state: .unavailable,
          callOkay: false,
          overrideMode: nil,
          overrideExpiresAt: nil
        )
      }
      return await self.currentPayload()
    }
  }

  private func currentPayload() -> StatusPayload {
    StatusPayload(
      state: store?.effectiveState ?? model.state,
      callOkay: store?.callsOkay ?? model.callOkay,
      overrideMode: store?.mode == .automatic ? nil : (store?.effectiveState ?? model.manualOverrideState),
      overrideExpiresAt: store?.overrideExpiry ?? model.manualOverride?.expiresAtWall
    )
  }

  private static func mapSyncState(_ state: SyncCoordinator.State) -> SyncState {
    switch state {
    case .idle:
      return .idle
    case .retrying:
      return .retrying
    case .superseded:
      return .superseded
    }
  }

  private static func mapPublishState(
    syncState: SyncCoordinator.State,
    lastPublished: Date?
  ) -> PublishState {
    switch syncState {
    case .idle:
      if let lastPublished {
        return .published(at: lastPublished)
      }
      return .never
    case .retrying:
      return .retrying
    case .superseded:
      return .superseded
    }
  }
}

@MainActor
@Observable
final class OwnerAppModel {
  var state: MeetingPulseState = .unavailable
  var callOkay = false
  var statusLine = MPString.board.genericHeadline
  var connectionLine = MPString.error.unreachable
  var displayName = ""
  var launchAtLogin = false
  var recoveryPhrase: String?
  var pairingCode: PairingCodeResult?
  var pairingLinks: [URL] = []
  var showingRotateConfirmation = false
  var showingRevokeConfirmation = false
  var showingDeleteConfirmation = false
  var runtime: OwnerRuntime?
  var runtimeStore: PulseStore?
  var manualOverride: ManualOverride?

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
        connectionLine = MPString.error.unreachable
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
    runtimeStore?.setOverride(override)
    if let override {
      state = override.state
      statusLine = override.state == .busy
        ? MPString.mast.modeBusy
        : MPString.menuBar.availableOverride
    }
  }

  func applyManualOverride(_ override: ManualOverride) {
    manualOverride = override
    runtimeStore?.setOverride(override)
    state = override.state
    statusLine = override.state == .busy
      ? MPString.mast.modeBusy
      : MPString.menuBar.availableOverride
  }

  func clearManualOverride() {
    manualOverride = nil
    runtimeStore?.setOverride(nil)
    statusLine = MPString.mast.reasonAutomatic
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
        connectionLine = MPString.error.unreachable
      }
    }
  }

  func createPairingCode() {
    Task { @MainActor in
      do {
        guard let runtime else {
          throw OwnerRuntimeError.unavailable
        }
        let result = try await runtime.createPairingCode()
        pairingCode = result
        pairingLinks = try runtime.pairingLinks(for: result)
      } catch {
        connectionLine = MPString.error.unreachable
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
        connectionLine = MPString.error.unreachable
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
        connectionLine = MPString.error.unreachable
      }
    }
  }

  func refreshAndPublish() {
    Task { @MainActor in
      guard let runtime else {
        connectionLine = MPString.error.starting
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
        connectionLine = MPString.error.unreachable
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
      connectionLine = MPString.error.loginItem
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
        statusLine = MPString.board.genericHeadline
        connectionLine = MPString.mast.resetComplete
        displayName = ""
        launchAtLogin = false
        recoveryPhrase = nil
        pairingCode = nil
        pairingLinks = []
      } catch {
        connectionLine = MPString.error.unreachable
      }
    }
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
    runtimeStore?.apply(status: status)
    statusLine =
      switch status.state {
      case .available:
        MPString.mast.reasonAutomatic
      case .busy:
        MPString.mast.modeBusy
      case .unavailable:
        MPString.board.genericHeadline
      }
  }

}

private enum OwnerRuntimeError: Error {
  case unavailable
  case invalidRecoveryPhrase
}

@MainActor
@Observable
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
  private var permissionTask: Task<Void, Never>?
  private(set) var state: LaunchState = .starting

  func start(model: OwnerAppModel, store: PulseStore? = nil) async {
    NSLog("Meeting Pulse launch sequence started")
    let migratedDisplayName = UserDefaults.standard.string(forKey: "owner.displayName") ?? ""
    store?.displayName = migratedDisplayName
    model.displayName = migratedDisplayName
    guard state == .starting else {
      return
    }
    do {
      instanceLock = try SingleInstanceLock()
      let configuration = try AppConfiguration.load()
      NSLog("Meeting Pulse configuration loaded")
      let installLocationIsValid = InstallLocation().isValid()
      if !installLocationIsValid {
        NSLog("Meeting Pulse install location is invalid")
        store?.installLocationIsValid = false
      }
      let coordinator = PermissionCoordinator()
      permissionCoordinator = coordinator
      await coordinator.start()
      if let store {
        let permissionChanges = await coordinator.changes
        permissionTask = Task { [weak store] in
          for await granted in permissionChanges {
            store?.accessibilityGranted = granted
          }
        }
      }
      NSLog("Meeting Pulse permission coordinator started")
      try LegacyStorageReset().resetIfNeeded()
      store?.hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "setup.completed")
      let secrets = LocalSecretStore()
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
        turnstile: gate,
        secrets: secrets
      )
      let recovery = RecoveryService(transport: transport, secrets: secrets)
      let runtime = OwnerRuntime(
        model: model,
        store: store,
        transport: transport,
        recovery: recovery,
        secrets: secrets,
        existingRegistration: existingRegistration,
        viewerOrigins: configuration.viewerOrigins
      )
      self.runtime = runtime
      model.runtime = runtime
      model.runtimeStore = store
      model.loadLaunchAtLogin()
      try await runtime.start()
      try model.loadStoredPairingCode()
      try model.loadRecoveryPhrase()
      store?.pairingCode = model.pairingCode?.rawCode
      store?.viewerLinks = model.pairingLinks
      store?.recoveryPhrase = model.recoveryPhrase
      store?.launchAtLogin = model.launchAtLogin
      turnstilePanel?.close()
      turnstilePanel = nil
      NSLog("Meeting Pulse detection runtime started")
      state = installLocationIsValid ? .running : .wrongInstallLocation
    } catch let error as AppConfiguration.ConfigurationError {
      NSLog("Meeting Pulse configuration error: %@", error.description)
      store?.setupFailure = error.description
      state = .setupRequired(error.description)
    } catch {
      NSLog("Meeting Pulse launch error: %@", String(describing: error))
      store?.setupFailure = MPString.error.genericSetup
      state = .setupRequired(MPString.error.genericSetup)
    }
  }

  private enum LaunchError: Error {
    case turnstileResourceMissing
    case localStorageUnavailable
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
      throw LaunchError.localStorageUnavailable
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
    panel.title = MPString.station.windowTitle
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
        MPString.thisMac.deleteTitle,
        isPresented: $model.showingDeleteConfirmation,
        titleVisibility: .visible
      ) {
        Button(MPString.thisMac.deleteEverything, role: .destructive) {
          model.deleteEverything()
        }
        Button(MPString.cancel, role: .cancel) {}
      } message: {
        Text(MPString.thisMac.deleteBody)
      }
    Text(model.connectionLine)
    Divider()
    Menu(MPString.menuBar.setBusy) {
      Button(MPString.mast.durationLabel(.m15)) { model.setBusy(duration: .m15) }
      Button(MPString.mast.durationLabel(.m30)) { model.setBusy(duration: .m30) }
      Button(MPString.mast.durationLabel(.m45)) { model.setBusy(duration: .m45) }
      Button(MPString.mast.durationLabel(.h1)) { model.setBusy(duration: .h1) }
      Button(MPString.mast.durationLabel(.h2)) { model.setBusy(duration: .h2) }
      Button(MPString.mast.durationLabel(.h4)) { model.setBusy(duration: .h4) }
      Button(MPString.mast.durationLabel(.untilCleared)) { model.setBusy(duration: .untilCleared) }
    }
    Menu(MPString.menuBar.setAvailable) {
      Button(MPString.mast.durationLabel(.m15)) { model.setAvailable(duration: .m15) }
      Button(MPString.mast.durationLabel(.m30)) { model.setAvailable(duration: .m30) }
      Button(MPString.mast.durationLabel(.m45)) { model.setAvailable(duration: .m45) }
      Button(MPString.mast.durationLabel(.h1)) { model.setAvailable(duration: .h1) }
      Button(MPString.mast.durationLabel(.h2)) { model.setAvailable(duration: .h2) }
      Button(MPString.mast.durationLabel(.h4)) { model.setAvailable(duration: .h4) }
      Button(MPString.mast.durationLabel(.untilCleared)) { model.setAvailable(duration: .untilCleared) }
    }
    Button(MPString.menuBar.backToAutomatic) { model.clearOverride() }
    Toggle(
      MPString.menuBar.callsAreOkay,
      isOn: Binding(
        get: { model.callOkay },
        set: { model.setCallOkay($0) }
      )
    )
    Button(MPString.station.checkNow) { model.refreshAndPublish() }
    Divider()
    Button(MPString.thisMac.name) { openWindow(id: "settings") }
    Button(MPString.sharing.createLink) {
      model.createPairingCode()
      openWindow(id: "pairing")
    }
    Button(MPString.sharing.createNewLink) {
      model.showingRotateConfirmation = true
    }
    .disabled(model.pairingCode == nil)
    Button(MPString.sharing.stopSharing) {
      model.showingRevokeConfirmation = true
    }
    .disabled(model.pairingCode == nil)
    Button(MPString.thisMac.showRecoveryPhrase) { openWindow(id: "recovery") }
    Button(MPString.diagnostics.headline) { openWindow(id: "diagnostics") }
    Button(MPString.thisMac.deleteEverything) {
      model.showingDeleteConfirmation = true
    }
    Divider()
    Button(MPString.menuBar.quit) {
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
      return MPString.board.busyHeadline
    case .available:
      return MPString.mast.reasonAutomatic
    case .unavailable:
      return MPString.board.genericHeadline
    }
  }
}

struct OnboardingWindow: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(MPString.onboardingStep2.headline)
        .font(.title2.weight(.semibold))
      Text(MPString.onboardingStep2.body)
      Text(MPString.station.readsWindowTitles)
      Button(MPString.onboardingStep2.cta) {
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
      Text(MPString.sharing.headline)
        .font(.title2.weight(.semibold))
      Text(MPString.sharing.body)
      if let pairingCode = model.pairingCode {
        Text(pairingCode.displayCode)
          .font(.system(.title, design: .monospaced))
        HStack {
          Button(MPString.sharing.copyCode) {
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
            Button(MPString.sharing.copyHostLink(pairingLink.host ?? MPString.sharing.unnamedOwner)) {
              NSPasteboard.general.clearContents()
              NSPasteboard.general.setString(
                pairingLink.absoluteString,
                forType: .string
              )
            }
          }
        }
        HStack {
          Button(MPString.sharing.createNewLink) {
            model.showingRotateConfirmation = true
          }
          Button(MPString.sharing.stopSharing, role: .destructive) {
            model.showingRevokeConfirmation = true
          }
        }
      } else {
        Text(MPString.sharing.emptyBody)
          .foregroundStyle(.secondary)
      }
    }
    .padding(24)
    .frame(width: 460)
    .confirmationDialog(
      MPString.sharing.createNewLinkTitle,
      isPresented: $model.showingRotateConfirmation,
      titleVisibility: .visible
    ) {
      Button(MPString.sharing.createNewLink, role: .destructive) {
        model.rotatePairingCode()
      }
      Button(MPString.cancel, role: .cancel) {}
    } message: {
      Text(MPString.sharing.createNewLinkBody)
    }
    .confirmationDialog(
      MPString.sharing.stopSharingTitle,
      isPresented: $model.showingRevokeConfirmation,
      titleVisibility: .visible
    ) {
      Button(MPString.sharing.stopSharing, role: .destructive) {
        model.revokePairingCode()
      }
      Button(MPString.cancel, role: .cancel) {}
    } message: {
      Text(MPString.sharing.stopSharingBody)
    }
  }
}

struct SettingsWindow: View {
  @Bindable var model: OwnerAppModel

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(MPString.thisMac.headline)
        .font(.title2.weight(.semibold))
      TextField(MPString.thisMac.optionalName, text: $model.displayName)
        .textFieldStyle(.roundedBorder)
      Button(MPString.thisMac.saveName) {
        model.saveDisplayName()
      }
      Toggle(
        MPString.thisMac.openAtLogin,
        isOn: Binding(
          get: { model.launchAtLogin },
          set: { model.setLaunchAtLogin($0) }
        )
      )
      Text(MPString.thisMac.viewerNameDetail)
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
      Text(MPString.thisMac.recoveryPhrase)
        .font(.title2.weight(.semibold))
      Text(MPString.thisMac.recoveryDetail)
      if let recoveryPhrase = model.recoveryPhrase {
        Text(recoveryPhrase)
          .font(.system(.body, design: .monospaced))
          .textSelection(.enabled)
        Button(MPString.thisMac.copyPhrase) {
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(recoveryPhrase, forType: .string)
        }
      } else {
        Text(MPString.thisMac.recoveryUnavailable)
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
      Text(MPString.diagnostics.headline)
        .font(.title2.weight(.semibold))
      LabeledContent(MPString.diagnostics.state, value: model.statusLine)
      LabeledContent(MPString.diagnostics.connection, value: model.connectionLine)
      Text(MPString.diagnostics.privacy)
      .font(.caption)
      .foregroundStyle(.secondary)
    }
    .padding(24)
    .frame(width: 460)
  }
}
