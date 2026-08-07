import Foundation
import Testing

@testable import MPCore

struct ReducerTests {
  @Test
  func decisionTableCoversEveryObservationPair() {
    let expected: [[State]] = [
      [.busy, .busy, .busy, .busy],
      [.busy, .available, .unavailable, .available],
      [.busy, .unavailable, .unavailable, .unavailable],
      [.busy, .available, .unavailable, .available],
    ]
    let observations = SourceObservation.allCases
    let now = ContinuousClock().now

    for (meetIndex, meet) in observations.enumerated() {
      for (slackIndex, slack) in observations.enumerated() {
        let result = StatusReducer.reduce(
          ReducerInput(
            meet: meet,
            slack: slack,
            accessibilityGranted: true,
            override: nil,
            callOkay: false,
            monotonicNow: now
          )
        )
        #expect(result.state == expected[meetIndex][slackIndex])
      }
    }
  }

  @Test
  func permissionDenialCollapsesEverythingExceptConfirmedBusy() {
    let now = ContinuousClock().now
    for meet in SourceObservation.allCases {
      for slack in SourceObservation.allCases {
        let result = StatusReducer.reduce(
          ReducerInput(
            meet: meet,
            slack: slack,
            accessibilityGranted: false,
            override: nil,
            callOkay: false,
            monotonicNow: now
          )
        )
        let expected: State = meet == .active || slack == .active ? .busy : .unavailable
        #expect(result.state == expected)
      }
    }
  }

  @Test
  func overrideBeatsActiveMeetingUnknownAndPermissionFailure() throws {
    let now = ContinuousClock().now
    let override = try ManualOverride(
      state: .available,
      createdAtWall: Date(),
      expiresAtWall: Date().addingTimeInterval(900),
      deadline: now.advanced(by: .seconds(900))
    )
    let result = StatusReducer.reduce(
      ReducerInput(
        meet: .active,
        slack: .unknown,
        accessibilityGranted: false,
        override: override,
        callOkay: true,
        monotonicNow: now
      )
    )
    #expect(result.state == .available)
    #expect(result.isOverridden)
    #expect(result.callOkay)
  }

  @Test
  func expiredOverrideIsInactiveAtTheBoundary() throws {
    let now = ContinuousClock().now
    let override = try ManualOverride(
      state: .busy,
      createdAtWall: Date(),
      expiresAtWall: Date().addingTimeInterval(30),
      deadline: now.advanced(by: .seconds(30))
    )
    #expect(!override.isActive(at: now.advanced(by: .seconds(30))))
    #expect(
      StatusReducer.reduce(
        ReducerInput(
          meet: .inactive,
          slack: .inactive,
          accessibilityGranted: true,
          override: override,
          callOkay: false,
          monotonicNow: now.advanced(by: .seconds(30))
        )
      ).state == .available
    )
  }

  @Test
  func unknownNeverReportsAllSourcesInactive() {
    let result = StatusReducer.reduce(
      ReducerInput(
        meet: .unknown,
        slack: .inactive,
        accessibilityGranted: true,
        override: nil,
        callOkay: false,
        monotonicNow: ContinuousClock().now
      )
    )
    #expect(result.reason != .allSourcesInactive)
    #expect(result.state == .unavailable)
  }

  @Test
  func callOkayPassesThroughWithoutChangingState() {
    let now = ContinuousClock().now
    for callOkay in [false, true] {
      let result = StatusReducer.reduce(
        ReducerInput(
          meet: .inactive,
          slack: .sourceAbsent,
          accessibilityGranted: true,
          override: nil,
          callOkay: callOkay,
          monotonicNow: now
        )
      )
      #expect(result.state == .available)
      #expect(result.callOkay == callOkay)
    }
  }

  @Test
  func manualOverrideRejectsUnavailableState() {
    #expect(throws: ManualOverride.ValidationError.unavailableState) {
      try ManualOverride(
        state: .unavailable,
        createdAtWall: Date(),
        expiresAtWall: nil,
        deadline: nil
      )
    }
  }
}
