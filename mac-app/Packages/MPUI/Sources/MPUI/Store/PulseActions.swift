import Foundation
import MPCore

@MainActor
public protocol PulseActions: AnyObject {
  func setBusy(for duration: ManualOverride.Duration) async
  func setAvailable(for duration: ManualOverride.Duration) async
  func clearOverride() async
  func setCallsOkay(_ on: Bool) async
  func setDisplayName(_ name: String) async
  func checkAndPublishNow() async

  func createViewerLink() async
  func rotateViewerLink() async
  func revokeViewerAccess() async
  func loadViewers() async
  func removeViewer(id: UUID) async
  func deleteViewer(id: UUID) async

  func setLaunchAtLogin(_ on: Bool) throws
  func setOpenWindowAtLogin(_ on: Bool)
  func revealRecoveryPhrase() async
  func deleteEverything() async
  func completeOnboarding()
  func retryLaunch() async

  func openAccessibilitySettings() -> Bool
  func openLoginItemsSettings()
  func revealInFinder()
  func openStation()
  func openStation(section: StationSection)
  func showOnboarding()
  func openPairing()
  func openRecovery()
  func openDiagnostics()
  func openSettings()
  func quit()
}

public extension PulseActions {
  func setBusy(for duration: ManualOverride.Duration = .m30) async {
    await setBusy(for: duration)
  }

  func setAvailable() async {
    await setAvailable(for: .m30)
  }

  func retryLaunch() async {}
}
