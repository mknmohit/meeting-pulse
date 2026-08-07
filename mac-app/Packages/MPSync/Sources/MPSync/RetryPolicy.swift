import Foundation
import MPCore

public struct RetryPolicy: Equatable, Sendable {
  public let baseDelay: Duration
  public let multiplier: Double
  public let maximumDelay: Duration

  public init(
    baseDelay: Duration = .seconds(1),
    multiplier: Double = 2,
    maximumDelay: Duration = .seconds(60)
  ) {
    self.baseDelay = baseDelay
    self.multiplier = multiplier
    self.maximumDelay = maximumDelay
  }

  public func delay(for attempt: Int, randomUnit: Double) -> Duration {
    let boundedAttempt = max(attempt, 0)
    let exponential = baseDelay.secondsValue * pow(multiplier, Double(boundedAttempt))
    let capped = min(maximumDelay.secondsValue, exponential)
    let unit = min(max(randomUnit, 0), 1)
    return .seconds(capped * unit)
  }
}

public struct LatestPayloadBuffer<Value: Sendable>: Sendable {
  private var value: Value?

  public init() {}

  public var hasValue: Bool {
    value != nil
  }

  public mutating func replace(with value: Value) {
    self.value = value
  }

  public mutating func take() -> Value? {
    defer { value = nil }
    return value
  }
}

extension Duration {
  fileprivate var secondsValue: Double {
    let parts = components
    return Double(parts.seconds) + Double(parts.attoseconds) / 1_000_000_000_000_000_000
  }
}
