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
      ),
      now: now,
      maxLatchDuration: .seconds(14_400)
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
      ),
      now: now,
      maxLatchDuration: .seconds(14_400)
    )

    let result = latch.apply(
      .init(
        slackRunning: true,
        scanCompleted: true,
        huddleWindowPresent: false,
        confirmedSessions: [],
        visibility: .transitionGrace
      ),
      now: now.advanced(by: .seconds(5)),
      maxLatchDuration: .seconds(14_400)
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
      ),
      now: now,
      maxLatchDuration: .seconds(14_400)
    )

    let result = latch.apply(
      .init(
        slackRunning: true,
        scanCompleted: true,
        huddleWindowPresent: true,
        confirmedSessions: []
      ),
      now: now.advanced(by: .seconds(5)),
      maxLatchDuration: .seconds(14_400)
    )

    #expect(result == .inactive)
    #expect(latch.activeAnchors.isEmpty)
  }

  @Test
  func expiredSpaceVisibilityBecomesUnknown() {
    var latch = SlackHuddleLatch()
    let anchor = anchor(at: now)
    _ = latch.apply(
      .init(
        slackRunning: true,
        scanCompleted: true,
        huddleWindowPresent: true,
        confirmedSessions: [anchor]
      ),
      now: now,
      maxLatchDuration: .seconds(14_400)
    )

    let result = latch.apply(
      .init(
        slackRunning: true,
        scanCompleted: true,
        huddleWindowPresent: false,
        confirmedSessions: [],
        visibility: .unavailable
      ),
      now: now.advanced(by: .seconds(30)),
      maxLatchDuration: .seconds(14_400)
    )

    #expect(result == .unknown)
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
      ),
      now: now,
      maxLatchDuration: .seconds(14_400)
    )

    let result = latch.apply(
      .init(
        slackRunning: false,
        scanCompleted: true,
        huddleWindowPresent: false,
        confirmedSessions: []
      ),
      now: now.advanced(by: .seconds(5)),
      maxLatchDuration: .seconds(14_400)
    )

    #expect(result == .sourceAbsent)
    #expect(latch.activeAnchors.isEmpty)
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
