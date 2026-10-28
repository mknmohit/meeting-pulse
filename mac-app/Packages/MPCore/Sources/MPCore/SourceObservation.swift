public enum SourceID: String, CaseIterable, Codable, Sendable {
  case googleMeet
  case slackHuddle
}

public enum SourceObservation: String, CaseIterable, Codable, Equatable, Sendable {
  case active
  case inactive
  case unknown
  case sourceAbsent
}

public enum DetectorHealth: Equatable, Sendable {
  case ok
  case degraded(DiagnosticCode)
  case permissionDenied
  case absent
}

extension DetectorHealth {
  /// The stable code of the health state.
  ///
  /// The code names the source and the failure, so the diagnostics view and
  /// the log can point at the application that needs attention.
  public var diagnosticCode: String {
    switch self {
    case .ok:
      "OK"
    case .degraded(let code):
      code.rawValue
    case .permissionDenied:
      "PERMISSION_DENIED"
    case .absent:
      "ABSENT"
    }
  }

  /// True when the detector cannot vouch for the state of its source.
  ///
  /// A degraded detector is the only health that points at one source; a
  /// missing permission is an app-wide problem and an absent source is
  /// normal.
  public var needsAttention: Bool {
    switch self {
    case .ok, .absent:
      false
    case .degraded, .permissionDenied:
      true
    }
  }
}

/// The source that needs the user's attention, if any.
///
/// The menu bar names this source so an unavailable status is not a dead end.
public enum SourceAttention: Equatable, Sendable {
  case none
  case googleMeet
  case slackHuddle

  public init(
    meet: SourceObservation,
    slack: SourceObservation,
    meetHealth: DetectorHealth = .ok,
    slackHealth: DetectorHealth = .ok
  ) {
    if meet == .unknown || meetHealth.needsAttention {
      self = .googleMeet
    } else if slack == .unknown || slackHealth.needsAttention {
      self = .slackHuddle
    } else {
      self = .none
    }
  }
}
