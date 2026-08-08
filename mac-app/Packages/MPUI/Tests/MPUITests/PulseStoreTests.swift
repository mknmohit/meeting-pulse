import Foundation
import MPCore
import MPSupport
import Testing
@testable import MPUI

@Test
@MainActor
func previewFixturesExposeExpectedFaces() {
  #expect(PulseStore.previewBusy().plateFace == .meeting)
  #expect(PulseStore.previewCallOkay().plateFace == .callOkay)
  #expect(PulseStore.preview().plateFace == .generic)
  #expect(PulseStore.previewNoPermission().plateFace == .generic)
}

@Test
@MainActor
func faceMatrixMatchesViewerContract() {
  let store = PulseStore.preview()
  let cases: [(State, Bool, PlateFace)] = [
    (.busy, false, .meeting),
    (.busy, true, .callOkay),
    (.available, false, .generic),
    (.unavailable, false, .generic)
  ]

  for (state, callsOkay, expected) in cases {
    store.effectiveState = state
    store.callsOkay = callsOkay
    store.lastPublished = .now
    #expect(store.plateFace == expected)
  }
}

@Test
@MainActor
func stalePublishedStateFallsBackToGenericFace() {
  let store = PulseStore.previewBusy()
  store.lastPublished = .now.addingTimeInterval(-181)
  #expect(store.plateFace == .generic)
}

@Test
func durationValuesAreIdentifiableAndHashable() {
  let durations = Set(ManualOverride.Duration.allCases)
  #expect(durations.count == 7)
  #expect(ManualOverride.Duration.m30.id == .m30)
}

@Test
func customDurationLabelsDescribeHoursAndMinutes() {
  #expect(
    MPString.mast.durationLabel(.custom(minutes: 90))
      == "Custom (1 hour 30 minutes)"
  )
  #expect(MPString.mast.durationLabel(.custom(minutes: 0)) == "Custom...")
}
