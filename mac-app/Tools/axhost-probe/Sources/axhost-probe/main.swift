import Foundation
import MPDetection

@main
private struct AXHostProbe {
  static func main() async {
    let discovery = WorkspaceAppDiscovery()
    guard let app = discovery.runningApps(bundleIDs: SlackFamily.bundleIDs).first else {
      print("SLACK_ABSENT")
      return
    }

    let host = AXRunLoopHost()
    do {
      let snapshot = try await host.snapshot(
        pid: app.processIdentifier,
        maxDepth: 20,
        maxElements: 5_000
      )
      print(
        "SNAPSHOT scanCompleted=\(snapshot.scanCompleted) rootChildren=\(snapshot.root.childCount)")

      try await host.observe(
        pid: app.processIdentifier,
        notifications: [
          "AXFocusedWindowChanged",
          "AXWindowCreated",
          "AXUIElementDestroyed",
        ]
      )
      let eventTask = Task {
        for await event in host.events {
          print("EVENT pid=\(event.processIdentifier) notification=\(event.notification)")
          break
        }
      }
      try await Task.sleep(for: .seconds(15))
      eventTask.cancel()
      await host.stopObserving(pid: app.processIdentifier)
      print("OBSERVER_COMPLETE")
    } catch {
      print("PROBE_ERROR \(error)")
    }
  }
}
