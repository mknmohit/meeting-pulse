import ApplicationServices
import MPCore

private let detectorNotifications = [
  kAXFocusedWindowChangedNotification as String,
  kAXWindowCreatedNotification as String,
  kAXUIElementDestroyedNotification as String,
]

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
    publish(.unknown, health: .permissionDenied)
  }

  public func spaceDidChange() async {
    guard currentObservation == .active || !latch.activeAnchors.isEmpty else {
      return
    }
    visibility = .transitionGrace
    visibilityGraceDeadline = monotonic.now().advanced(by: .seconds(20))
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
      visibility: visibility
    )
    let observation = latch.apply(
      evidence,
      now: now,
      maxLatchDuration: .seconds(14_400)
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
      return .authoritative
    }
    if !evidence.confirmedSessions.isEmpty {
      visibility = .authoritative
      visibilityGraceDeadline = nil
      return .authoritative
    }
    if visibility == .transitionGrace,
      let deadline = visibilityGraceDeadline,
      now >= deadline
    {
      visibility = .unavailable
      visibilityGraceDeadline = nil
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
    var health: DetectorHealth = .ok

    for app in apps {
      do {
        let snapshot = try await elementTree.snapshot(
          pid: app.processIdentifier,
          maxDepth: 20,
          maxElements: 3_000
        )
        scanCompleted = scanCompleted && snapshot.scanCompleted
        confirmedSessions.formUnion(
          MeetSelectors.strongAnchors(
            in: snapshot,
            confirmedAt: monotonic.now()
          )
        )
        liveAnchors.formUnion(
          MeetSelectors.liveAnchors(
            in: snapshot,
            anchors: existingAnchors
          )
        )
        if !snapshot.scanCompleted {
          health = .degraded(DiagnosticCode(rawValue: "MEET_SCAN_INCOMPLETE"))
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
        liveAnchors: liveAnchors
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
    publish(.unknown, health: .permissionDenied)
  }

  public func spaceDidChange() async {
    guard currentObservation == .active || !latch.activeAnchors.isEmpty else {
      return
    }
    visibility = .transitionGrace
    visibilityGraceDeadline = monotonic.now().advanced(by: .seconds(20))
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
      visibility: visibility
    )
    publish(
      latch.apply(
        evidence,
        now: now,
        maxLatchDuration: .seconds(14_400)
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
      return .authoritative
    }
    if !evidence.confirmedSessions.isEmpty {
      visibility = .authoritative
      visibilityGraceDeadline = nil
      return .authoritative
    }
    if visibility == .authoritative,
      !evidence.huddleWindowPresent,
      !latch.activeAnchors.isEmpty
    {
      visibility = .recreationGrace
      visibilityGraceDeadline = now.advanced(by: .seconds(20))
    }
    if let deadline = visibilityGraceDeadline, now >= deadline {
      switch visibility {
      case .transitionGrace:
        visibility = .unavailable
      case .recreationGrace:
        visibility = .authoritative
      case .authoritative, .unavailable:
        break
      }
      visibilityGraceDeadline = nil
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
    var confirmedSessions = Set<SlackHuddleLatch.Anchor>()
    var health: DetectorHealth = .ok
    for app in apps {
      do {
        let snapshot = try await elementTree.snapshot(
          pid: app.processIdentifier,
          maxDepth: 20,
          maxElements: 3_000
        )
        scanCompleted = scanCompleted && snapshot.scanCompleted
        huddleWindowPresent =
          huddleWindowPresent || !SlackSelectors.huddleWindows(in: snapshot).isEmpty
        confirmedSessions.formUnion(
          SlackSelectors.activeAnchors(
            in: snapshot,
            confirmedAt: monotonic.now()
          )
        )
        if !snapshot.scanCompleted {
          health = .degraded(DiagnosticCode(rawValue: "SLACK_SCAN_INCOMPLETE"))
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
        confirmedSessions: confirmedSessions
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
  case .unreadable:
    "SLACK_TREE_UNREADABLE"
  }
}
