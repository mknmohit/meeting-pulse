import Foundation
import MPDetection

@main
private struct ChromeWindowIDProbe {
  static func main() async {
    let discovery = WorkspaceAppDiscovery()
    let apps = discovery.runningApps(bundleIDs: ChromeFamily.bundleIDs)
    guard !apps.isEmpty else {
      print("CHROME_ABSENT")
      return
    }

    let host = AXRunLoopHost()
    for app in apps {
      do {
        let snapshot = try await host.snapshot(
          pid: app.processIdentifier,
          maxDepth: 20,
          maxElements: 5_000
        )
        print("=== pid=\(app.processIdentifier) scanCompleted=\(snapshot.scanCompleted) ===")
        let rootChildCount = snapshot.root.childCount
        let rootChildren = snapshot.root.children.count
        print(
          "ROOT role=\(snapshot.root.role ?? "nil") rd=\(snapshot.root.roleDescription ?? "nil") title=\(snapshot.root.title ?? "nil") childCount=\(rootChildCount) childrenCount=\(rootChildren)"
        )
        for (i, c) in snapshot.root.children.enumerated() {
          print(
            "  child[\(i)] role=\(c.role ?? "nil") rd=\(c.roleDescription ?? "nil") title=\(String((c.title ?? "").prefix(40))) childCount=\(c.childCount)"
          )
        }

        // Recursive raw dump, bounded.
        printRaw(snapshot.root.children, depth: 0, max: 8)

        // Walk the tree, print windowID + matching roles.
        var meetWebareas = 0
        var meetTabs = 0
        var callControls = 0
        var leaveButtons = 0
        var shareButtons = 0
        var withWindowIDWeb = 0
        var withWindowIDTab = 0
        walk(snapshot.root, "", &meetWebareas, &meetTabs, &callControls, &leaveButtons, &shareButtons, &withWindowIDWeb, &withWindowIDTab)

        print("SUMMARY pid=\(app.processIdentifier):")
        print("  meet webareas=\(meetWebareas) withWindowID=\(withWindowIDWeb)")
        print("  meet tabs=\(meetTabs) withWindowID=\(withWindowIDTab)")
        print("  callControls groups=\(callControls)")
        print("  leave-call buttons=\(leaveButtons)")
        print("  share-screen buttons=\(shareButtons)")
      } catch {
        print("PROBE_ERROR pid=\(app.processIdentifier): \(error)")
      }
    }
  }

  private static func printRaw(_ nodes: [AXNode], depth: Int, max: Int) {
    if depth >= max { return }
    for (i, n) in nodes.enumerated() {
      let indent = String(repeating: "  ", count: depth + 1)
      print(
        "\(indent)[\(i)] role=\(n.role ?? "-") rd=\(n.roleDescription ?? "-") title=\(String((n.title ?? "").prefix(40))) desc=\(String((n.description ?? "").prefix(40))) windowID=\(String(describing: n.windowID)) cc=\(n.childCount)"
      )
      printRaw(n.children, depth: depth + 1, max: max)
    }
  }

  private static func walk(
    _ node: AXNode,
    _ path: String,
    _ meetWebareas: inout Int,
    _ meetTabs: inout Int,
    _ callControls: inout Int,
    _ leaveButtons: inout Int,
    _ shareButtons: inout Int,
    _ withWindowIDWeb: inout Int,
    _ withWindowIDTab: inout Int
  ) {
    let role = node.role ?? ""
    let sub = node.subrole ?? ""
    let rd = node.roleDescription ?? ""
    let title = node.title ?? ""
    let desc = node.description ?? ""

    if role == "AXWebArea" && rd == "HTML content" && title.hasPrefix("Meet -") {
      meetWebareas += 1
      if node.windowID != nil { withWindowIDWeb += 1 }
      print(
        "  WEBAREA path=\(path) title=\(String(title.prefix(60))) windowID=\(String(describing: node.windowID))"
      )
    }
    if role == "AXRadioButton" && sub == "AXTabButton" && desc.hasPrefix("Meet -") {
      meetTabs += 1
      if node.windowID != nil { withWindowIDTab += 1 }
      print(
        "  TAB path=\(path) desc=\(String(desc.prefix(60))) windowID=\(String(describing: node.windowID))"
      )
    }
    if role == "AXGroup" && sub == "AXLandmarkRegion" && rd == "region" && desc == "Call controls" {
      callControls += 1
    }
    if role == "AXButton" && rd == "button" && desc == "Leave call" {
      leaveButtons += 1
    }
    if role == "AXButton" && rd == "button" && desc == "Share screen" {
      shareButtons += 1
    }

    for (i, c) in node.children.enumerated() {
      walk(c, "\(path)/\(i)", &meetWebareas, &meetTabs, &callControls, &leaveButtons, &shareButtons, &withWindowIDWeb, &withWindowIDTab)
    }
  }
}
