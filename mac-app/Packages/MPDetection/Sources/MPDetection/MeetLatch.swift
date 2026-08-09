import CoreGraphics
import MPCore

public enum DetectionVisibility: Equatable, Sendable {
  case authoritative
  case transitionGrace
  case recreationGrace
  case unavailable
}

public struct MeetLatch: Sendable {
  public struct Anchor: Equatable, Hashable, Sendable {
    public let windowID: CGWindowID
    public let tabIdentity: String
    public let confirmedAt: ContinuousClock.Instant

    public init(
      windowID: CGWindowID,
      tabIdentity: String,
      confirmedAt: ContinuousClock.Instant
    ) {
      self.windowID = windowID
      self.tabIdentity = tabIdentity
      self.confirmedAt = confirmedAt
    }
  }

  public struct Evidence: Sendable {
    public let chromeRunning: Bool
    public let scanCompleted: Bool
    public let confirmedSessions: Set<Anchor>
    public let liveAnchors: Set<Anchor>
    public let visibility: DetectionVisibility

    public init(
      chromeRunning: Bool,
      scanCompleted: Bool,
      confirmedSessions: Set<Anchor>,
      liveAnchors: Set<Anchor>,
      visibility: DetectionVisibility = .authoritative
    ) {
      self.chromeRunning = chromeRunning
      self.scanCompleted = scanCompleted
      self.confirmedSessions = confirmedSessions
      self.liveAnchors = liveAnchors
      self.visibility = visibility
    }
  }

  private var anchors = Set<Anchor>()

  public init() {}

  public var activeAnchors: Set<Anchor> {
    anchors
  }

  public mutating func apply(
    _ evidence: Evidence,
    now: ContinuousClock.Instant,
    maxLatchDuration: Duration
  ) -> SourceObservation {
    if anchors.isEmpty {
      guard evidence.chromeRunning else {
        return .sourceAbsent
      }
      if !evidence.confirmedSessions.isEmpty {
        anchors = evidence.confirmedSessions
        return .active
      }
      guard evidence.visibility == .authoritative else {
        return .unknown
      }
      return evidence.scanCompleted ? .inactive : .unknown
    }

    if !evidence.chromeRunning {
      anchors.removeAll()
      return .inactive
    }

    if anchors.contains(where: {
      now >= $0.confirmedAt.advanced(by: maxLatchDuration)
    }) {
      anchors.removeAll()
      return .unknown
    }

    if !evidence.confirmedSessions.isEmpty {
      anchors = evidence.confirmedSessions
      return .active
    }

    switch evidence.visibility {
    case .transitionGrace, .recreationGrace:
      return .active
    case .unavailable:
      return .unknown
    case .authoritative:
      break
    }

    if !evidence.liveAnchors.isEmpty {
      anchors = evidence.liveAnchors
      return .active
    }

    if !evidence.scanCompleted {
      return .unknown
    }

    anchors.removeAll()
    return .inactive
  }
}
