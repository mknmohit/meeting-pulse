import Foundation

public protocol WallClock: Sendable {
  var now: Date { get }
}

public protocol Monotonic: Sendable {
  func now() -> ContinuousClock.Instant
  func sleep(until: ContinuousClock.Instant) async throws
}

public struct SystemWallClock: WallClock, Sendable {
  public init() {}

  public var now: Date {
    Date()
  }
}

public struct SystemMonotonicClock: Monotonic, Sendable {
  private let clock: ContinuousClock

  public init() {
    clock = ContinuousClock()
  }

  public func now() -> ContinuousClock.Instant {
    clock.now
  }

  public func sleep(until deadline: ContinuousClock.Instant) async throws {
    try await clock.sleep(until: deadline)
  }
}
