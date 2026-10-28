import Foundation
import Testing

@testable import MPCore

@Suite("SourceAttention")
struct SourceAttentionTests {
  @Test
  func quietSourcesNeedNoAttention() {
    let attention = SourceAttention(
      meet: .inactive,
      slack: .sourceAbsent,
      meetHealth: .ok,
      slackHealth: .absent
    )
    #expect(attention == .none)
  }

  @Test
  func anUnknownMeetObservationNamesMeet() {
    let attention = SourceAttention(
      meet: .unknown,
      slack: .inactive,
      meetHealth: .ok,
      slackHealth: .ok
    )
    #expect(attention == .googleMeet)
  }

  @Test
  func anUnknownSlackObservationNamesSlack() {
    let attention = SourceAttention(
      meet: .inactive,
      slack: .unknown,
      meetHealth: .ok,
      slackHealth: .ok
    )
    #expect(attention == .slackHuddle)
  }

  @Test
  func aDegradedDetectorNamesItsSource() {
    let degraded = DetectorHealth.degraded(DiagnosticCode(rawValue: "MEET_AX_DEGENERATE"))
    let attention = SourceAttention(
      meet: .inactive,
      slack: .inactive,
      meetHealth: degraded,
      slackHealth: .ok
    )
    #expect(attention == .googleMeet)
  }

  @Test
  func healthCodesAreStable() {
    #expect(DetectorHealth.ok.diagnosticCode == "OK")
    #expect(DetectorHealth.absent.diagnosticCode == "ABSENT")
    #expect(DetectorHealth.permissionDenied.diagnosticCode == "PERMISSION_DENIED")
    #expect(
      DetectorHealth.degraded(DiagnosticCode(rawValue: "SLACK_AX_TIMEOUT")).diagnosticCode
        == "SLACK_AX_TIMEOUT"
    )
  }
}
