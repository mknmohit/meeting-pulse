import Foundation
import MPCore
import Testing

@testable import MPSupport

struct ManualOverrideStoreTests {
  @Test
  func setPersistsAndReloadsAnOverride() async throws {
    let fileSystem = InMemoryOverrideFileSystem()
    let wallClock = MutableWallClock(now: Date(timeIntervalSince1970: 1_000))
    let monotonic = NonExpiringMonotonicClock()
    let store = ManualOverrideStore(
      fileURL: URL(fileURLWithPath: "/tmp/override.json"),
      wallClock: wallClock,
      monotonic: monotonic,
      fileSystem: fileSystem
    )

    let saved = try await store.set(state: .busy, duration: .m30)
    let reloaded = ManualOverrideStore(
      fileURL: URL(fileURLWithPath: "/tmp/override.json"),
      wallClock: wallClock,
      monotonic: monotonic,
      fileSystem: fileSystem
    )
    let loaded = await reloaded.load()

    #expect(saved.state == .busy)
    #expect(loaded?.state == .busy)
    #expect(loaded?.expiresAtWall == saved.expiresAtWall)
    #expect(loaded?.deadline != nil)
  }

  @Test
  func customDurationPersistsItsCalculatedExpiry() async throws {
    let fileSystem = InMemoryOverrideFileSystem()
    let wallClock = MutableWallClock(now: Date(timeIntervalSince1970: 1_000))
    let monotonic = NonExpiringMonotonicClock()
    let store = ManualOverrideStore(
      fileURL: URL(fileURLWithPath: "/tmp/override.json"),
      wallClock: wallClock,
      monotonic: monotonic,
      fileSystem: fileSystem
    )

    let saved = try await store.set(
      state: .available,
      duration: .custom(minutes: 90)
    )

    #expect(saved.expiresAtWall == Date(timeIntervalSince1970: 6_400))
    #expect(saved.state == .available)
  }

  @Test
  func invalidCustomDurationDoesNotReplaceCurrentOverride() async throws {
    let fileSystem = InMemoryOverrideFileSystem()
    let store = ManualOverrideStore(
      fileURL: URL(fileURLWithPath: "/tmp/override.json"),
      wallClock: MutableWallClock(now: Date(timeIntervalSince1970: 1_000)),
      monotonic: NonExpiringMonotonicClock(),
      fileSystem: fileSystem
    )
    _ = try await store.set(state: .busy, duration: .m30)

    do {
      _ = try await store.set(
        state: .available,
        duration: .custom(minutes: 1_441)
      )
      Issue.record("Invalid custom duration was accepted")
    } catch let error as ManualOverride.ValidationError {
      #expect(error == .invalidDuration)
    }

    #expect((await store.current)?.state == .busy)
  }

  @Test
  func malformedFileIsDiscardedAndLogged() async {
    let fileSystem = InMemoryOverrideFileSystem(data: Data("{".utf8))
    let log = LogSink()
    let store = ManualOverrideStore(
      fileURL: URL(fileURLWithPath: "/tmp/override.json"),
      wallClock: MutableWallClock(now: Date()),
      monotonic: FixedMonotonicClock(),
      fileSystem: fileSystem,
      log: { message in log.messages.append(message) }
    )

    let loaded = await store.load()

    #expect(loaded == nil)
    #expect(log.messages.contains("OVERRIDE_FILE_INVALID"))
    #expect(fileSystem.data == nil)
  }

  @Test
  func backwardsWallClockCannotExtendOriginalDuration() async throws {
    let fileSystem = InMemoryOverrideFileSystem()
    let originalWallClock = MutableWallClock(now: Date(timeIntervalSince1970: 1_000))
    let monotonic = NonExpiringMonotonicClock()
    let firstStore = ManualOverrideStore(
      fileURL: URL(fileURLWithPath: "/tmp/override.json"),
      wallClock: originalWallClock,
      monotonic: monotonic,
      fileSystem: fileSystem
    )
    _ = try await firstStore.set(state: .busy, duration: .m15)

    originalWallClock.now = Date(timeIntervalSince1970: 0)
    let reloaded = ManualOverrideStore(
      fileURL: URL(fileURLWithPath: "/tmp/override.json"),
      wallClock: originalWallClock,
      monotonic: monotonic,
      fileSystem: fileSystem
    )
    let loaded = await reloaded.load()

    #expect(loaded?.deadline == monotonic.instant.advanced(by: .seconds(900)))
  }

  @Test
  func expiryPublishesImmediately() async throws {
    let fileSystem = InMemoryOverrideFileSystem()
    let publisher = PublishSink()
    let store = ManualOverrideStore(
      fileURL: URL(fileURLWithPath: "/tmp/override.json"),
      wallClock: MutableWallClock(now: Date()),
      monotonic: ImmediateMonotonicClock(),
      fileSystem: fileSystem,
      publish: { value in publisher.values.append(value) }
    )

    _ = try await store.set(state: .busy, duration: .m15)
    for _ in 0..<20 {
      await Task.yield()
    }
    try? await Task.sleep(for: .milliseconds(10))

    #expect(publisher.values.count == 1)
    guard let first = publisher.values.first else {
      Issue.record("Expiry did not publish a value")
      return
    }
    #expect(first == nil)
    let current = await store.current
    #expect(current == nil)
  }

  @Test
  func replacingAnOverridePreventsTheOldExpiryFromClearingIt() async throws {
    let fileSystem = InMemoryOverrideFileSystem()
    let publisher = PublishSink()
    let store = ManualOverrideStore(
      fileURL: URL(fileURLWithPath: "/tmp/override.json"),
      wallClock: MutableWallClock(now: Date()),
      monotonic: DelayedMonotonicClock(),
      fileSystem: fileSystem,
      publish: { value in publisher.values.append(value) }
    )

    _ = try await store.set(state: .busy, duration: .m15)
    _ = try await store.set(state: .available, duration: .m30)
    for _ in 0..<20 {
      await Task.yield()
    }

    #expect((await store.current)?.state == .available)
    #expect(publisher.values.isEmpty)
  }
}

private final class MutableWallClock: WallClock, @unchecked Sendable {
  var now: Date

  init(now: Date) {
    self.now = now
  }
}

private struct FixedMonotonicClock: Monotonic {
  let instant: ContinuousClock.Instant

  init() {
    instant = ContinuousClock().now
  }

  func now() -> ContinuousClock.Instant {
    instant
  }

  func sleep(until: ContinuousClock.Instant) async throws {}
}

private struct NonExpiringMonotonicClock: Monotonic {
  let instant = ContinuousClock().now

  func now() -> ContinuousClock.Instant {
    instant
  }

  func sleep(until: ContinuousClock.Instant) async throws {
    try await Task.sleep(for: .seconds(60))
  }
}

private struct ImmediateMonotonicClock: Monotonic {
  let instant = ContinuousClock().now

  func now() -> ContinuousClock.Instant {
    instant
  }

  func sleep(until: ContinuousClock.Instant) async throws {}
}

private struct DelayedMonotonicClock: Monotonic {
  let instant = ContinuousClock().now

  func now() -> ContinuousClock.Instant {
    instant
  }

  func sleep(until: ContinuousClock.Instant) async throws {
    try await Task.sleep(for: .seconds(1))
  }
}

private final class InMemoryOverrideFileSystem: OverrideFileSystem, @unchecked Sendable {
  var data: Data?

  init(data: Data? = nil) {
    self.data = data
  }

  func read(_: URL) throws -> Data? {
    data
  }

  func atomicWrite(_ data: Data, to _: URL) throws {
    self.data = data
  }

  func remove(_: URL) throws {
    data = nil
  }
}

private final class LogSink: @unchecked Sendable {
  var messages = [String]()
}

private final class PublishSink: @unchecked Sendable {
  var values = [ManualOverride?]()
}
