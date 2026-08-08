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
  let now = Date(timeIntervalSince1970: 1_720_000_000)
  let expiry = Date(timeIntervalSince1970: 1_720_000_600)
  let result = ReasonLineBuilder.build(
    deleteCompleted: false,
    accessibilityGranted: true,
    syncState: .idle,
    hasViewerLink: true,
    mode: .busy,
    overrideExpiry: expiry,
    stateReason: .manualOverride,
    callsOkay: false,
    face: .meeting,
    now: now
  )
  let endTime = expiry.formatted(date: .omitted, time: .shortened)
  #expect(result.0 == "Busy until \(endTime) - 10 minutes remaining")
}

@Test
func reasonLineUsesCompactMenuBarCountdown() {
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
    presentation: .menuBar,
    now: Date(timeIntervalSince1970: 1_720_000_000)
  )
  #expect(result.0 == "Busy - 10m")
}

@Test
func reasonLineFormatsTimedAvailableHours() {
  let now = Date(timeIntervalSince1970: 1_720_000_000)
  let expiry = now.addingTimeInterval(5_400)
  let result = ReasonLineBuilder.overrideLine(
    mode: .available,
    overrideExpiry: expiry,
    presentation: .station,
    now: now
  )
  let endTime = expiry.formatted(date: .omitted, time: .shortened)
  #expect(result == "Available until \(endTime) - 1 hour 30 minutes remaining")
}

@Test
func reasonLineClampsSubMinuteCountdown() {
  let now = Date(timeIntervalSince1970: 1_720_000_000)
  let expiry = now.addingTimeInterval(30)
  #expect(
    ReasonLineBuilder.overrideLine(
      mode: .busy,
      overrideExpiry: expiry,
      presentation: .station,
      now: now
    ).contains("less than a minute remaining")
  )
  #expect(
    ReasonLineBuilder.overrideLine(
      mode: .busy,
      overrideExpiry: expiry,
      presentation: .menuBar,
      now: now
    ) == "Busy - <1m"
  )
}

@Test
func reasonLineKeepsIndefiniteOverrideCopy() {
  #expect(
    ReasonLineBuilder.overrideLine(
      mode: .busy,
      overrideExpiry: nil,
      presentation: .menuBar
    ) == "Busy until you clear it"
  )
}
