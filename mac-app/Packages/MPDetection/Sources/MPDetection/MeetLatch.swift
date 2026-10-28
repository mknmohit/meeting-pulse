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
    /// A Meet page is present and exposes its content, so the absence of call
    /// controls is positive evidence that no call is running.
    public let meetSurfaceReadable: Bool
    /// A complete scan found no Meet page and no Meet tab, so the Meet tab
    /// was closed and the call is over.
    public let meetSurfaceAbsent: Bool
    /// The application exposed readable content.
    ///
    /// A browser whose accessibility server collapsed into its menu bar can
    /// be walked end to end and still expose no window and no web area. Such
    /// a tree cannot prove that no call is running, so the latch reports it
    /// as unknown instead of inactive.
    public let contentReadable: Bool
    /// The number of elements the scan kept.
    public let elementCount: Int

    public init(
      chromeRunning: Bool,
      scanCompleted: Bool,
      confirmedSessions: Set<Anchor>,
      liveAnchors: Set<Anchor>,
      visibility: DetectionVisibility = .authoritative,
      meetSurfaceReadable: Bool = false,
      meetSurfaceAbsent: Bool = false,
      contentReadable: Bool = true,
      elementCount: Int = 0
    ) {
      self.chromeRunning = chromeRunning
      self.scanCompleted = scanCompleted
      self.confirmedSessions = confirmedSessions
      self.liveAnchors = liveAnchors
      self.visibility = visibility
      self.meetSurfaceReadable = meetSurfaceReadable
      self.meetSurfaceAbsent = meetSurfaceAbsent
      self.contentReadable = contentReadable
      self.elementCount = elementCount
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
    maxLatchDuration: Duration? = nil
  ) -> SourceObservation {
    if anchors.isEmpty {
      guard evidence.chromeRunning else {
        return .sourceAbsent
      }
      if !evidence.confirmedSessions.isEmpty {
        anchors = evidence.confirmedSessions
        return .active
      }
      if evidence.visibility == .transitionGrace || evidence.visibility == .recreationGrace {
        return .unknown
      }
      if evidence.scanCompleted, evidence.meetSurfaceReadable {
        // The Meet page is readable and exposes no call controls, so there is
        // no call running. This is positive end evidence, not a missing signal.
        return .inactive
      }
      guard evidence.visibility == .authoritative else {
        return .unknown
      }
      guard evidence.contentReadable else {
        // The application exposed no window and no web content. The tree
        // collapsed, so the missing call control is not evidence that no call
        // is running.
        return .unknown
      }
      return evidence.scanCompleted ? .inactive : .unknown
    }

    if !evidence.chromeRunning {
      anchors.removeAll()
      return .inactive
    }

    if let maxLatchDuration,
      anchors.contains(where: {
        now >= $0.confirmedAt.advanced(by: maxLatchDuration)
      })
    {
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
      if evidence.scanCompleted,
        evidence.meetSurfaceReadable || evidence.meetSurfaceAbsent
      {
        // The error state is recoverable: the Meet page is readable and shows
        // no call controls, or the Meet surface is gone entirely. Either way
        // the call is provably over.
        anchors.removeAll()
        return .inactive
      }
      if !evidence.contentReadable {
        // The tree collapsed, so the missing call control is not evidence
        // that the call ended. The confirmed call keeps its hold instead of
        // downgrading a busy meeting to unavailable.
        return .active
      }
      return .unknown
    case .authoritative:
      break
    }

    if !evidence.contentReadable {
      // The tree collapsed into its menu bar. A missing call control is not
      // evidence that the call ended, so the latch keeps reporting the
      // confirmed call instead of downgrading a busy meeting.
      return .active
    }

    if !evidence.scanCompleted {
      // The scan was truncated, so a missing call control is not evidence that
      // the call ended. A long running meeting grows the accessibility tree
      // well past the element budget, so the latch keeps reporting the
      // confirmed call until a complete scan proves it is gone.
      return .active
    }

    if evidence.meetSurfaceReadable {
      // The page is readable and no call control was found, which is positive
      // evidence that the call ended.
      anchors.removeAll()
      return .inactive
    }

    if !evidence.liveAnchors.isEmpty {
      anchors = evidence.liveAnchors
      return .active
    }

    anchors.removeAll()
    return .inactive
  }
}
