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
