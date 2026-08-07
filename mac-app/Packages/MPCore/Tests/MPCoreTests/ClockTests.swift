import Foundation
import Testing

@testable import MPCore

struct ClockTests {
  @Test
  func fixedMonotonicClockSatisfiesInjectedSeam() {
    let instant = ContinuousClock().now
    let clock = FixedMonotonicClock(instant: instant)
    #expect(clock.now() == instant)
  }

  @Test
  func systemWallClockProducesWallTime() {
    let before = Date()
    let now = SystemWallClock().now
    let after = Date()
    #expect(now >= before)
    #expect(now <= after)
  }
}

private struct FixedMonotonicClock: Monotonic {
  let instant: ContinuousClock.Instant

  func now() -> ContinuousClock.Instant {
    instant
  }

  func sleep(until: ContinuousClock.Instant) async throws {}
}
