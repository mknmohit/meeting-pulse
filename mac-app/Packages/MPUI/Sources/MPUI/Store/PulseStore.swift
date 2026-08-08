import Foundation
import Observation
import MPCore
import MPSupport
import WebKit

@MainActor
@Observable
public final class PulseStore {
  public var effectiveState: State = .unavailable
  public var callsOkay = false
  public var statusReason: StatusReason?
  public var lastSync: SyncSnapshot = .empty
  public var lastPublished: Date?
  public var syncState: SyncState = .idle
  public var publishState: PublishState = .never
  public var isPublishing = false
  public var isOnline = true

  public var accessibilityGranted = false
  public var meet: SourceObservation?
  public var slack: SourceObservation?
  public var meetSeenAt: Date?
  public var slackSeenAt: Date?
  public var idleCheckInterval: Duration = .seconds(20)
  public var activeCheckInterval: Duration = .seconds(5)

  public var displayName = "" {
    didSet {
      if displayName.count > 80 {
        displayName = String(displayName.prefix(80))
      }
    }
  }
  public var mode: PulseMode = .automatic
  public var preferredDuration: ManualOverride.Duration = .m30
  public var overrideExpiry: Date?

  public var pairingCode: String?
  public var viewerLinks: [URL] = []
  public var viewers: Loadable<[ViewerSummary]> = .idle
  public var isCreatingViewerLink = false

  public var launchAtLogin = false
  public var openWindowAtLogin = false
  public var recoveryPhrase: String?
  public var installLocationIsValid = true

  public var section: StationSection = .watch
  public var stationVisible = false
  public var turnstilePresentation: TurnstilePresentationState = .hidden
  public var turnstileWebView: WKWebView?
  public var setupFailure: String?
  public var setupFailureHeadline = MPString.error.genericSetup
  public var hasCompletedOnboarding = false
  public var deleteCompleted = false
  public var lastError: PulseError?
  public var didAutoAdvance = false

  public init() {}

  public var plateFace: PlateFace {
    PlateFace(state: effectiveState, callsOkay: callsOkay, isFresh: isFresh)
  }

  public var plateHeadline: String {
    switch plateFace {
    case .meeting:
      return MPString.board.busyHeadline(named: displayName.isEmpty ? nil : displayName)
    case .callOkay:
      return MPString.board.callOkayHeadline(named: displayName.isEmpty ? nil : displayName)
    case .generic:
      return MPString.board.genericHeadline
    }
  }

  public var plateSupporting: String {
    if plateFace == .generic, !isOnline {
      return MPString.board.offlineSubhead
    }
    switch plateFace {
    case .meeting:
      return MPString.board.busySubhead
    case .callOkay:
      return MPString.board.callOkaySubhead
    case .generic:
      return MPString.board.genericSubhead
    }
  }

  public var reasonLine: String {
    reasonLine(at: .now)
  }

  public func reasonLine(
    at now: Date,
    presentation: ReasonLinePresentation = .station
  ) -> String {
    ReasonLineBuilder.build(
      deleteCompleted: deleteCompleted,
      accessibilityGranted: accessibilityGranted,
      syncState: syncState,
      hasViewerLink: hasViewerLink,
      mode: mode,
      overrideExpiry: overrideExpiry,
      stateReason: statusReason,
      callsOkay: callsOkay,
      face: plateFace,
      activeSource: activeSource,
      presentation: presentation,
      now: now
    ).0
  }

  public var reasonTone: ReasonTone {
    ReasonLineBuilder.build(
      deleteCompleted: deleteCompleted,
      accessibilityGranted: accessibilityGranted,
      syncState: syncState,
      hasViewerLink: hasViewerLink,
      mode: mode,
      overrideExpiry: overrideExpiry,
      stateReason: statusReason,
      callsOkay: callsOkay,
      face: plateFace,
      activeSource: activeSource
    ).1
  }

  public var hasViewerLink: Bool {
    !viewerLinks.isEmpty
  }

  public var primaryViewerLink: URL? {
    viewerLinks.first
  }

  public var hasOverride: Bool {
    mode != .automatic
  }

  public var isFresh: Bool {
    guard let lastPublished else {
      return false
    }
    return Date.now.timeIntervalSince(lastPublished) <= TimeInterval(Staleness.staleAfterSeconds)
  }

  public var needsAttention: Bool {
    setupFailure != nil
      || !accessibilityGranted
      || !installLocationIsValid
      || syncState == .retrying
      || syncState == .superseded
  }

  private var activeSource: String? {
    if meet == .active {
      return MPString.station.googleMeet
    }
    if slack == .active {
      return MPString.station.slackHuddles
    }
    return nil
  }

  public func apply(
    status: EffectiveStatus,
    reading: SchedulerReadingSnapshot? = nil,
    publishedAt: Date? = nil
  ) {
    effectiveState = status.state
    callsOkay = status.callOkay
    statusReason = status.reason
    if let publishedAt {
      lastPublished = publishedAt
      publishState = .published(at: publishedAt)
    }
    let freshness: Freshness = lastPublished.map {
      .fresh(secondsAgo: max(Int(Date.now.timeIntervalSince($0)), 0))
    } ?? .stale(.now)
    lastSync = SyncSnapshot(
      state: status.state,
      callOkay: status.callOkay,
      freshness: freshness,
      capturedAt: .now
    )
    if let reading {
      meet = reading.meet
      slack = reading.slack
      accessibilityGranted = reading.accessibilityGranted
      meetSeenAt = reading.capturedAt
      slackSeenAt = reading.capturedAt
    }
  }

  public func setOverride(_ override: ManualOverride?) {
    guard let override else {
      mode = .automatic
      overrideExpiry = nil
      return
    }
    mode = override.state == .busy ? .busy : .available
    overrideExpiry = override.expiresAtWall
    effectiveState = override.state
  }
}

public struct SchedulerReadingSnapshot: Equatable, Sendable {
  public let meet: SourceObservation
  public let slack: SourceObservation
  public let accessibilityGranted: Bool
  public let capturedAt: Date

  public init(
    meet: SourceObservation,
    slack: SourceObservation,
    accessibilityGranted: Bool,
    capturedAt: Date = .now
  ) {
    self.meet = meet
    self.slack = slack
    self.accessibilityGranted = accessibilityGranted
    self.capturedAt = capturedAt
  }
}
