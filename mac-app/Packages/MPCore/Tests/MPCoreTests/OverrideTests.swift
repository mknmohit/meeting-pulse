import Foundation
import Testing

@testable import MPCore

struct OverrideTests {
  @Test
  func durationPresetsMatchTheProductContract() {
    #expect(ManualOverride.Duration.default == .m30)
    #expect(ManualOverride.Duration.m15.seconds == 900)
    #expect(ManualOverride.Duration.m30.seconds == 1_800)
    #expect(ManualOverride.Duration.m45.seconds == 2_700)
    #expect(ManualOverride.Duration.h1.seconds == 3_600)
    #expect(ManualOverride.Duration.h2.seconds == 7_200)
    #expect(ManualOverride.Duration.h4.seconds == 14_400)
    #expect(ManualOverride.Duration.untilCleared.seconds == nil)
  }

  @Test
  func overrideRoundTripsWithoutPersistingMonotonicDeadline() throws {
    let override = try ManualOverride(
      state: .busy,
      createdAtWall: Date(timeIntervalSince1970: 1_000),
      expiresAtWall: Date(timeIntervalSince1970: 2_000),
      deadline: ContinuousClock().now
    )
    let data = try JSONEncoder().encode(override)
    let restored = try JSONDecoder().decode(ManualOverride.self, from: data)
    #expect(restored.state == .busy)
    #expect(restored.createdAtWall == override.createdAtWall)
    #expect(restored.expiresAtWall == override.expiresAtWall)
    #expect(restored.deadline == nil)
    #expect(!restored.isActive(at: ContinuousClock().now))
  }
}
