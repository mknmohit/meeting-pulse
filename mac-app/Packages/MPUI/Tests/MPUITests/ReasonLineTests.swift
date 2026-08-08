import Foundation
import MPCore
import Testing
@testable import MPUI

@Test
func reasonLineKeepsPermissionFirst() {
  let result = ReasonLineBuilder.build(
    deleteCompleted: false,
    accessibilityGranted: false,
    syncState: .retrying,
    hasViewerLink: false,
    mode: .automatic,
    overrideExpiry: nil,
    stateReason: .permissionDenied,
    callsOkay: false,
    face: .generic
  )
  #expect(result.0 == "Waiting for Accessibility permission")
  #expect(result.1 == .caution)
}

@Test
func reasonLineNamesMissingViewerLink() {
  let result = ReasonLineBuilder.build(
    deleteCompleted: false,
    accessibilityGranted: true,
    syncState: .idle,
    hasViewerLink: false,
    mode: .automatic,
    overrideExpiry: nil,
    stateReason: .allSourcesInactive,
    callsOkay: false,
    face: .generic
  )
  #expect(result.0 == "No one is watching yet. Create a link.")
}

@Test
func reasonLineReportsTimedBusyOverride() {
  let result = ReasonLineBuilder.build(
    deleteCompleted: false,
    accessibilityGranted: true,
    syncState: .idle,
    hasViewerLink: true,
    mode: .busy,
    overrideExpiry: Date(timeIntervalSince1970: 1_720_000_600),
    stateReason: .manualOverride,
    callsOkay: false,
    face: .meeting,
    now: Date(timeIntervalSince1970: 1_720_000_000)
  )
  #expect(result.0 == "Busy for another 10 minutes")
}
