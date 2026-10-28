import ApplicationServices
import MPCore

private let detectorNotifications = [
  kAXFocusedWindowChangedNotification as String,
  kAXWindowCreatedNotification as String,
  kAXUIElementDestroyedNotification as String,
]

/// The longest a single accessibility read may take.
///
/// A browser that stops answering holds the read on the accessibility
/// thread. The deadline keeps the detector producing readings and lets it
/// fail closed instead of waiting forever.
private let snapshotDeadline = Duration.seconds(12)

public actor GoogleMeetDetector: MeetingDetector {
  public nonisolated let sourceIdentifier: SourceID = .googleMeet

  private let appDiscovery: any AppDiscovery
  private let permissionProbe: any PermissionProbe
  private let elementTree: any AXElementTree
  private let eventSource: any AXEventSource
  private let monotonic: any Monotonic
  private var latch = MeetLatch()
  private var visibility = DetectionVisibility.authoritative
  private var visibilityGraceDeadline: ContinuousClock.Instant?
  private var unavailableSince: ContinuousClock.Instant?
  private var generation: UInt64 = 0
  private var samplingTask: Task<MeetSample, Never>?
  private var eventTask: Task<Void, Never>?
  private var observedPIDs = [pid_t]()
  private var continuation: AsyncStream<SourceObservation>.Continuation

  public private(set) var currentObservation: SourceObservation = .unknown
  public private(set) var health: DetectorHealth = .degraded(
    DiagnosticCode(rawValue: "MEET_NOT_STARTED")
  )
  public let observationStream: AsyncStream<SourceObservation>

  public init(
    appDiscovery: any AppDiscovery = WorkspaceAppDiscovery(),
    permissionProbe: any PermissionProbe = AccessibilityPermissionProbe(),
    elementTree: any AXElementTree = AXRunLoopHost.shared,
    eventSource: any AXEventSource = AXRunLoopHost.shared,
    monotonic: any Monotonic = SystemMonotonicClock()
  ) {
    self.appDiscovery = appDiscovery
    self.permissionProbe = permissionProbe
    self.elementTree = elementTree
    self.eventSource = eventSource
    self.monotonic = monotonic
    var continuation: AsyncStream<SourceObservation>.Continuation?
    observationStream = AsyncStream { continuation = $0 }
    self.continuation = continuation!
  }

  public func start() async {
    guard eventTask == nil else {
      return
    }
    await requestSample()
    for app in appDiscovery.runningApps(bundleIDs: ChromeFamily.bundleIDs) {
      do {
        try await eventSource.observe(
          pid: app.processIdentifier,
          notifications: detectorNotifications
        )
        observedPIDs.append(app.processIdentifier)
      } catch {
        health = .degraded(DiagnosticCode(rawValue: "AX_OBSERVER_ATTACH_FAILED"))
      }
    }
    eventTask = Task { [weak self] in
      guard let self else {
        return
      }
      for await _ in eventSource.events {
        await self.requestSample()
      }
    }
  }

  public func stop() async {
    eventTask?.cancel()
    eventTask = nil
    samplingTask?.cancel()
    samplingTask = nil
    visibility = .authoritative
    visibilityGraceDeadline = nil
    unavailableSince = nil
    for pid in observedPIDs {
      await eventSource.stopObserving(pid: pid)
    }
    observedPIDs.removeAll()
  }

  public func invalidate() async {
    samplingTask?.cancel()
    samplingTask = nil
    latch = MeetLatch()
    visibility = .authoritative
    visibilityGraceDeadline = nil
    unavailableSince = nil
    publish(.unknown, health: .permissionDenied)
  }

  public func spaceDidChange() async {
    guard currentObservation == .active || !latch.activeAnchors.isEmpty else {
      return
    }
    visibility = .transitionGrace
    visibilityGraceDeadline = monotonic.now().advanced(by: .seconds(20))
    unavailableSince = nil
  }

  public func requestSample() async {
    generation &+= 1
    let requestedGeneration = generation
    samplingTask?.cancel()
    let apps = appDiscovery.runningApps(bundleIDs: ChromeFamily.bundleIDs)
    let existingAnchors = latch.activeAnchors
    let permissionProbe = permissionProbe
    let elementTree = elementTree
    let monotonic = monotonic
    let task = Task {
      await Self.gather(
        apps: apps,
        existingAnchors: existingAnchors,
        permissionProbe: permissionProbe,
        elementTree: elementTree,
        monotonic: monotonic
      )
    }
    samplingTask = task
    let sample = await task.value
    guard requestedGeneration == generation else {
      return
    }
    samplingTask = nil
    if sample.permissionDenied {
      latch = MeetLatch()
      publish(.unknown, health: .permissionDenied)
      return
    }
    let now = monotonic.now()
    let visibility = resolvedVisibility(for: sample.evidence, now: now)
    let evidence = MeetLatch.Evidence(
      chromeRunning: sample.evidence.chromeRunning,
      scanCompleted: sample.evidence.scanCompleted,
      confirmedSessions: sample.evidence.confirmedSessions,
      liveAnchors: sample.evidence.liveAnchors,
      visibility: visibility,
      meetSurfaceReadable: sample.evidence.meetSurfaceReadable,
      meetSurfaceAbsent: sample.evidence.meetSurfaceAbsent,
      contentReadable: sample.evidence.contentReadable,
      elementCount: sample.evidence.elementCount
    )
    let observation = latch.apply(
      evidence,
      now: now,
      maxLatchDuration: nil
    )
    NSLog(
      "Meeting Pulse meet scan completed=%@ readable=%@ surface=%@ anchors=%@ elements=%d health=%@",
      sample.evidence.scanCompleted ? "1" : "0",
      sample.evidence.contentReadable ? "1" : "0",
      sample.evidence.meetSurfaceReadable ? "1" : "0",
      String(sample.evidence.confirmedSessions.count),
      sample.evidence.elementCount,
      sample.health.diagnosticCode
    )
    publish(observation, health: sample.health)
  }

  private func resolvedVisibility(
    for evidence: MeetLatch.Evidence,
    now: ContinuousClock.Instant
  ) -> DetectionVisibility {
    guard evidence.chromeRunning else {
      visibility = .authoritative
      visibilityGraceDeadline = nil
      unavailableSince = nil
      return .authoritative
    }
    if !evidence.confirmedSessions.isEmpty {
      visibility = .authoritative
      visibilityGraceDeadline = nil
      unavailableSince = nil
      return .authoritative
    }
    if visibility == .transitionGrace,
      let deadline = visibilityGraceDeadline,
      now >= deadline
    {
      visibility = .unavailable
      visibilityGraceDeadline = nil
      unavailableSince = now
    }
    if visibility == .unavailable {
      if evidence.scanCompleted,
        evidence.contentReadable,
        evidence.meetSurfaceReadable || evidence.meetSurfaceAbsent
      {
        // The degraded state is recoverable: the Meet page is readable and
        // exposes no call controls, or the Meet surface is gone entirely.
        // Either way the call is provably over.
        visibility = .authoritative
        visibilityGraceDeadline = nil
        unavailableSince = nil
      } else if let since = unavailableSince,
        now >= since.advanced(by: .seconds(45))
      {
        // Backstop: a degraded visibility must never stick forever.
        visibility = .authoritative
        visibilityGraceDeadline = nil
        unavailableSince = nil
      }
    }
    return visibility
  }

  private func publish(_ observation: SourceObservation, health: DetectorHealth) {
    self.health = health
    guard currentObservation != observation else {
      return
    }
    currentObservation = observation
    continuation.yield(observation)
  }

  private static func gather(
    apps: [RunningApp],
    existingAnchors: Set<MeetLatch.Anchor>,
    permissionProbe: any PermissionProbe,
    elementTree: any AXElementTree,
    monotonic: any Monotonic
  ) async -> MeetSample {
    guard permissionProbe.isTrusted else {
      return MeetSample(
        evidence: .init(
          chromeRunning: !apps.isEmpty,
          scanCompleted: false,
          confirmedSessions: [],
          liveAnchors: []
        ),
        health: .permissionDenied,
        permissionDenied: true
      )
    }
    guard !apps.isEmpty else {
      return MeetSample(
        evidence: .init(
          chromeRunning: false,
          scanCompleted: true,
          confirmedSessions: [],
          liveAnchors: []
        ),
        health: .absent,
        permissionDenied: false
      )
    }

    var scanCompleted = true
    var confirmedSessions = Set<MeetLatch.Anchor>()
    var liveAnchors = Set<MeetLatch.Anchor>()
    var meetSurfaceReadable = false
    var meetSurfacePresent = false
    var contentReadable = true
    var elementCount = 0
    var health: DetectorHealth = .ok

    for app in apps {
      do {
        let snapshot = try await withDeadline(snapshotDeadline) {
          try await elementTree.snapshot(
            pid: app.processIdentifier,
            maxDepth: 24,
            maxElements: 8_000
          )
        }
        scanCompleted = scanCompleted && snapshot.scanCompleted
        let analysis = MeetSelectors.analyze(
          in: snapshot,
          anchors: existingAnchors,
          confirmedAt: monotonic.now()
        )
        confirmedSessions.formUnion(analysis.confirmedSessions)
        liveAnchors.formUnion(analysis.liveAnchors)
        meetSurfaceReadable = meetSurfaceReadable || analysis.meetSurfaceReadable
        meetSurfacePresent = meetSurfacePresent || analysis.meetSurfacePresent
        contentReadable = contentReadable && snapshot.contentReadable
        elementCount += snapshot.elementCount
        if !snapshot.scanCompleted {
          health = .degraded(DiagnosticCode(rawValue: "MEET_SCAN_INCOMPLETE"))
        } else if !snapshot.contentReadable {
          // The browser exposed neither a window nor a web area. The tree
          // collapsed, so the absence of a call control proves nothing.
          health = .degraded(DiagnosticCode(rawValue: "MEET_AX_DEGENERATE"))
        }
      } catch let error as AXSnapshotError {
        scanCompleted = false
        health = .degraded(DiagnosticCode(rawValue: meetDiagnostic(for: error)))
      } catch {
        scanCompleted = false
        health = .degraded(DiagnosticCode(rawValue: "MEET_TREE_UNREADABLE"))
      }
    }

    return MeetSample(
      evidence: .init(
        chromeRunning: true,
        scanCompleted: scanCompleted,
        confirmedSessions: confirmedSessions,
        liveAnchors: liveAnchors,
        meetSurfaceReadable: meetSurfaceReadable,
        meetSurfaceAbsent: scanCompleted && contentReadable && !meetSurfacePresent,
        contentReadable: contentReadable,
        elementCount: elementCount
      ),
      health: health,
      permissionDenied: false
    )
  }
}

public actor SlackHuddleDetector: MeetingDetector {
  public nonisolated let sourceIdentifier: SourceID = .slackHuddle

  private let appDiscovery: any AppDiscovery
  private let permissionProbe: any PermissionProbe
  private let elementTree: any AXElementTree
  private let eventSource: any AXEventSource
  private let monotonic: any Monotonic
  private var latch = SlackHuddleLatch()
  private var visibility = DetectionVisibility.authoritative
  private var visibilityGraceDeadline: ContinuousClock.Instant?
  private var recreationGraceConsumed = false
  private var unavailableSince: ContinuousClock.Instant?
  private var generation: UInt64 = 0
  private var samplingTask: Task<SlackSample, Never>?
  private var eventTask: Task<Void, Never>?
  private var observedPIDs = [pid_t]()
  private var continuation: AsyncStream<SourceObservation>.Continuation

  public private(set) var currentObservation: SourceObservation = .unknown
  public private(set) var health: DetectorHealth = .degraded(
    DiagnosticCode(rawValue: "SLACK_NOT_STARTED")
  )
  public let observationStream: AsyncStream<SourceObservation>

  public init(
    appDiscovery: any AppDiscovery = WorkspaceAppDiscovery(),
    permissionProbe: any PermissionProbe = AccessibilityPermissionProbe(),
    elementTree: any AXElementTree = AXRunLoopHost.shared,
    eventSource: any AXEventSource = AXRunLoopHost.shared,
    monotonic: any Monotonic = SystemMonotonicClock()
  ) {
    self.appDiscovery = appDiscovery
    self.permissionProbe = permissionProbe
    self.elementTree = elementTree
    self.eventSource = eventSource
    self.monotonic = monotonic
    var continuation: AsyncStream<SourceObservation>.Continuation?
    observationStream = AsyncStream { continuation = $0 }
    self.continuation = continuation!
  }

  public func start() async {
    guard eventTask == nil else {
      return
    }
    await requestSample()
    for app in appDiscovery.runningApps(bundleIDs: SlackFamily.bundleIDs) {
      do {
        try await eventSource.observe(
          pid: app.processIdentifier,
          notifications: detectorNotifications
        )
        observedPIDs.append(app.processIdentifier)
      } catch {
        health = .degraded(DiagnosticCode(rawValue: "AX_OBSERVER_ATTACH_FAILED"))
      }
    }
    eventTask = Task { [weak self] in
      guard let self else {
        return
      }
      for await _ in eventSource.events {
        await self.requestSample()
      }
    }
  }

  public func stop() async {
    eventTask?.cancel()
    eventTask = nil
    samplingTask?.cancel()
    samplingTask = nil
    latch = SlackHuddleLatch()
    visibility = .authoritative
    visibilityGraceDeadline = nil
    recreationGraceConsumed = false
    unavailableSince = nil
    for pid in observedPIDs {
      await eventSource.stopObserving(pid: pid)
    }
    observedPIDs.removeAll()
  }

  public func invalidate() async {
    samplingTask?.cancel()
    samplingTask = nil
    latch = SlackHuddleLatch()
    visibility = .authoritative
    visibilityGraceDeadline = nil
    recreationGraceConsumed = false
    unavailableSince = nil
    publish(.unknown, health: .permissionDenied)
  }

  public func spaceDidChange() async {
    guard currentObservation == .active || !latch.activeAnchors.isEmpty else {
      return
    }
    visibility = .transitionGrace
    visibilityGraceDeadline = monotonic.now().advanced(by: .seconds(20))
    recreationGraceConsumed = false
    unavailableSince = nil
  }

  public func requestSample() async {
    generation &+= 1
    let requestedGeneration = generation
    samplingTask?.cancel()
    let apps = appDiscovery.runningApps(bundleIDs: SlackFamily.bundleIDs)
    let permissionProbe = permissionProbe
    let elementTree = elementTree
    let task = Task {
      await Self.gather(
        apps: apps,
        permissionProbe: permissionProbe,
        elementTree: elementTree,
        monotonic: monotonic
      )
    }
    samplingTask = task
    let sample = await task.value
    guard requestedGeneration == generation else {
      return
    }
    samplingTask = nil
    let now = monotonic.now()
    let visibility = resolvedVisibility(for: sample.evidence, now: now)
    let evidence = SlackHuddleLatch.Evidence(
      slackRunning: sample.evidence.slackRunning,
      scanCompleted: sample.evidence.scanCompleted,
      huddleWindowPresent: sample.evidence.huddleWindowPresent,
      confirmedSessions: sample.evidence.confirmedSessions,
      visibility: visibility,
      contentReadable: sample.evidence.contentReadable,
      elementCount: sample.evidence.elementCount
    )
    NSLog(
      "Meeting Pulse slack scan completed=%@ readable=%@ huddle=%@ anchors=%@ elements=%d health=%@",
      sample.evidence.scanCompleted ? "1" : "0",
      sample.evidence.contentReadable ? "1" : "0",
      sample.evidence.huddleWindowPresent ? "1" : "0",
      String(sample.evidence.confirmedSessions.count),
      sample.evidence.elementCount,
      sample.health.diagnosticCode
    )
    publish(
      latch.apply(
        evidence
      ),
      health: sample.health
    )
  }

  private func resolvedVisibility(
    for evidence: SlackHuddleLatch.Evidence,
    now: ContinuousClock.Instant
  ) -> DetectionVisibility {
    guard evidence.slackRunning else {
      visibility = .authoritative
      visibilityGraceDeadline = nil
      recreationGraceConsumed = false
      unavailableSince = nil
      return .authoritative
    }
    if !evidence.confirmedSessions.isEmpty {
      visibility = .authoritative
      visibilityGraceDeadline = nil
      recreationGraceConsumed = false
      unavailableSince = nil
      return .authoritative
    }
    if visibility == .authoritative,
      !evidence.huddleWindowPresent,
      !latch.activeAnchors.isEmpty,
      !recreationGraceConsumed
    {
      // Slack briefly recreates the huddle window when the huddle moves
      // between windows or spaces. The grace covers that short window, it is
      // not a licence to keep reporting a huddle for half a minute.
      visibility = .recreationGrace
      visibilityGraceDeadline = now.advanced(by: .seconds(5))
    }
    if let deadline = visibilityGraceDeadline, now >= deadline {
      switch visibility {
      case .transitionGrace:
        visibility = .unavailable
        unavailableSince = now
      case .recreationGrace:
        visibility = .authoritative
        recreationGraceConsumed = true
      case .authoritative, .unavailable:
        break
      }
      visibilityGraceDeadline = nil
    }
    if visibility == .unavailable {
      if evidence.scanCompleted,
        evidence.contentReadable,
        !evidence.huddleWindowPresent
      {
        // The huddle window is gone and the scan was complete, so the huddle
        // ended. The degraded state is recoverable.
        visibility = .authoritative
        visibilityGraceDeadline = nil
        unavailableSince = nil
      } else if let since = unavailableSince,
        now >= since.advanced(by: .seconds(45))
      {
        // Backstop: a degraded visibility must never stick forever.
        visibility = .authoritative
        visibilityGraceDeadline = nil
        unavailableSince = nil
      }
    }
    return visibility
  }

  private func publish(_ observation: SourceObservation, health: DetectorHealth) {
    self.health = health
    guard currentObservation != observation else {
      return
    }
    currentObservation = observation
    continuation.yield(observation)
  }

  private static func gather(
    apps: [RunningApp],
    permissionProbe: any PermissionProbe,
    elementTree: any AXElementTree,
    monotonic: any Monotonic
  ) async -> SlackSample {
    guard permissionProbe.isTrusted else {
      return SlackSample(
        evidence: .init(
          slackRunning: !apps.isEmpty,
          scanCompleted: false,
          huddleWindowPresent: false,
          confirmedSessions: []
        ),
        health: .permissionDenied
      )
    }
    guard !apps.isEmpty else {
      return SlackSample(
        evidence: .init(
          slackRunning: false,
          scanCompleted: true,
          huddleWindowPresent: false,
          confirmedSessions: []
        ),
        health: .absent
      )
    }

    var scanCompleted = true
    var huddleWindowPresent = false
    var elementCount = 0
    var confirmedSessions = Set<SlackHuddleLatch.Anchor>()
    var contentReadable = true
    var health: DetectorHealth = .ok
    for app in apps {
      do {
        let snapshot = try await withDeadline(snapshotDeadline) {
          try await elementTree.snapshot(
            pid: app.processIdentifier,
            maxDepth: 20,
            maxElements: 6_000
          )
        }
        scanCompleted = scanCompleted && snapshot.scanCompleted
        let analysis = SlackSelectors.analyze(
          in: snapshot,
          confirmedAt: monotonic.now()
        )
        huddleWindowPresent =
          huddleWindowPresent || !analysis.huddleWindows.isEmpty
        confirmedSessions.formUnion(analysis.activeAnchors)
        contentReadable = contentReadable && snapshot.contentReadable
        elementCount += snapshot.elementCount
        if !snapshot.scanCompleted {
          health = .degraded(DiagnosticCode(rawValue: "SLACK_SCAN_INCOMPLETE"))
        } else if !snapshot.contentReadable {
          // The application exposed neither a window nor a web area. The tree
          // collapsed, so the absence of a huddle window proves nothing.
          health = .degraded(DiagnosticCode(rawValue: "SLACK_AX_DEGENERATE"))
        }
      } catch let error as AXSnapshotError {
        scanCompleted = false
        health = .degraded(DiagnosticCode(rawValue: slackDiagnostic(for: error)))
      } catch {
        scanCompleted = false
        health = .degraded(DiagnosticCode(rawValue: "SLACK_TREE_UNREADABLE"))
      }
    }

    return SlackSample(
      evidence: .init(
        slackRunning: true,
        scanCompleted: scanCompleted,
        huddleWindowPresent: huddleWindowPresent,
        confirmedSessions: confirmedSessions,
        contentReadable: contentReadable,
        elementCount: elementCount
      ),
      health: health
    )
  }
}

private struct MeetSample: Sendable {
  let evidence: MeetLatch.Evidence
  let health: DetectorHealth
  let permissionDenied: Bool
}

private struct SlackSample: Sendable {
  let evidence: SlackHuddleLatch.Evidence
  let health: DetectorHealth
}

private func meetDiagnostic(for error: AXSnapshotError) -> String {
  switch error {
  case .permissionDenied:
    "MEET_AX_DENIED"
  case .treeTooLarge:
    "MEET_TREE_TOO_LARGE"
  case .timedOut:
    "MEET_AX_TIMEOUT"
  case .unreadable:
    "MEET_TREE_UNREADABLE"
  }
}

private func slackDiagnostic(for error: AXSnapshotError) -> String {
  switch error {
  case .permissionDenied:
    "SLACK_AX_DENIED"
  case .treeTooLarge:
    "SLACK_TREE_TOO_LARGE"
  case .timedOut:
    "SLACK_AX_TIMEOUT"
  case .unreadable:
    "SLACK_TREE_UNREADABLE"
  }
}
