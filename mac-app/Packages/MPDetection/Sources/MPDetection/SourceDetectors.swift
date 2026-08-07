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
    for pid in observedPIDs {
      await eventSource.stopObserving(pid: pid)
    }
    observedPIDs.removeAll()
  }

  public func invalidate() async {
    samplingTask?.cancel()
    samplingTask = nil
    latch = MeetLatch()
    publish(.unknown, health: .permissionDenied)
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
    let observation = latch.apply(
      sample.evidence,
      now: monotonic.now(),
      maxLatchDuration: .seconds(14_400)
    )
    publish(observation, health: sample.health)
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
          maxElements: 5_000
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
    eventSource: any AXEventSource = AXRunLoopHost.shared
  ) {
    self.appDiscovery = appDiscovery
    self.permissionProbe = permissionProbe
    self.elementTree = elementTree
    self.eventSource = eventSource
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
    for pid in observedPIDs {
      await eventSource.stopObserving(pid: pid)
    }
    observedPIDs.removeAll()
  }

  public func invalidate() async {
    samplingTask?.cancel()
    samplingTask = nil
    publish(.unknown, health: .permissionDenied)
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
        elementTree: elementTree
      )
    }
    samplingTask = task
    let sample = await task.value
    guard requestedGeneration == generation else {
      return
    }
    samplingTask = nil
    publish(sample.observation, health: sample.health)
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
    elementTree: any AXElementTree
  ) async -> SlackSample {
    guard permissionProbe.isTrusted else {
      return SlackSample(
        observation: .unknown,
        health: .permissionDenied
      )
    }
    guard !apps.isEmpty else {
      return SlackSample(
        observation: .sourceAbsent,
        health: .absent
      )
    }

    var sawActive = false
    var scanCompleted = true
    var health: DetectorHealth = .ok
    for app in apps {
      do {
        let snapshot = try await elementTree.snapshot(
          pid: app.processIdentifier,
          maxDepth: 20,
          maxElements: 5_000
        )
        scanCompleted = scanCompleted && snapshot.scanCompleted
        sawActive = sawActive || SlackSelectors.hasActiveHuddle(in: snapshot)
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
      observation: sawActive ? .active : (scanCompleted ? .inactive : .unknown),
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
  let observation: SourceObservation
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
