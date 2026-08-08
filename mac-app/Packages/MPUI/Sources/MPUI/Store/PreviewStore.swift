import Foundation
import MPCore

@MainActor
public extension PulseStore {
  static func preview() -> PulseStore {
    makePreview(state: .available, callsOkay: false, accessibilityGranted: true)
  }

  static func previewBusy() -> PulseStore {
    makePreview(state: .busy, callsOkay: false, accessibilityGranted: true)
  }

  static func previewCallOkay() -> PulseStore {
    makePreview(state: .busy, callsOkay: true, accessibilityGranted: true)
  }

  static func previewGeneric() -> PulseStore {
    makePreview(state: .unavailable, callsOkay: false, accessibilityGranted: false)
  }

  static func previewNoPermission() -> PulseStore {
    makePreview(state: .unavailable, callsOkay: false, accessibilityGranted: false)
  }

  private static func makePreview(
    state: State,
    callsOkay: Bool,
    accessibilityGranted: Bool
  ) -> PulseStore {
    let store = PulseStore()
    store.effectiveState = state
    store.callsOkay = callsOkay
    store.accessibilityGranted = accessibilityGranted
    store.statusReason = accessibilityGranted ? .allSourcesInactive : .permissionDenied
    store.lastPublished = .now
    store.publishState = .published(at: .now)
    store.viewerLinks = [URL(string: "https://example.invalid/#code=ABCD1234")!]
    store.pairingCode = "ABCD1234"
    store.meet = state == .busy ? .active : .inactive
    store.slack = .inactive
    return store
  }
}
