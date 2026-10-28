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
  func unavailableVisibilityWithAReadableMeetSurfaceEndsTheCall() {
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

    // The Meet page is still readable and shows no call controls, so the call
    // is provably over even though the visibility is degraded.
    let result = latch.apply(
      .init(
        chromeRunning: true,
        scanCompleted: true,
        confirmedSessions: [],
        liveAnchors: [],
        visibility: .unavailable,
        meetSurfaceReadable: true
      ),
      now: now.advanced(by: .seconds(30)),
      maxLatchDuration: .seconds(14_400)
    )

    #expect(result == .inactive)
    #expect(latch.activeAnchors.isEmpty)
  }

  @Test
  func unavailableVisibilityWithAnAbsentMeetSurfaceEndsTheCall() {
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

    // A complete scan that found no Meet page and no Meet tab means the tab
    // was closed, so the call is over.
    let result = latch.apply(
      .init(
        chromeRunning: true,
        scanCompleted: true,
        confirmedSessions: [],
        liveAnchors: [],
        visibility: .unavailable,
        meetSurfaceAbsent: true
      ),
      now: now.advanced(by: .seconds(30)),
      maxLatchDuration: .seconds(14_400)
    )

    #expect(result == .inactive)
    #expect(latch.activeAnchors.isEmpty)
  }

  @Test
  func authoritativeScanWithAReadableMeetSurfaceEndsTheCall() {
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

    // Leaving a call from the picture-in-picture popover keeps the Meet tab
    // open. The page is readable and the call controls are gone, which is
    // positive evidence that the call ended.
    let result = latch.apply(
      .init(
        chromeRunning: true,
        scanCompleted: true,
        confirmedSessions: [],
        liveAnchors: [],
        meetSurfaceReadable: true
      ),
      now: now.advanced(by: .seconds(10)),
      maxLatchDuration: .seconds(14_400)
    )

    #expect(result == .inactive)
    #expect(latch.activeAnchors.isEmpty)
  }

  @Test
  func incompleteScanWithoutLiveAnchorKeepsTheLatchActive() {
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

    // A truncated scan cannot prove the call ended, so the confirmed session
    // stays active. This is the long running meeting case: the accessibility
    // tree outgrows the element budget and the scan no longer completes.
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
    #expect(result == .active)
    #expect(latch.activeAnchors == [anchor])
  }

  @Test
  func incompleteScanWithoutAnyAnchorIsUnknown() {
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
    #expect(latch.activeAnchors.isEmpty)
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

  @Test
  func unreadableTreeIsUnknownInsteadOfInactive() {
    // A collapsed accessibility tree exposes no window and no web area. It
    // cannot prove that no call is running, so the latch fails closed.
    var latch = MeetLatch()
    let result = latch.apply(
      .init(
        chromeRunning: true,
        scanCompleted: true,
        confirmedSessions: [],
        liveAnchors: [],
        contentReadable: false
      ),
      now: now,
      maxLatchDuration: .seconds(14_400)
    )
    #expect(result == .unknown)
  }

  @Test
  func unreadableTreeHoldsAConfirmedCall() {
    // A busy meeting is never downgraded to unknown because the tree
    // collapsed while it was being read.
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
        contentReadable: false
      ),
      now: now.advanced(by: .seconds(5)),
      maxLatchDuration: .seconds(14_400)
    )
    #expect(result == .active)
    #expect(latch.activeAnchors == [anchor])
  }

  @Test
  func unavailableVisibilityWithAnUnreadableTreeHoldsTheCall() {
    // Leaving a call from the picture-in-picture popover tears the browser
    // window down. While the tree is collapsed the missing call control is
    // not evidence that the call ended, so a busy meeting keeps its hold
    // instead of turning into "status unavailable".
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
        liveAnchors: [],
        visibility: .unavailable,
        contentReadable: false
      ),
      now: now.advanced(by: .seconds(5)),
      maxLatchDuration: .seconds(14_400)
    )

    #expect(result == .active)
    #expect(latch.activeAnchors == [anchor])
  }
}

private let now = ContinuousClock().now

private func anchor(at instant: ContinuousClock.Instant) -> MeetLatch.Anchor {
  MeetLatch.Anchor(windowID: CGWindowID(42), tabIdentity: "tab", confirmedAt: instant)
}
