import AppKit
import MPCore
import MPDetection
import MPSupport
import MPSync
import MPUI
import Observation
import SwiftUI

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
    // The delegate is created by AppKit before this init runs; share the
    // actions handle so Dock-icon / Launchpad reopens can surface the station.
    appDelegate.pulseActions = _actions.wrappedValue
    // Dock visibility tracks the station window: only show the Dock icon while
    // the station is visible. The menu-bar item is unaffected by activation
    // policy, so it stays in either mode. Start in .accessory because the
    // station has not appeared yet at launch.
    DockVisibilityCoordinator.shared.start(store: store)
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
      NativeMenuBarLabel(
        store: store,
        model: model,
        actions: actions,
        start: {
          await launchCoordinator.start(
            model: model,
            store: FeatureFlag.macNative ? store : nil,
            openStation: {
              if FeatureFlag.macNative {
                actions.openStation()
              }
            }
          )
          appDelegate.terminationHandler = {
            await model.runtime?.gracefulQuit()
          }
        },
        retryLaunch: {
          await launchCoordinator.retryLaunch(
            model: model,
            store: FeatureFlag.macNative ? store : nil,
            openStation: {
              if FeatureFlag.macNative {
                actions.openStation()
              }
            }
          )
        }
      )
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
  let retryLaunch: @MainActor () async -> Void
  @Environment(\.openWindow) private var openWindow

  init(
    store: PulseStore,
    model: OwnerAppModel,
    actions: AppPulseActions,
    start: @escaping @MainActor () async -> Void,
    retryLaunch: @escaping @MainActor () async -> Void
  ) {
    self.store = store
    self.model = model
    self.actions = actions
    self.start = start
    self.retryLaunch = retryLaunch
  }

  private var menuBarState: MeetingPulseState {
    if FeatureFlag.macNative {
      return store.isFresh ? store.effectiveState : .unavailable
    }
    return model.state
  }

  private var menuBarCallsOkay: Bool {
    FeatureFlag.macNative ? store.callsOkay : model.callOkay
  }

  var body: some View {
    Group {
      HeartThreadMenuIcon(state: menuBarState, callsOkay: menuBarCallsOkay)
        .opacity(FeatureFlag.macNative && store.deleteCompleted ? 0.4 : 1)
    }
    .task {
      if FeatureFlag.macNative {
        actions.configure(
          openWindow: { id in
            // `ignoringOtherApps: true` is required so the station window can
            // take focus when launched from Launchpad or the Dock. Without it,
            // the window opens behind whatever app the user launched us from.
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: id)
          },
          retryLaunch: retryLaunch
        )
      }
      await start()
      if FeatureFlag.macNative {
        // Always surface the station on launch so the Dock icon mirrors a real
        // window. Launchpad / Dock activations route through the same opener
        // via `applicationShouldHandleReopen` in the app delegate.
        actions.openStation()
      }
    }
  }
}

@MainActor
final class MeetingPulseAppDelegate: NSObject, NSApplicationDelegate {
  var terminationHandler: (@MainActor () async -> Void)?
  var pulseActions: AppPulseActions?
  private var terminationStarted = false
  private static let terminationWatchdog: Duration = .seconds(3)

  func applicationShouldHandleReopen(
    _ sender: NSApplication,
    hasVisibleWindows flag: Bool
  ) -> Bool {
    // Surfacing the station here keeps the Dock icon and the window in sync:
    // when the user clicks the Dock icon (or re-activates the app from
    // Launchpad) the station window appears, so the Dock icon does not stay
    // visible without a real window.
    pulseActions?.openStation()
    return true
  }

  func applicationShouldTerminate(
    _: NSApplication
  ) -> NSApplication.TerminateReply {
    // Cmd+Q while the station is visible should only close the station window,
    // not terminate the app. The menu-bar "Quit Meeting Pulse" item calls
    // `actions.quit()` which sets `requestedQuitFromMenu` so we can honor the
    // explicit exit. When the station is hidden, the dock icon is gone and
    // the app is in `.accessory` mode; a Cmd+Q then targets whatever app the
    // user has focused, so terminating here is the right answer.
    if let actions = pulseActions,
       !actions.requestedQuitFromMenu,
       actions.isStationVisible {
      actions.closeStation()
      return .terminateCancel
    }
    guard let terminationHandler, !terminationStarted else {
      return .terminateNow
    }
    terminationStarted = true
    Task { @MainActor in
      let terminationTask = Task { @MainActor in
        await terminationHandler()
      }
      let timeoutTask = Task { @MainActor in
        try? await Task.sleep(for: Self.terminationWatchdog)
        if !terminationTask.isCancelled {
          NSLog("Meeting Pulse: graceful quit exceeded watchdog; forcing terminate.")
          terminationTask.cancel()
          // Force-terminate so the app does not hang in `.terminateLater`
          // when the graceful quit fails to complete in time.
          NSApp.reply(toApplicationShouldTerminate: true)
        }
      }
      await terminationTask.value
      timeoutTask.cancel()
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
  private let overrideOperationQueue = SerialOperationQueue()

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
      nonce: registration.instanceNonce,
      onStateChange: { [weak self] state in
        guard let self else {
          return
        }
        self.store?.syncState = Self.mapSyncState(state)
        switch state {
        case .retrying:
          self.store?.publishState = .retrying
        case .superseded:
          self.store?.publishState = .superseded
        case .idle:
          if let lastPublished = await self.sync?.lastSuccessfulSync {
            self.store?.publishState = .published(at: lastPublished)
          }
        }
      },
      nonceRefresh: { [weak self] in
        guard let self else {
          return nil
        }
        // The device was re-bound elsewhere, so the server side nonce moved
        // on. Registering the stored device again returns the current nonce.
        return try? await self.recovery.registerStoredDevice()?.instanceNonce
      },
      deviceRecovery: { [weak self] in
        guard let self else {
          return nil
        }
        // The device is no longer bound to the signed-in identity. The
        // recovery phrase re-binds it (and rotates the instance nonce).
        return try? await self.recovery.registerStoredDevice()
      }
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
        if online {
          // The network came back: publish the pending status right away
          // instead of waiting for the retry backoff to expire.
          await self.sync?.connectionRestored()
        } else {
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
          "Meeting Pulse reading meet=%@ slack=%@ permission=%d health=%@/%@",
          reading.meet.rawValue,
          reading.slack.rawValue,
          reading.accessibilityGranted,
          reading.meetHealth.diagnosticCode,
          reading.slackHealth.diagnosticCode
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
        let attention = SourceAttention(
          meet: reading.meet,
          slack: reading.slack,
          meetHealth: reading.meetHealth,
          slackHealth: reading.slackHealth
        )
        self.model.applyAutomatic(status, attention: attention)
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
      return try await recovery.registerStoredDevice() ?? existingRegistration
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

  func deleteViewer(_ id: UUID) async throws {
    try await transport.deleteViewer(id)
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
  ) async throws -> ManualOverride {
    try await enqueueOverrideOperation { [weak self] in
      guard let self, let overrideStore = self.overrideStore else {
        throw OwnerRuntimeError.unavailable
      }
      let override = try await overrideStore.set(state: state, duration: duration)
      self.model.applyManualOverride(override)
      await self.restartHeartbeat()
      await self.publishOverride(override)
      return override
    }
  }

  func clearOverride() async throws {
    try await enqueueOverrideOperation { [weak self] in
      guard let self, let overrideStore = self.overrideStore else {
        throw OwnerRuntimeError.unavailable
      }
      try await overrideStore.clear()
      self.model.clearManualOverride()
      await self.restartHeartbeat()
      await self.scheduler.requestImmediateSample()
    }
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
      try? await Task.sleep(for: .seconds(1))
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
    await overrideStore?.stop()
    overrideStore = nil
    await overrideOperationQueue.cancel()
    await sync?.stop()
    sync = nil
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
    if override == nil, let overrideStore, await overrideStore.current != nil {
      return
    }
    if let override {
      model.applyManualOverride(override)
    } else {
      model.clearManualOverride()
    }
    await restartHeartbeat()
    await scheduler.requestImmediateSample()
  }

  private func enqueueOverrideOperation<T: Sendable>(
    _ operation: @escaping @MainActor @Sendable () async throws -> T
  ) async throws -> T {
    try await overrideOperationQueue.enqueue(operation)
  }

  private func restartHeartbeat() async {
    guard let sync else {
      return
    }
    let interval: Duration
    if store?.mode != .automatic {
      interval = .seconds(30)
    } else if store?.stationVisible == false {
      // The viewer treats a status as stale after 180 seconds, so the
      // heartbeat has to stay well below that window even when the station
      // window is hidden.
      interval = .seconds(60)
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

  func menuBarStatusLine(at now: Date) -> String {
    guard let override = manualOverride, let expiry = override.expiresAtWall else {
      return statusLine
    }
    let mode: PulseMode = override.state == .busy ? .busy : .available
    return ReasonLineBuilder.overrideLine(
      mode: mode,
      overrideExpiry: expiry,
      presentation: .menuBar,
      now: now
    )
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
        _ = try await runtime.setOverride(state: state, duration: duration)
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

  func applyAutomatic(_ status: EffectiveStatus, attention: SourceAttention = .none) {
    guard manualOverride == nil else {
      return
    }
    NSLog(
      "Meeting Pulse reducer state=%@ reason=%@ attention=%@",
      status.state.rawValue,
      status.reason.rawValue,
      String(describing: attention)
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
        Self.unavailableLine(status: status, attention: attention)
      }
  }

  /// The menu bar line for an unavailable status.
  ///
  /// The board keeps its plain headline, but the menu bar names the source
  /// that needs attention so the user knows where to look.
  private static func unavailableLine(
    status: EffectiveStatus,
    attention: SourceAttention
  ) -> String {
    switch status.reason {
    case .permissionDenied:
      return MPString.mast.reasonAccessibilityMissing
    case .untrustedSource:
      guard attention != .none else {
        return MPString.board.genericHeadline
      }
      return MPString.mast.sourceNeedsAttention(sourceName(for: attention))
    case .manualOverride, .confirmedActiveSource, .allSourcesInactive:
      return MPString.board.genericHeadline
    }
  }

  private static func sourceName(for attention: SourceAttention) -> String {
    switch attention {
    case .none:
      ""
    case .googleMeet:
      MPString.station.googleMeet
    case .slackHuddle:
      MPString.station.slack
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
  private var turnstileGate: TurnstileGate?
  private var permissionTask: Task<Void, Never>?
  private var launchRetryTask: Task<Void, Never>?
  private var launchRetryCount = 0
  /// Upper bound for automatic launch retries so a permanent failure cannot
  /// loop forever.
  private static let maxLaunchAutoRetries = 5
  private static let launchRetryDelay: Duration = .seconds(10)
  private(set) var state: LaunchState = .starting

  func start(
    model: OwnerAppModel,
    store: PulseStore? = nil,
    openStation: @escaping @MainActor () -> Void = {},
    allowIdentityRecovery: Bool = true
  ) async {
    NSLog("Meeting Pulse launch sequence started")
    let migratedDisplayName = UserDefaults.standard.string(forKey: "owner.displayName") ?? ""
    store?.displayName = migratedDisplayName
    model.displayName = migratedDisplayName
    guard state == .starting else {
      return
    }
    let secrets = LocalSecretStore()
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
        permissionTask = Task { [weak self, weak store] in
          for await granted in permissionChanges {
            guard let self else {
              return
            }
            store?.accessibilityGranted = granted
            await self.runtime?.refreshAndPublish()
          }
        }

      }
      NSLog("Meeting Pulse permission coordinator started")
      try LegacyStorageReset().resetIfNeeded()
      store?.hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "setup.completed")
      let existingRegistration = try existingRegistration(from: secrets)
      guard
        let htmlURL = Bundle.main.url(
          forResource: "turnstile",
          withExtension: "html"
        )
      else {
        throw LaunchError.turnstileResourceMissing
      }
      let provider = LazyTurnstileProvider(
        siteKey: configuration.turnstileSiteKey,
        htmlURL: htmlURL,
        baseURL: configuration.viewerOrigins[0],
        onCreated: { @MainActor [weak store] view in
          store?.turnstileWebView = view
        }
      )
      let gate = TurnstileGate(
        provider: provider,
        onTokenStarted: { @MainActor [weak store] in
          store?.turnstilePresentation = .verifying
          openStation()
        },
        onTokenFinished: { @MainActor [weak store] in
          store?.turnstileWebView = nil
          store?.turnstilePresentation = .hidden
        }
      )
      turnstileGate = gate
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
      store?.turnstileWebView = nil
      store?.turnstilePresentation = .hidden
      await turnstileGate?.shutdown()
      turnstileGate = nil
      store?.setupFailure = nil
      store?.setupFailureHeadline = MPString.error.genericSetup
      NSLog("Meeting Pulse detection runtime started")
      launchRetryCount = 0
      launchRetryTask?.cancel()
      launchRetryTask = nil
      state = installLocationIsValid ? .running : .wrongInstallLocation
    } catch let error as SupabaseStatusTransport.TransportError
      where error == .identityLost && allowIdentityRecovery {
      await cleanupAfterFailedLaunch(model: model, store: store)
      do {
        for key in SecretKey.allCases {
          try secrets.delete(key)
        }
      } catch {
        let detail = Self.launchFailureDetail(for: error)
        NSLog("Meeting Pulse identity reset error: %@", detail)
        store?.turnstileWebView = nil
        store?.turnstilePresentation = .failed
        store?.setupFailureHeadline = MPString.error.launchFailed
        store?.setupFailure = detail
        state = .setupRequired(detail)
        return
      }
      state = .starting
      await start(
        model: model,
        store: store,
        openStation: openStation,
        allowIdentityRecovery: false
      )
    } catch let error as AppConfiguration.ConfigurationError {
      await cleanupAfterFailedLaunch(model: model, store: store)
      NSLog("Meeting Pulse configuration error: %@", error.description)
      store?.turnstileWebView = nil
      store?.turnstilePresentation = .failed
      store?.setupFailureHeadline = MPString.error.genericSetup
      store?.setupFailure = error.description
      state = .setupRequired(error.description)
    } catch {
      await cleanupAfterFailedLaunch(model: model, store: store)
      let detail = Self.launchFailureDetail(for: error)
      NSLog("Meeting Pulse launch error: %@", detail)
      store?.turnstileWebView = nil
      store?.turnstilePresentation = .failed
      store?.setupFailureHeadline = MPString.error.launchFailed
      store?.setupFailure = detail
      state = .setupRequired(detail)
      scheduleLaunchRetry(model: model, store: store, openStation: openStation)
    }
  }

  /// Waits for connectivity and retries the launch automatically.
  ///
  /// A launch that failed while the machine was offline used to require a
  /// restart: the setup screen was shown and nothing else happened when the
  /// network came back.
  private func scheduleLaunchRetry(
    model: OwnerAppModel,
    store: PulseStore?,
    openStation: @escaping @MainActor () -> Void
  ) {
    launchRetryTask?.cancel()
    let monitor = NetworkMonitor()
    launchRetryTask = Task { [weak self] in
      monitor.start()
      let changes = monitor.changes
      var sawOffline = false
      for await online in changes {
        guard let self else {
          monitor.stop()
          return
        }
        if !online {
          sawOffline = true
          continue
        }
        monitor.stop()
        if sawOffline {
          // The network came back: retry the launch right away.
          await self.performLaunchRetry(
            model: model,
            store: store,
            openStation: openStation
          )
        } else {
          // The network was reachable when the launch failed, so the failure
          // is probably not connectivity related. Retry once after a short
          // delay in case the remote side was temporarily unavailable.
          try? await Task.sleep(for: Self.launchRetryDelay)
          guard !Task.isCancelled else {
            return
          }
          await self.performLaunchRetry(
            model: model,
            store: store,
            openStation: openStation
          )
        }
        return
      }
      monitor.stop()
    }
  }

  private func performLaunchRetry(
    model: OwnerAppModel,
    store: PulseStore?,
    openStation: @escaping @MainActor () -> Void
  ) async {
    guard launchRetryCount < Self.maxLaunchAutoRetries else {
      return
    }
    launchRetryCount += 1
    NSLog("Meeting Pulse automatic launch retry %d", launchRetryCount)
    await retryLaunch(model: model, store: store, openStation: openStation)
  }

  func retryLaunch(
    model: OwnerAppModel,
    store: PulseStore? = nil,
    openStation: @escaping @MainActor () -> Void = {}
  ) async {
    guard case .setupRequired = state else {
      return
    }
    await cleanupAfterFailedLaunch(model: model, store: store)
    store?.turnstileWebView = nil
    store?.turnstilePresentation = .hidden
    store?.setupFailureHeadline = MPString.error.genericSetup
    store?.setupFailure = nil
    state = .starting
    await start(model: model, store: store, openStation: openStation)
  }

  private func cleanupAfterFailedLaunch(
    model: OwnerAppModel,
    store: PulseStore?
  ) async {
    permissionTask?.cancel()
    permissionTask = nil
    await permissionCoordinator?.stop()
    permissionCoordinator = nil
    await runtime?.stop()
    runtime = nil
    model.runtime = nil
    model.runtimeStore = store
    store?.turnstileWebView = nil
    await turnstileGate?.shutdown()
    turnstileGate = nil
  }

  private static func launchFailureDetail(for error: Error) -> String {
    let detail = String(describing: error).trimmingCharacters(in: .whitespacesAndNewlines)
    return detail.isEmpty ? error.localizedDescription : detail
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

}

struct MenuBarView: View {
  @Bindable var model: OwnerAppModel
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    // Render the status line without `TimelineView`. A `TimelineView` in a
    // `MenuBarExtra` body is a known crash trigger on macOS: the periodic
    // schedule combined with `MenuBehavior.menuNeedsUpdate`'s re-entry
    // path produces a render loop that exhausts the main thread's stack
    // guard within ~85 frames
    // (`EXC_BAD_ACCESS / KERN_PROTECTION_FAILURE` inside
    // `ViewRendererHost.render`). The menu only stays open for a few
    // seconds, so a static snapshot of the status line is sufficient.
    Text(model.menuBarStatusLine(at: .now))
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
    Menu {
      ForEach(ManualOverride.Duration.allCases) { duration in
        Button {
          model.setBusy(duration: duration)
        } label: {
          Image(systemName: "moon.fill")
          Text(MPString.mast.durationLabel(duration))
        }
      }
    } label: {
      Image(systemName: "moon.fill")
      Text(MPString.menuBar.setBusy)
    }
    Menu {
      ForEach(ManualOverride.Duration.allCases) { duration in
        Button {
          model.setAvailable(duration: duration)
        } label: {
          Image(systemName: "checkmark.circle")
          Text(MPString.mast.durationLabel(duration))
        }
      }
    } label: {
      Image(systemName: "checkmark.circle")
      Text(MPString.menuBar.setAvailable)
    }
    Button {
      model.clearOverride()
    } label: {
      Image(systemName: "arrow.uturn.backward")
      Text(MPString.menuBar.backToAutomatic)
    }
    Toggle(isOn: Binding(
      get: { model.callOkay },
      set: { model.setCallOkay($0) }
    )) {
      Image(systemName: "phone.fill")
      Text(MPString.menuBar.callsAreOkay)
    }
    Button {
      model.refreshAndPublish()
    } label: {
      Image(systemName: "arrow.clockwise")
      Text(MPString.station.checkNow)
    }
    Divider()
    Button {
      openWindow(id: "settings")
    } label: {
      Image(systemName: "rectangle.grid.2x2")
      Text(MPString.thisMac.name)
    }
    Button {
      model.createPairingCode()
      openWindow(id: "pairing")
    } label: {
      Image(systemName: "link.badge.plus")
      Text(MPString.sharing.createLink)
    }
    Button {
      model.showingRotateConfirmation = true
    } label: {
      Image(systemName: "arrow.triangle.2.circlepath")
      Text(MPString.sharing.createNewLink)
    }
    .disabled(model.pairingCode == nil)
    Button {
      model.showingRevokeConfirmation = true
    } label: {
      Image(systemName: "link.slash")
      Text(MPString.sharing.stopSharing)
    }
    .disabled(model.pairingCode == nil)
    Button {
      openWindow(id: "recovery")
    } label: {
      Image(systemName: "key.fill")
      Text(MPString.thisMac.showRecoveryPhrase)
    }
    Button {
      openWindow(id: "diagnostics")
    } label: {
      Image(systemName: "stethoscope")
      Text(MPString.diagnostics.headline)
    }
    Button {
      model.showingDeleteConfirmation = true
    } label: {
      Image(systemName: "trash")
      Text(MPString.thisMac.deleteEverything)
    }
    Divider()
    Button {
      NSApplication.shared.terminate(nil)
    } label: {
      Image(systemName: "power")
      Text(MPString.menuBar.quit)
    }
  }
}

struct HeartThreadMenuIcon: View {
  let state: MeetingPulseState
  let callsOkay: Bool
  @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    Image(nsImage: cachedImage)
      .animation(
        accessibilityReduceMotion ? nil : .easeInOut(duration: 0.18),
        value: state
      )
      .animation(
        accessibilityReduceMotion ? nil : .easeInOut(duration: 0.18),
        value: callsOkay
      )
      .frame(width: 22, height: 22)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(statusAccessibilityLabel)
      .accessibilityIdentifier("meetingpulse.menu-bar-status")
  }

  /// Cached rasterization of the menu-bar icon. The original implementation
  /// re-rasterized an NSImage with NSBezierPath on every SwiftUI render and
  /// on every state change, allocating a 22x22 bitmap each time. The menu
  /// bar re-evaluates the label frequently (every store mutation), so the
  /// cache lookup now happens on a hot path. The cache is keyed on the
  /// three render inputs that affect appearance: state, callsOkay,
  /// colorScheme. NSCache evicts under memory pressure automatically.
  private var cachedImage: NSImage {
    let key = ImageCacheKey(state: state, callsOkay: callsOkay, colorScheme: colorScheme)
    if let cached = ImageCache.shared.image(forKey: key) {
      return cached
    }
    let image = renderMenuBarImage()
    ImageCache.shared.setImage(image, forKey: key)
    return image
  }

  private func renderMenuBarImage() -> NSImage {
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
      if callsOkay {
        return NSColor(calibratedRed: 0.42, green: 0.70, blue: 1, alpha: 1)
      }
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

private struct ImageCacheKey: Hashable {
  let state: MeetingPulseState
  let callsOkay: Bool
  let colorScheme: ColorScheme
}

private final class ImageCache: @unchecked Sendable {
  static let shared = ImageCache()

  private let cache = NSCache<NSString, NSImage>()

  private init() {
    cache.countLimit = 6
  }

  func image(forKey key: ImageCacheKey) -> NSImage? {
    cache.object(forKey: Self.cacheKey(key))
  }

  func setImage(_ image: NSImage, forKey key: ImageCacheKey) {
    cache.setObject(image, forKey: Self.cacheKey(key))
  }

  private static func cacheKey(_ key: ImageCacheKey) -> NSString {
    "\(key.state.rawValue)-\(key.callsOkay ? 1 : 0)-\(key.colorScheme == .dark ? 1 : 0)" as NSString
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

/// Mirrors the station-window visibility to the Dock icon.
///
/// The Dock icon is shown only while the station window is on screen. When the
/// user closes the station, the activation policy flips back to `.accessory`
/// so the Dock icon disappears. The menu-bar `MenuBarExtra` is unaffected by
/// activation policy, so the menu-bar item stays available in either mode.
@MainActor
final class DockVisibilityCoordinator {
  static let shared = DockVisibilityCoordinator()

  private var observationTask: Task<Void, Never>?
  private var lastPolicy: NSApplication.ActivationPolicy?

  private init() {}

  func start(store: PulseStore) {
    observationTask?.cancel()
    // Apply the initial policy immediately so the Dock icon is correct on
    // launch. The station is not visible at this point, so start in .accessory.
    applyPolicy(for: store.stationVisible)
    observationTask = Task { @MainActor [weak store] in
      while !Task.isCancelled {
        guard let store else { return }
        let visible = store.stationVisible
        applyPolicy(for: visible)
        await Self.waitForStationChange(store: store)
      }
    }
  }

  func stop() {
    observationTask?.cancel()
    observationTask = nil
  }

  private func applyPolicy(for stationVisible: Bool) {
    let policy: NSApplication.ActivationPolicy = stationVisible ? .regular : .accessory
    guard policy != lastPolicy else { return }
    if !NSApplication.shared.setActivationPolicy(policy) {
      NSLog("Meeting Pulse: failed to update activation policy to \(policy.rawValue).")
      return
    }
    lastPolicy = policy
  }

  private static func waitForStationChange(store: PulseStore) async {
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      withObservationTracking {
        _ = store.stationVisible
      } onChange: {
        continuation.resume()
      }
    }
  }
}
