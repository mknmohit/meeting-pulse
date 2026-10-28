import CoreGraphics
import Testing

@testable import MPDetection

struct SlackHuddleLatchTests {
  @Test
  func confirmedHuddleCreatesAnActiveLatch() {
    var latch = SlackHuddleLatch()
    let anchor = anchor(at: now)
    let result = latch.apply(
      .init(
        slackRunning: true,
        scanCompleted: true,
        huddleWindowPresent: true,
        confirmedSessions: [anchor]
      )
    )

    #expect(result == .active)
    #expect(latch.activeAnchors == [anchor])
  }

  @Test
  func transitionGraceMaintainsHuddleWhenWindowIsOffSpace() {
    var latch = SlackHuddleLatch()
    let anchor = anchor(at: now)
    _ = latch.apply(
      .init(
        slackRunning: true,
        scanCompleted: true,
        huddleWindowPresent: true,
        confirmedSessions: [anchor]
      )
    )

    let result = latch.apply(
      .init(
        slackRunning: true,
        scanCompleted: true,
        huddleWindowPresent: false,
        confirmedSessions: [],
        visibility: .transitionGrace
      )
    )

    #expect(result == .active)
    #expect(latch.activeAnchors == [anchor])
  }

  @Test
  func authoritativeEndReleasesHuddle() {
    var latch = SlackHuddleLatch()
    let anchor = anchor(at: now)
    _ = latch.apply(
      .init(
        slackRunning: true,
        scanCompleted: true,
        huddleWindowPresent: true,
        confirmedSessions: [anchor]
      )
    )

    let result = latch.apply(
      .init(
        slackRunning: true,
        scanCompleted: true,
        huddleWindowPresent: false,
        confirmedSessions: []
      )
    )

    #expect(result == .inactive)
    #expect(latch.activeAnchors.isEmpty)
  }

  @Test
  func longRunningHuddleRemainsActiveWithoutLatchExpiry() {
    var latch = SlackHuddleLatch()
    let anchor = anchor(at: now.advanced(by: .seconds(-14_401)))
    _ = latch.apply(
      .init(
        slackRunning: true,
        scanCompleted: true,
        huddleWindowPresent: true,
        confirmedSessions: [anchor]
      )
    )

    let result = latch.apply(
      .init(
        slackRunning: true,
        scanCompleted: true,
        huddleWindowPresent: true,
        confirmedSessions: [],
        visibility: .authoritative
      )
    )

    #expect(result == .active)
    #expect(latch.activeAnchors == [anchor])
  }

  @Test
  func incompleteUnavailableScanKeepsTheHuddleAnchored() {
    var latch = SlackHuddleLatch()
    let anchor = anchor(at: now)
    _ = latch.apply(
      .init(
        slackRunning: true,
        scanCompleted: true,
        huddleWindowPresent: true,
        confirmedSessions: [anchor]
      )
    )

    // The scan could not be completed, so the huddle may still be running.
    // The observation stays unknown, but the anchors are kept so the huddle
    // is not dropped.
    let result = latch.apply(
      .init(
        slackRunning: true,
        scanCompleted: false,
        huddleWindowPresent: false,
        confirmedSessions: [],
        visibility: .unavailable
      )
    )

    #expect(result == .unknown)
    #expect(latch.activeAnchors == [anchor])
  }

  @Test
  func unavailableScanWithTheHuddleWindowPresentKeepsTheHuddleActive() {
    var latch = SlackHuddleLatch()
    let anchor = anchor(at: now)
    _ = latch.apply(
      .init(
        slackRunning: true,
        scanCompleted: true,
        huddleWindowPresent: true,
        confirmedSessions: [anchor]
      )
    )

    let result = latch.apply(
      .init(
        slackRunning: true,
        scanCompleted: false,
        huddleWindowPresent: true,
        confirmedSessions: [],
        visibility: .unavailable
      )
    )

    #expect(result == .active)
    #expect(latch.activeAnchors == [anchor])
  }

  @Test
  func unavailableScanWithoutTheHuddleWindowEndsTheHuddle() {
    var latch = SlackHuddleLatch()
    let anchor = anchor(at: now)
    _ = latch.apply(
      .init(
        slackRunning: true,
        scanCompleted: true,
        huddleWindowPresent: true,
        confirmedSessions: [anchor]
      )
    )

    // The scan completed and no huddle window is left, so the huddle ended
    // even though the visibility is degraded.
    let result = latch.apply(
      .init(
        slackRunning: true,
        scanCompleted: true,
        huddleWindowPresent: false,
        confirmedSessions: [],
        visibility: .unavailable
      )
    )

    #expect(result == .inactive)
    #expect(latch.activeAnchors.isEmpty)
  }

  @Test
  func huddleWindowWithoutControlsPreservesActiveHuddle() {
    var latch = SlackHuddleLatch()
    let anchor = anchor(at: now)
    _ = latch.apply(
      .init(
        slackRunning: true,
        scanCompleted: true,
        huddleWindowPresent: true,
        confirmedSessions: [anchor]
      )
    )

    let result = latch.apply(
      .init(
        slackRunning: true,
        scanCompleted: true,
        huddleWindowPresent: true,
        confirmedSessions: []
      )
    )

    #expect(result == .active)
    #expect(latch.activeAnchors == [anchor])
  }

  @Test
  func slackTerminationClearsHuddle() {
    var latch = SlackHuddleLatch()
    let anchor = anchor(at: now)
    _ = latch.apply(
      .init(
        slackRunning: true,
        scanCompleted: true,
        huddleWindowPresent: true,
        confirmedSessions: [anchor]
      )
    )

    let result = latch.apply(
      .init(
        slackRunning: false,
        scanCompleted: true,
        huddleWindowPresent: false,
        confirmedSessions: []
      )
    )

    #expect(result == .sourceAbsent)
    #expect(latch.activeAnchors.isEmpty)
  }

  @Test
  func unreadableTreeIsUnknownInsteadOfInactive() {
    // A collapsed accessibility tree exposes no window and no huddle
    // content. It cannot prove that no huddle is running.
    var latch = SlackHuddleLatch()
    let result = latch.apply(
      .init(
        slackRunning: true,
        scanCompleted: true,
        huddleWindowPresent: false,
        confirmedSessions: [],
        contentReadable: false
      )
    )

    #expect(result == .unknown)
  }

  @Test
  func unreadableTreeHoldsAConfirmedHuddle() {
    // A busy huddle is never downgraded because the tree collapsed while it
    // was being read.
    var latch = SlackHuddleLatch()
    let anchor = anchor(at: now)
    _ = latch.apply(
      .init(
        slackRunning: true,
        scanCompleted: true,
        huddleWindowPresent: true,
        confirmedSessions: [anchor]
      )
    )

    let result = latch.apply(
      .init(
        slackRunning: true,
        scanCompleted: true,
        huddleWindowPresent: false,
        confirmedSessions: [],
        contentReadable: false
      )
    )

    #expect(result == .active)
    #expect(latch.activeAnchors == [anchor])
  }
}

private let now = ContinuousClock().now

private func anchor(at instant: ContinuousClock.Instant) -> SlackHuddleLatch.Anchor {
  SlackHuddleLatch.Anchor(
    processIdentifier: 42,
    windowID: CGWindowID(8),
    confirmedAt: instant
  )
}
