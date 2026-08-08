import AppKit
import Foundation
import MPUI
import MPCore
import MPSupport
import MPSync
import SwiftUI

@MainActor
final class AppPulseActions: PulseActions {
  private let store: PulseStore
  private weak var model: OwnerAppModel?
  private var windowOpener: (@MainActor (String) -> Void)?
  private var launchRetrier: (@MainActor () async -> Void)?

  /// Set by `quit()` so the app delegate can distinguish an explicit menu Quit
  /// from a Cmd+Q keypress. Cmd+Q should only close the station; the menu
  /// Quit always terminates the app.
  private(set) var requestedQuitFromMenu = false

  init(store: PulseStore, model: OwnerAppModel? = nil) {
    self.store = store
    self.model = model
  }

  /// True while the station NSWindow is on screen. Mirrors
  /// `PulseStore.stationVisible`, which `StationWindow.onAppear` /
  /// `.onDisappear` maintain.
  var isStationVisible: Bool { store.stationVisible }

  func attach(model: OwnerAppModel) {
    model.runtimeStore = store
    self.model = model
  }

  func configure(
    openWindow: @escaping @MainActor (String) -> Void,
    retryLaunch: @escaping @MainActor () async -> Void
  ) {
    windowOpener = openWindow
    launchRetrier = retryLaunch
  }

  func setBusy(for duration: ManualOverride.Duration) async {
    await setOverride(state: .busy, duration: duration)
  }

  func setAvailable(for duration: ManualOverride.Duration) async {
    await setOverride(state: .available, duration: duration)
  }

  func clearOverride() async {
    guard let runtime = model?.runtime else {
      store.lastError = .network
      return
    }
    let previousState = store.effectiveState
    do {
      try await runtime.clearOverride()
      store.mode = .automatic
      store.overrideExpiry = nil
      await runtime.refreshAndPublish()
    } catch {
      store.effectiveState = previousState
      store.lastError = .network
    }
  }

  func setCallsOkay(_ on: Bool) async {
    guard let runtime = model?.runtime else {
      store.lastError = .network
      return
    }
    store.callsOkay = on
    model?.callOkay = on
    await runtime.refreshAndPublish()
  }

  func setDisplayName(_ name: String) async {
    guard let runtime = model?.runtime else {
      store.lastError = .network
      return
    }
    store.displayName = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
    do {
      try await runtime.updateDisplayName(store.displayName.isEmpty ? nil : store.displayName)
    } catch {
      store.lastError = .network
    }
  }

  func checkAndPublishNow() async {
    guard let runtime = model?.runtime else {
      store.lastError = .network
      return
    }
    store.isPublishing = true
    store.publishState = .publishing
    await runtime.refreshAndPublish()
    store.isPublishing = false
  }

  func createViewerLink() async {
    guard let runtime = model?.runtime else {
      store.lastError = .createLink
      return
    }
    guard !store.isCreatingViewerLink else {
      return
    }
    store.isCreatingViewerLink = true
    store.lastError = nil
    defer {
      store.isCreatingViewerLink = false
    }
    do {
      let result = try await runtime.createPairingCode()
      store.pairingCode = result.rawCode
      store.viewerLinks = try runtime.pairingLinks(for: result)
      store.viewers = .idle
      completeOnboarding()
    } catch {
      store.lastError = .createLink
    }
  }

  func rotateViewerLink() async {
    guard let runtime = model?.runtime else {
      store.lastError = .createLink
      return
    }
    do {
      let result = try await runtime.rotatePairingCode()
      store.pairingCode = result.rawCode
      store.viewerLinks = try runtime.pairingLinks(for: result)
      store.viewers = .idle
    } catch {
      store.lastError = .createLink
    }
  }

  func revokeViewerAccess() async {
    guard let runtime = model?.runtime else {
      store.lastError = .network
      return
    }
    do {
      try await runtime.revokePairingCode()
      store.pairingCode = nil
      store.viewerLinks = []
      store.viewers = .idle
    } catch {
      store.lastError = .network
    }
  }

  func loadViewers() async {
    guard let runtime = model?.runtime else {
      store.viewers = .failed(MPString.sharing.viewersLoadFailed)
      return
    }
    guard let viewers = try? await runtime.listViewers() else {
      store.viewers = .failed(MPString.sharing.viewersLoadFailed)
      return
    }
    store.viewers = .loaded(
      viewers
        .filter { $0.revokedAt == nil }
        .map { ViewerSummary(id: $0.viewerUserID, pairedAt: $0.createdAt) }
    )
  }

  func removeViewer(id: UUID) async {
    guard let runtime = model?.runtime else {
      store.lastError = .viewers
      return
    }
    do {
      try await runtime.revokeViewer(id)
      await loadViewers()
    } catch {
      store.lastError = .viewers
    }
  }

  func setLaunchAtLogin(_ on: Bool) throws {
    guard let runtime = model?.runtime else {
      throw AppPulseActionError.runtimeUnavailable
    }
    try runtime.updateLoginItem(on)
  }

  func setOpenWindowAtLogin(_ on: Bool) {
    UserDefaults.standard.set(on, forKey: "com.meetingpulse.openWindowAtLogin")
  }

  func revealRecoveryPhrase() async {
    guard let runtime = model?.runtime else {
      store.lastError = .localStorage
      return
    }
    do {
      store.recoveryPhrase = try runtime.recoveryPhrase() ?? nil
    } catch {
      store.lastError = .localStorage
    }
  }

  func deleteEverything() async {
    guard store.deleteCompleted == false else {
      return
    }

    guard let runtime = model?.runtime else {
      store.lastError = .network
      return
    }
    do {
      try await runtime.deleteEverything()
      store.deleteCompleted = true
      store.effectiveState = .unavailable
      store.pairingCode = nil
      store.viewerLinks = []
      store.recoveryPhrase = nil
      store.displayName = ""
      store.mode = .automatic
      store.overrideExpiry = nil
      store.viewers = .idle
      store.hasCompletedOnboarding = false
      UserDefaults.standard.removeObject(forKey: "setup.completed")
    } catch {
      store.lastError = .network
    }
  }

  func completeOnboarding() {
    UserDefaults.standard.set(true, forKey: "setup.completed")
    store.hasCompletedOnboarding = true
  }

  func retryLaunch() async {
    guard let launchRetrier else {
      NSLog("Meeting Pulse: launch retry is unavailable")
      return
    }
    await launchRetrier()
  }

  func openAccessibilitySettings() -> Bool {
    guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    else {
      return false
    }
    return NSWorkspace.shared.open(url)
  }

  func openLoginItemsSettings() {
    guard let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")
    else {
      return
    }
    _ = NSWorkspace.shared.open(url)
  }

  func revealInFinder() {
    NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
  }

  func openStation() {
    openStation(section: .watch)
  }

  func openStation(section: StationSection) {
    store.section = section
    // Flip the activation policy synchronously before opening the window.
    // Without this, the window opens in `.accessory` mode and is ordered
    // beneath whatever app the user launched us from (Launchpad / Dock /
    // menu bar). Setting `.regular` first lets the window take focus and
    // appear on top the moment SwiftUI presents it. The Dock icon is
    // acceptable here: it disappears again as soon as the station closes,
    // because `StationWindow.onDisappear` clears `stationVisible` and the
    // `DockVisibilityCoordinator` observer flips the policy back.
    if !store.stationVisible {
      store.stationVisible = true
      NSApplication.shared.setActivationPolicy(.regular)
    }
    windowOpener?("station")
  }

  /// Close the station NSWindow if it is currently on screen. The menu-bar
  /// process stays alive so the user can reopen the station later. No-op when
  /// the station is already hidden.
  func closeStation() {
    guard store.stationVisible else { return }
    let stationTitle = MPString.station.windowTitle
    for window in NSApp.windows where window.title == stationTitle {
      window.performClose(nil)
    }
    // `performClose` is asynchronous: the window's `.onDisappear` callback
    // does not fire until the next runloop tick, and the `DockVisibilityCoordinator`
    // observer would not see the policy change until that loop runs. Flip the
    // activation policy synchronously so the Dock icon disappears at the same
    // time the station window does, instead of staying visible for a frame or
    // two after Cmd+Q.
    store.stationVisible = false
    NSApplication.shared.setActivationPolicy(.accessory)
  }

  func showOnboarding() {
    openStation()
  }

  func openPairing() {
    windowOpener?("pairing")
  }

  func openRecovery() {
    windowOpener?("recovery")
  }

  func openDiagnostics() {
    windowOpener?("diagnostics")
  }

  func openSettings() {
    windowOpener?("settings")
  }

  func quit() {
    requestedQuitFromMenu = true
    NSApp.terminate(nil)
  }

  private func setOverride(state: MPCore.State, duration: ManualOverride.Duration) async {
    guard let runtime = model?.runtime else {
      store.lastError = .network
      return
    }
    let previousMode = store.mode
    let previousExpiry = store.overrideExpiry
    let previousState = store.effectiveState
    store.mode = state == .busy ? .busy : .available
    store.preferredDuration = duration
    do {
      try await runtime.setOverride(state: state, duration: duration)
    } catch {
      store.mode = previousMode
      store.overrideExpiry = previousExpiry
      store.effectiveState = previousState
      store.lastError = .network
    }
  }

  private enum AppPulseActionError: Error {
    case runtimeUnavailable
  }
}
