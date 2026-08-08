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

  init(store: PulseStore, model: OwnerAppModel? = nil) {
    self.store = store
    self.model = model
  }

  func attach(model: OwnerAppModel) {
    model.runtimeStore = store
    self.model = model
  }

  func configure(openWindow: @escaping @MainActor (String) -> Void) {
    windowOpener = openWindow
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
    windowOpener?("station")
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
