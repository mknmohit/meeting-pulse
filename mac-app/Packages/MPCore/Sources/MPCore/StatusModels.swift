import Foundation

public enum State: String, CaseIterable, Codable, Equatable, Sendable {
  case available
  case busy
  case unavailable
}

public enum StatusReason: String, Codable, Equatable, Sendable {
  case manualOverride
  case confirmedActiveSource
  case permissionDenied
  case untrustedSource
  case allSourcesInactive
}

public struct EffectiveStatus: Codable, Equatable, Sendable {
  public let state: State
  public let callOkay: Bool
  public let isOverridden: Bool
  public let reason: StatusReason

  public init(
    state: State,
    callOkay: Bool,
    isOverridden: Bool,
    reason: StatusReason
  ) {
    self.state = state
    self.callOkay = callOkay
    self.isOverridden = isOverridden
    self.reason = reason
  }
}

public struct ReducerInput: Sendable {
  public let meet: SourceObservation
  public let slack: SourceObservation
  public let accessibilityGranted: Bool
  public let override: ManualOverride?
  public let callOkay: Bool
  public let monotonicNow: ContinuousClock.Instant

  public init(
    meet: SourceObservation,
    slack: SourceObservation,
    accessibilityGranted: Bool,
    override: ManualOverride?,
    callOkay: Bool,
    monotonicNow: ContinuousClock.Instant
  ) {
    self.meet = meet
    self.slack = slack
    self.accessibilityGranted = accessibilityGranted
    self.override = override
    self.callOkay = callOkay
    self.monotonicNow = monotonicNow
  }
}
