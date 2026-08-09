import CoreGraphics
import MPCore

public struct SlackHuddleLatch: Sendable {
  public struct Anchor: Equatable, Hashable, Sendable {
    public let processIdentifier: pid_t
    public let windowID: CGWindowID
    public let confirmedAt: ContinuousClock.Instant

    public init(
      processIdentifier: pid_t,
      windowID: CGWindowID,
      confirmedAt: ContinuousClock.Instant
    ) {
      self.processIdentifier = processIdentifier
      self.windowID = windowID
      self.confirmedAt = confirmedAt
    }
  }

  public struct Evidence: Sendable {
    public let slackRunning: Bool
    public let scanCompleted: Bool
    public let huddleWindowPresent: Bool
    public let confirmedSessions: Set<Anchor>
    public let visibility: DetectionVisibility

    public init(
      slackRunning: Bool,
      scanCompleted: Bool,
      huddleWindowPresent: Bool,
      confirmedSessions: Set<Anchor>,
      visibility: DetectionVisibility = .authoritative
    ) {
      self.slackRunning = slackRunning
      self.scanCompleted = scanCompleted
      self.huddleWindowPresent = huddleWindowPresent
      self.confirmedSessions = confirmedSessions
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
      guard evidence.slackRunning else {
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

    guard evidence.slackRunning else {
      anchors.removeAll()
      return .sourceAbsent
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

    if !evidence.scanCompleted {
      return .unknown
    }

    anchors.removeAll()
    return .inactive
  }
}
