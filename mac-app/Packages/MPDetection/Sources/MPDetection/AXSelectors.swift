import CoreGraphics
import MPCore

public enum ChromeFamily {
  public static let bundleIDs = ["com.google.Chrome"]
}

public enum SlackFamily {
  public static let bundleIDs = ["com.tinyspeck.slackmacgap"]
}

private func normalizedAXText(_ value: String?) -> String {
  value?
    .split(whereSeparator: { $0.isWhitespace })
    .joined(separator: " ")
    .lowercased() ?? ""
}

private func matchesAXText(_ value: String?, _ candidates: Set<String>) -> Bool {
  candidates.contains(normalizedAXText(value))
}

private enum AXLabels {
  static let callControls: Set<String> = ["call controls"]
  static let leaveCall: Set<String> = ["leave call"]
  static let presentationControls: Set<String> = [
    "share screen",
    "share your screen",
    "present now",
    "stop presenting",
  ]
  static let presentingSuffix = " is presenting"
  static let huddleActions: Set<String> = ["huddle window actions", "huddles actions"]
  static let leaveHuddle: Set<String> = ["leave huddle"]
}

private func tabLabel(_ node: AXNode) -> String? {
  if let description = node.description, !description.isEmpty {
    return description
  }
  return node.title
}

private func isPresentationControl(_ value: String?) -> Bool {
  let normalized = normalizedAXText(value)
  guard !normalized.isEmpty else {
    return false
  }
  return AXLabels.presentationControls.contains(normalized)
    || normalized.hasSuffix(AXLabels.presentingSuffix)
}

private func isMeetTabLabel(_ normalized: String) -> Bool {
  normalized == "meet"
    || normalized.hasPrefix("meet -")
    || normalized.hasPrefix("meet:")
}

private func callControlsPresent(in node: AXNode) -> Bool {
  var hasRegion = false
  var hasLeave = false
  var hasPresentationControl = false
  var stack = Array(node.children.reversed())

  while let child = stack.popLast() {
    if child.role == "AXGroup"
      && child.subrole == "AXLandmarkRegion"
      && normalizedAXText(child.roleDescription) == "region"
      && matchesAXText(child.description, AXLabels.callControls)
    {
      hasRegion = true
    }
    if child.role == "AXButton"
      && normalizedAXText(child.roleDescription) == "button"
    {
      if matchesAXText(child.description, AXLabels.leaveCall) {
        hasLeave = true
      }
      if isPresentationControl(child.description) {
        hasPresentationControl = true
      }
    }
    if hasRegion && hasLeave && hasPresentationControl {
      return true
    }
    if !child.children.isEmpty {
      stack.append(contentsOf: child.children.reversed())
    }
  }
  return false
}

private func huddleControlsPresent(in window: AXNode) -> Bool {
  var hasToolbar = false
  var hasLeave = false
  var stack = Array(window.children.reversed())

  while let child = stack.popLast() {
    if child.role == "AXToolbar"
      && matchesAXText(child.description, AXLabels.huddleActions)
    {
      hasToolbar = true
    }
    if child.role == "AXButton"
      && normalizedAXText(child.roleDescription) == "button"
      && matchesAXText(child.description, AXLabels.leaveHuddle)
    {
      hasLeave = true
    }
    if hasToolbar && hasLeave {
      return true
    }
    if !child.children.isEmpty {
      stack.append(contentsOf: child.children.reversed())
    }
  }
  return false
}

struct MeetSelectorAnalysis {
  let confirmedSessions: Set<MeetLatch.Anchor>
  let liveAnchors: Set<MeetLatch.Anchor>
}

private struct MeetTab {
  let normalizedLabel: String
  let identity: String
}

public enum MeetSelectors {
  public static func isMeetWebArea(_ node: AXNode) -> Bool {
    guard
      node.role == "AXWebArea"
        && normalizedAXText(node.roleDescription) == "html content"
    else {
      return false
    }
    let title = normalizedAXText(node.title)
    return title == "meet" || title.hasPrefix("meet -") || title.hasPrefix("meet:")
  }

  public static func hasCallControls(_ node: AXNode) -> Bool {
    callControlsPresent(in: node)
  }

  public static func tabEntries(in snapshot: AXSnapshot) -> [AXNode] {
    var entries: [AXNode] = []
    snapshot.root.forEachDescendant { node in
      guard node.role == "AXRadioButton", node.subrole == "AXTabButton" else {
        return
      }
      if isMeetTabLabel(normalizedAXText(tabLabel(node))) {
        entries.append(node)
      }
    }
    return entries
  }

  static func analyze(
    in snapshot: AXSnapshot,
    anchors: Set<MeetLatch.Anchor>,
    confirmedAt: ContinuousClock.Instant
  ) -> MeetSelectorAnalysis {
    var tabsByWindow = [CGWindowID: [MeetTab]]()
    var liveWindowIDs = Set<CGWindowID>()
    var webAreas: [AXNode] = []

    snapshot.root.forEachDescendant { node in
      if node.role == "AXWindow", let windowID = node.windowID {
        liveWindowIDs.insert(windowID)
      }
      if node.role == "AXRadioButton",
        node.subrole == "AXTabButton",
        let windowID = node.windowID,
        let label = tabLabel(node)
      {
        let normalizedLabel = normalizedAXText(label)
        if isMeetTabLabel(normalizedLabel) {
          tabsByWindow[windowID, default: []].append(
            MeetTab(
              normalizedLabel: normalizedLabel,
              identity: CrockfordBase32.sha256Hex(label)
            )
          )
        }
      }
      if isMeetWebArea(node) && callControlsPresent(in: node) {
        webAreas.append(node)
      }
    }

    var confirmedSessions = Set<MeetLatch.Anchor>()
    for webArea in webAreas {
      guard
        let windowID = webArea.windowID,
        let title = webArea.title
      else {
        continue
      }
      let normalizedTitle = normalizedAXText(title)
      guard
        let tab = tabsByWindow[windowID]?.first(where: {
          $0.normalizedLabel.hasPrefix(normalizedTitle)
        })
      else {
        continue
      }
      confirmedSessions.insert(
        MeetLatch.Anchor(
          windowID: windowID,
          tabIdentity: tab.identity,
          confirmedAt: confirmedAt
        )
      )
    }

    let liveAnchors = Set(
      anchors.filter { anchor in
        guard liveWindowIDs.contains(anchor.windowID) else {
          return false
        }
        return tabsByWindow[anchor.windowID]?.contains {
          $0.identity == anchor.tabIdentity
        } == true
      }
    )
    return MeetSelectorAnalysis(
      confirmedSessions: confirmedSessions,
      liveAnchors: liveAnchors
    )
  }

  public static func strongAnchors(
    in snapshot: AXSnapshot,
    confirmedAt: ContinuousClock.Instant
  ) -> Set<MeetLatch.Anchor> {
    analyze(
      in: snapshot,
      anchors: Set<MeetLatch.Anchor>(),
      confirmedAt: confirmedAt
    ).confirmedSessions
  }

  public static func liveAnchors(
    in snapshot: AXSnapshot,
    anchors: Set<MeetLatch.Anchor>
  ) -> Set<MeetLatch.Anchor> {
    let tabs = tabEntries(in: snapshot)
    let liveTabIdentities: Set<String> = Set(
      tabs.compactMap { tab in
        guard let description = tabLabel(tab), let windowID = tab.windowID else {
          return nil
        }
        return "\(windowID):\(CrockfordBase32.sha256Hex(description))"
      }
    )
    var liveWindowIDs = Set<CGWindowID>()
    snapshot.root.forEachDescendant { node in
      if node.role == "AXWindow", let windowID = node.windowID {
        liveWindowIDs.insert(windowID)
      }
    }
    return Set(
      anchors.filter {
        liveWindowIDs.contains($0.windowID)
          && liveTabIdentities.contains("\($0.windowID):\($0.tabIdentity)")
      }
    )
  }
}

struct SlackSelectorAnalysis {
  let huddleWindows: [AXNode]
  let hasActiveHuddle: Bool
  let activeAnchors: Set<SlackHuddleLatch.Anchor>
}

public enum SlackSelectors {
  static func analyze(
    in snapshot: AXSnapshot,
    confirmedAt: ContinuousClock.Instant
  ) -> SlackSelectorAnalysis {
    var standardWindows: [AXNode] = []
    snapshot.root.forEachDescendant { node in
      if node.role == "AXWindow", node.subrole == "AXStandardWindow" {
        standardWindows.append(node)
      }
    }

    var huddleWindows: [AXNode] = []
    var activeAnchors = Set<SlackHuddleLatch.Anchor>()
    var hasActiveHuddle = false
    for window in standardWindows {
      let hasControls = huddleControlsPresent(in: window)
      if normalizedAXText(window.title).hasPrefix("huddle:") || hasControls {
        huddleWindows.append(window)
      }
      if hasControls {
        hasActiveHuddle = true
        if let windowID = window.windowID {
          activeAnchors.insert(
            SlackHuddleLatch.Anchor(
              processIdentifier: snapshot.processIdentifier,
              windowID: windowID,
              confirmedAt: confirmedAt
            )
          )
        }
      }
    }
    return SlackSelectorAnalysis(
      huddleWindows: huddleWindows,
      hasActiveHuddle: hasActiveHuddle,
      activeAnchors: activeAnchors
    )
  }

  public static func huddleWindows(in snapshot: AXSnapshot) -> [AXNode] {
    analyze(in: snapshot, confirmedAt: ContinuousClock().now).huddleWindows
  }

  public static func hasHuddleControls(_ window: AXNode) -> Bool {
    huddleControlsPresent(in: window)
  }

  public static func hasActiveHuddle(in snapshot: AXSnapshot) -> Bool {
    analyze(in: snapshot, confirmedAt: ContinuousClock().now).hasActiveHuddle
  }

  public static func activeAnchors(
    in snapshot: AXSnapshot,
    confirmedAt: ContinuousClock.Instant
  ) -> Set<SlackHuddleLatch.Anchor> {
    analyze(in: snapshot, confirmedAt: confirmedAt).activeAnchors
  }
}
