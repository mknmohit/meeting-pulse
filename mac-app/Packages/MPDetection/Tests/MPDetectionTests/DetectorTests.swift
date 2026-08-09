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

private func meetSnapshot(active: Bool) -> AXSnapshot {
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
  return AXSnapshot(
    capturedAt: Date(),
    processIdentifier: 42,
    scanCompleted: true,
    root: node(
      role: "AXApplication",
      children: [node(role: "AXWindow", windowID: 7, children: [webArea, tab])]
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
