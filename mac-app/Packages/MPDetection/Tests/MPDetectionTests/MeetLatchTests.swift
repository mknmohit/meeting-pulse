import CoreGraphics
import Testing

@testable import MPDetection

struct MeetLatchTests {
  @Test
  func idleWithoutChromeIsSourceAbsent() {
    var latch = MeetLatch()
    let result = latch.apply(
      .init(
        chromeRunning: false,
        scanCompleted: false,
        confirmedSessions: [],
        liveAnchors: []
      ),
      now: now,
      maxLatchDuration: .seconds(14_400)
    )
    #expect(result == .sourceAbsent)
  }

  @Test
  func incompleteIdleScanIsUnknown() {
    var latch = MeetLatch()
    let result = latch.apply(
      .init(
        chromeRunning: true,
        scanCompleted: false,
        confirmedSessions: [],
        liveAnchors: []
      ),
      now: now,
      maxLatchDuration: .seconds(14_400)
    )
    #expect(result == .unknown)
  }

  @Test
  func confirmedSessionCreatesAnActiveLatch() {
    var latch = MeetLatch()
    let anchor = anchor(at: now)
    let result = latch.apply(
      .init(
        chromeRunning: true,
        scanCompleted: true,
        confirmedSessions: [anchor],
        liveAnchors: []
      ),
      now: now,
      maxLatchDuration: .seconds(14_400)
    )
    #expect(result == .active)
    #expect(latch.activeAnchors == [anchor])
  }

  @Test
  func liveAnchorMaintainsAnIncompleteScan() {
    var latch = MeetLatch()
    let anchor = anchor(at: now)
    _ = latch.apply(
      .init(
        chromeRunning: true,
        scanCompleted: true,
        confirmedSessions: [anchor],
        liveAnchors: []
      ),
      now: now,
      maxLatchDuration: .seconds(14_400)
    )

    let result = latch.apply(
      .init(
        chromeRunning: true,
        scanCompleted: false,
        confirmedSessions: [],
        liveAnchors: [anchor]
      ),
      now: now.advanced(by: .seconds(10)),
      maxLatchDuration: .seconds(14_400)
    )
    #expect(result == .active)
  }

  @Test
  func transitionGraceMaintainsActiveWhenAnchorIsOffSpace() {
    var latch = MeetLatch()
    let anchor = anchor(at: now)
    _ = latch.apply(
      .init(
        chromeRunning: true,
        scanCompleted: true,
        confirmedSessions: [anchor],
        liveAnchors: []
      ),
      now: now,
      maxLatchDuration: .seconds(14_400)
    )

    let result = latch.apply(
      .init(
        chromeRunning: true,
        scanCompleted: true,
        confirmedSessions: [],
        liveAnchors: [],
        visibility: .transitionGrace
      ),
      now: now.advanced(by: .seconds(5)),
      maxLatchDuration: .seconds(14_400)
    )

    #expect(result == .active)
    #expect(latch.activeAnchors == [anchor])
  }

  @Test
  func expiredSpaceVisibilityBecomesUnknownInsteadOfInactive() {
    var latch = MeetLatch()
    let anchor = anchor(at: now)
    _ = latch.apply(
      .init(
        chromeRunning: true,
        scanCompleted: true,
        confirmedSessions: [anchor],
        liveAnchors: []
      ),
      now: now,
      maxLatchDuration: .seconds(14_400)
    )

    let result = latch.apply(
      .init(
        chromeRunning: true,
        scanCompleted: true,
        confirmedSessions: [],
        liveAnchors: [],
        visibility: .unavailable
      ),
      now: now.advanced(by: .seconds(30)),
      maxLatchDuration: .seconds(14_400)
    )

    #expect(result == .unknown)
    #expect(latch.activeAnchors == [anchor])
  }

  @Test
  func incompleteScanWithoutLiveAnchorIsUnknown() {
    var latch = MeetLatch()
    let anchor = anchor(at: now)
    _ = latch.apply(
      .init(
        chromeRunning: true,
        scanCompleted: true,
        confirmedSessions: [anchor],
        liveAnchors: []
      ),
      now: now,
      maxLatchDuration: .seconds(14_400)
    )

    let result = latch.apply(
      .init(
        chromeRunning: true,
        scanCompleted: false,
        confirmedSessions: [],
        liveAnchors: []
      ),
      now: now.advanced(by: .seconds(10)),
      maxLatchDuration: .seconds(14_400)
    )
    #expect(result == .unknown)
    #expect(latch.activeAnchors == [anchor])
  }

  @Test
  func completeScanWithoutLiveAnchorReleasesToInactive() {
    var latch = MeetLatch()
    let anchor = anchor(at: now)
    _ = latch.apply(
      .init(
        chromeRunning: true,
        scanCompleted: true,
        confirmedSessions: [anchor],
        liveAnchors: []
      ),
      now: now,
      maxLatchDuration: .seconds(14_400)
    )

    let result = latch.apply(
      .init(
        chromeRunning: true,
        scanCompleted: true,
        confirmedSessions: [],
        liveAnchors: []
      ),
      now: now.advanced(by: .seconds(10)),
      maxLatchDuration: .seconds(14_400)
    )
    #expect(result == .inactive)
    #expect(latch.activeAnchors.isEmpty)
  }

  @Test
  func closingOneOfTwoCallsKeepsTheOtherActive() {
    var latch = MeetLatch()
    let first = anchor(at: now)
    let second = anchor(at: now)
    _ = latch.apply(
      .init(
        chromeRunning: true,
        scanCompleted: true,
        confirmedSessions: [first, second],
        liveAnchors: []
      ),
      now: now,
      maxLatchDuration: .seconds(14_400)
    )

    let result = latch.apply(
      .init(
        chromeRunning: true,
        scanCompleted: true,
        confirmedSessions: [],
        liveAnchors: [second]
      ),
      now: now.advanced(by: .seconds(10)),
      maxLatchDuration: .seconds(14_400)
    )
    #expect(result == .active)
    #expect(latch.activeAnchors == [second])
  }

  @Test
  func explicitlyExpiredLatchBecomesUnknown() {
    var latch = MeetLatch()
    let anchor = anchor(at: now)
    _ = latch.apply(
      .init(
        chromeRunning: true,
        scanCompleted: true,
        confirmedSessions: [anchor],
        liveAnchors: []
      ),
      now: now,
      maxLatchDuration: .seconds(30)
    )

    let result = latch.apply(
      .init(
        chromeRunning: true,
        scanCompleted: true,
        confirmedSessions: [],
        liveAnchors: [anchor]
      ),
      now: now.advanced(by: .seconds(30)),
      maxLatchDuration: .seconds(30)
    )
    #expect(result == .unknown)
    #expect(latch.activeAnchors.isEmpty)
  }

  @Test
  func activeLatchDoesNotExpireWithoutConfiguredDuration() {
    var latch = MeetLatch()
    let anchor = anchor(at: now)
    _ = latch.apply(
      .init(
        chromeRunning: true,
        scanCompleted: true,
        confirmedSessions: [anchor],
        liveAnchors: []
      ),
      now: now,
      maxLatchDuration: nil
    )

    let result = latch.apply(
      .init(
        chromeRunning: true,
        scanCompleted: true,
        confirmedSessions: [],
        liveAnchors: [anchor]
      ),
      now: now.advanced(by: .seconds(14_401)),
      maxLatchDuration: nil
    )

    #expect(result == .active)
    #expect(latch.activeAnchors == [anchor])
  }

  @Test
  func chromeTerminationReleasesToInactive() {
    var latch = MeetLatch()
    let anchor = anchor(at: now)
    _ = latch.apply(
      .init(
        chromeRunning: true,
        scanCompleted: true,
        confirmedSessions: [anchor],
        liveAnchors: []
      ),
      now: now,
      maxLatchDuration: .seconds(14_400)
    )
    let result = latch.apply(
      .init(
        chromeRunning: false,
        scanCompleted: false,
        confirmedSessions: [],
        liveAnchors: []
      ),
      now: now.advanced(by: .seconds(10)),
      maxLatchDuration: .seconds(14_400)
    )
    #expect(result == .inactive)
  }
}

private let now = ContinuousClock().now

private func anchor(at instant: ContinuousClock.Instant) -> MeetLatch.Anchor {
  MeetLatch.Anchor(windowID: CGWindowID(42), tabIdentity: "tab", confirmedAt: instant)
}
