import CoreGraphics
import Foundation
import MPCore
import Testing

@testable import MPDetection

struct DetectorTests {
  @Test
  func newerMeetSampleWinsOverDelayedOlderSample() async {
    let tree = DelayedTree(snapshots: [
      meetSnapshot(active: true),
      meetSnapshot(active: false),
    ])
    let detector = GoogleMeetDetector(
      appDiscovery: StaticDiscovery(),
      permissionProbe: StaticPermission(),
      elementTree: tree,
      eventSource: EmptyEventSource()
    )

    let first = Task {
      await detector.requestSample()
    }
    try? await Task.sleep(for: .milliseconds(10))
    let second = Task {
      await detector.requestSample()
    }
    await first.value
    await second.value

    #expect(await detector.currentObservation == .inactive)
  }

  @Test
  func permissionRevocationClearsMeetLatch() async {
    let tree = DelayedTree(snapshots: [meetSnapshot(active: true)])
    let detector = GoogleMeetDetector(
      appDiscovery: StaticDiscovery(),
      permissionProbe: StaticPermission(),
      elementTree: tree,
      eventSource: EmptyEventSource()
    )
    await detector.requestSample()
    #expect(await detector.currentObservation == .active)

    await detector.invalidate()

    #expect(await detector.currentObservation == .unknown)
    #expect(await detector.health == .permissionDenied)
  }

  @Test
  func longRunningMeetRemainsActiveWhenTheAnchoredTabIsLive() async {
    let clock = TestMonotonic()
    let detector = GoogleMeetDetector(
      appDiscovery: StaticDiscovery(),
      permissionProbe: StaticPermission(),
      elementTree: DelayedTree(snapshots: [
        meetSnapshot(active: true),
        meetSnapshot(active: false),
      ]),
      eventSource: EmptyEventSource(),
      monotonic: clock
    )

    await detector.requestSample()
    clock.advance(by: .seconds(14_401))
    await detector.requestSample()

    #expect(await detector.currentObservation == .active)
  }

  @Test
  func meetRecoversAfterATemporaryUnavailableSample() async {
    let detector = GoogleMeetDetector(
      appDiscovery: StaticDiscovery(),
      permissionProbe: StaticPermission(),
      elementTree: DelayedTree(snapshots: [
        meetSnapshot(active: true),
        incompleteMeetSnapshot(),
        meetSnapshot(active: true),
      ]),
      eventSource: EmptyEventSource()
    )

    await detector.requestSample()
    #expect(await detector.currentObservation == .active)

    await detector.requestSample()
    #expect(await detector.currentObservation == .unknown)

    await detector.requestSample()
    #expect(await detector.currentObservation == .active)
  }

  @Test
  func spaceChangeKeepsMeetActiveUntilVisibilityGraceExpires() async {
    let clock = TestMonotonic()
    let detector = GoogleMeetDetector(
      appDiscovery: StaticDiscovery(),
      permissionProbe: StaticPermission(),
      elementTree: DelayedTree(snapshots: [
        meetSnapshot(active: true),
        meetSnapshot(active: false),
      ]),
      eventSource: EmptyEventSource(),
      monotonic: clock
    )

    await detector.requestSample()
    #expect(await detector.currentObservation == .active)

    await detector.spaceDidChange()
    await detector.requestSample()
    #expect(await detector.currentObservation == .active)

    clock.advance(by: .seconds(21))
    await detector.requestSample()
    #expect(await detector.currentObservation == .unknown)
  }

  @Test
  func spaceChangeKeepsSlackHuddleActiveUntilVisibilityGraceExpires() async {
    let clock = TestMonotonic()
    let detector = SlackHuddleDetector(
      appDiscovery: StaticDiscovery(),
      permissionProbe: StaticPermission(),
      elementTree: DelayedTree(snapshots: [
        slackSnapshot(active: true),
        slackSnapshot(active: false),
      ]),
      eventSource: EmptyEventSource(),
      monotonic: clock
    )

    await detector.requestSample()
    #expect(await detector.currentObservation == .active)

    await detector.spaceDidChange()
    await detector.requestSample()
    #expect(await detector.currentObservation == .active)

    clock.advance(by: .seconds(21))
    await detector.requestSample()
    #expect(await detector.currentObservation == .active)
  }

  @Test
  func longRunningSlackHuddleRemainsActiveWhenControlsAreTemporarilyMissing() async {
    let clock = TestMonotonic()
    let detector = SlackHuddleDetector(
      appDiscovery: StaticDiscovery(),
      permissionProbe: StaticPermission(),
      elementTree: DelayedTree(snapshots: [
        slackSnapshot(active: true),
        slackSnapshot(windowPresent: true, controlsPresent: false),
      ]),
      eventSource: EmptyEventSource(),
      monotonic: clock
    )

    await detector.requestSample()
    clock.advance(by: .seconds(14_401))
    await detector.requestSample()

    #expect(await detector.currentObservation == .active)
  }

  @Test
  func slackWindowRecreationGraceStillEndsAnActualHuddle() async {
    let clock = TestMonotonic()
    let detector = SlackHuddleDetector(
      appDiscovery: StaticDiscovery(),
      permissionProbe: StaticPermission(),
      elementTree: DelayedTree(snapshots: [
        slackSnapshot(active: true),
        slackSnapshot(active: false),
      ]),
      eventSource: EmptyEventSource(),
      monotonic: clock
    )

    await detector.requestSample()
    await detector.requestSample()
    #expect(await detector.currentObservation == .active)

    clock.advance(by: .seconds(21))
    await detector.requestSample()
    #expect(await detector.currentObservation == .inactive)

    await detector.requestSample()
    #expect(await detector.currentObservation == .inactive)
  }

  @Test
  func embeddedSlackHuddleUpdatesStatusAndEndsAfterControlsDisappear() async {
    let clock = TestMonotonic()
    let detector = SlackHuddleDetector(
      appDiscovery: StaticDiscovery(),
      permissionProbe: StaticPermission(),
      elementTree: DelayedTree(snapshots: [
        slackEmbeddedSnapshot(active: true),
        slackEmbeddedSnapshot(active: false),
      ]),
      eventSource: EmptyEventSource(),
      monotonic: clock
    )

    await detector.requestSample()
    #expect(await detector.currentObservation == .active)

    await detector.requestSample()
    #expect(await detector.currentObservation == .active)

    clock.advance(by: .seconds(21))
    await detector.requestSample()
    #expect(await detector.currentObservation == .inactive)
  }
}

private struct StaticDiscovery: AppDiscovery {
  func runningApps(bundleIDs: [String]) -> [RunningApp] {
    [RunningApp(processIdentifier: 42, bundleIdentifier: bundleIDs[0])]
  }
}

private struct StaticPermission: PermissionProbe {
  var isTrusted = true
}

private struct EmptyEventSource: AXEventSource {
  let events: AsyncStream<AXEvent> = AsyncStream { _ in }

  func observe(pid: pid_t, notifications: [String]) async throws {}
  func stopObserving(pid: pid_t) async {}
}

private final class DelayedTree: AXElementTree, @unchecked Sendable {
  private let lock = NSLock()
  private let snapshots: [AXSnapshot]
  private var nextIndex = 0

  init(snapshots: [AXSnapshot]) {
    self.snapshots = snapshots
  }

  func snapshot(
    pid: pid_t,
    maxDepth: Int,
    maxElements: Int
  ) async throws -> AXSnapshot {
    let index = lock.withLock {
      defer { nextIndex += 1 }
      return nextIndex
    }
    if index == 0 {
      try await Task.sleep(for: .milliseconds(100))
    }
    return snapshots[min(index, snapshots.count - 1)]
  }
}

private final class TestMonotonic: Monotonic, @unchecked Sendable {
  private let lock = NSLock()
  private var instant = ContinuousClock().now

  func now() -> ContinuousClock.Instant {
    lock.withLock { instant }
  }

  func sleep(until: ContinuousClock.Instant) async throws {}

  func advance(by duration: Duration) {
    lock.withLock {
      instant = instant.advanced(by: duration)
    }
  }
}

private func meetSnapshot(
  active: Bool,
  includeTab: Bool = true,
  scanCompleted: Bool = true
) -> AXSnapshot {
  let controls: [AXNode] =
    active
    ? [
      node(
        role: "AXGroup", subrole: "AXLandmarkRegion", roleDescription: "region",
        description: "Call controls"),
      node(role: "AXButton", roleDescription: "button", description: "Leave call"),
      node(role: "AXButton", roleDescription: "button", description: "Share screen"),
    ]
    : []
  let webArea = node(
    role: "AXWebArea",
    roleDescription: "HTML content",
    title: "Meet - test",
    windowID: 7,
    children: controls
  )
  let tab = node(
    role: "AXRadioButton",
    subrole: "AXTabButton",
    roleDescription: "radio button",
    description: "Meet - test tab",
    windowID: 7
  )
  let tabs = includeTab ? [tab] : []
  return AXSnapshot(
    capturedAt: Date(),
    processIdentifier: 42,
    scanCompleted: scanCompleted,
    root: node(
      role: "AXApplication",
      children: [
        node(role: "AXWindow", windowID: 7, children: [webArea] + tabs)
      ]
    )
  )
}

private func incompleteMeetSnapshot() -> AXSnapshot {
  AXSnapshot(
    capturedAt: Date(),
    processIdentifier: 42,
    scanCompleted: false,
    root: node(role: "AXApplication")
  )
}

private func slackSnapshot(active: Bool) -> AXSnapshot {
  slackSnapshot(windowPresent: active, controlsPresent: active)
}

private func slackSnapshot(
  windowPresent: Bool,
  controlsPresent: Bool
) -> AXSnapshot {
  let huddleChildren: [AXNode] =
    windowPresent
    ? [
      node(role: "AXWebArea", title: "Huddle: test", windowID: 8),
    ] + (controlsPresent
      ? [
        node(role: "AXToolbar", description: "Huddle window actions"),
        node(role: "AXButton", roleDescription: "button", description: "Leave Huddle"),
      ]
      : [])
    : []
  let windows: [AXNode] =
    windowPresent
    ? [
      node(
        role: "AXWindow",
        subrole: "AXStandardWindow",
        title: "Huddle: test",
        windowID: 8,
        children: huddleChildren
      )
    ]
    : []
  return AXSnapshot(
    capturedAt: Date(),
    processIdentifier: 42,
    scanCompleted: true,
    root: node(role: "AXApplication", children: windows)
  )
}

private func slackEmbeddedSnapshot(active: Bool) -> AXSnapshot {
  let children: [AXNode] =
    active
    ? [
      node(role: "AXToolbar", description: "Huddles actions"),
      node(role: "AXButton", roleDescription: "button", description: "Leave Huddle"),
    ]
    : [
      node(role: "AXRow", subrole: "AXOutlineRow", description: "Huddles"),
      node(role: "AXButton", description: "Start huddle with <contact>"),
    ]
  return AXSnapshot(
    capturedAt: Date(),
    processIdentifier: 42,
    scanCompleted: true,
    root: node(
      role: "AXApplication",
      children: [
        node(
          role: "AXWindow",
          subrole: "AXStandardWindow",
          title: "test-channel - Slack",
          windowID: 9,
          children: children
        )
      ]
    )
  )
}

private func node(
  role: String? = nil,
  subrole: String? = nil,
  roleDescription: String? = nil,
  title: String? = nil,
  description: String? = nil,
  windowID: CGWindowID? = nil,
  children: [AXNode] = []
) -> AXNode {
  AXNode(
    role: role,
    subrole: subrole,
    roleDescription: roleDescription,
    identifier: nil,
    title: title,
    description: description,
    value: nil,
    help: nil,
    enabled: true,
    focused: false,
    childCount: children.count,
    windowID: windowID,
    children: children
  )
}
