import Foundation
import Testing

@testable import MPSupport

struct LegacyStorageResetTests {
  @Test
  func resetClearsSetupOnceAndIsIdempotent() throws {
    let suiteName = "MeetingPulse.LegacyResetTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    defaults.set(true, forKey: "setup.completed")
    let cleaner = CleanerSpy()
    let reset = LegacyStorageReset(defaults: defaults, cleaner: cleaner)

    #expect(try reset.resetIfNeeded())
    #expect(!defaults.bool(forKey: "setup.completed"))
    #expect(defaults.bool(forKey: LegacyStorageReset.sentinelKey))
    #expect(cleaner.calls == 1)
    #expect(!(try reset.resetIfNeeded()))
    #expect(cleaner.calls == 1)
  }

  @Test
  func cleanupFailureDoesNotMarkResetComplete() throws {
    let suiteName = "MeetingPulse.LegacyResetFailureTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    defaults.set(true, forKey: "setup.completed")
    let cleaner = CleanerSpy(error: CleanupFailure.failed)
    let reset = LegacyStorageReset(defaults: defaults, cleaner: cleaner)

    #expect(throws: CleanupFailure.failed) {
      _ = try reset.resetIfNeeded()
    }
    #expect(defaults.bool(forKey: "setup.completed"))
    #expect(!defaults.bool(forKey: LegacyStorageReset.sentinelKey))
  }
}

private enum CleanupFailure: Error, Equatable {
  case failed
}

private final class CleanerSpy: LegacyKeychainCleaner, @unchecked Sendable {
  private(set) var calls = 0
  let error: CleanupFailure?

  init(error: CleanupFailure? = nil) {
    self.error = error
  }

  func removeMeetingPulseItems() throws {
    calls += 1
    if let error {
      throw error
    }
  }
}
