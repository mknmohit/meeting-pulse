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
  static let shareScreen: Set<String> = ["share screen"]
  static let huddleActions: Set<String> = ["huddle window actions", "huddles actions"]
  static let leaveHuddle: Set<String> = ["leave huddle"]
}

private func tabLabel(_ node: AXNode) -> String? {
  if let description = node.description, !description.isEmpty {
    return description
  }
  return node.title
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
    var hasRegion = false
    var hasLeave = false
    var hasShare = false
    node.forEachDescendant { child in
      if child.role == "AXGroup"
        && child.subrole == "AXLandmarkRegion"
        && normalizedAXText(child.roleDescription) == "region"
        && matchesAXText(child.description, AXLabels.callControls)
      {
        hasRegion = true
      }
      guard
        child.role == "AXButton"
          && normalizedAXText(child.roleDescription) == "button"
      else {
        return
      }
      if matchesAXText(child.description, AXLabels.leaveCall) {
        hasLeave = true
      }
      if matchesAXText(child.description, AXLabels.shareScreen) {
        hasShare = true
      }
    }
    return hasRegion && hasLeave && hasShare
  }

  public static func tabEntries(in snapshot: AXSnapshot) -> [AXNode] {
    var entries: [AXNode] = []
    snapshot.root.forEachDescendant { node in
      guard node.role == "AXRadioButton", node.subrole == "AXTabButton" else {
        return
      }
      let label = normalizedAXText(tabLabel(node))
      if label == "meet" || label.hasPrefix("meet -") || label.hasPrefix("meet:") {
        entries.append(node)
      }
    }
    return entries
  }

  public static func strongAnchors(
    in snapshot: AXSnapshot,
    confirmedAt: ContinuousClock.Instant
  ) -> Set<MeetLatch.Anchor> {
    let tabs = tabEntries(in: snapshot)
    var webAreas: [AXNode] = []
    snapshot.root.forEachDescendant { node in
      if isMeetWebArea(node) && hasCallControls(node) {
        webAreas.append(node)
      }
    }
    return Set(
      webAreas.compactMap { webArea in
        guard let windowID = webArea.windowID, let title = webArea.title else {
          return nil
        }
        let normalizedTitle = normalizedAXText(title)
        guard
          let tab = tabs.first(where: {
            $0.windowID == windowID
              && normalizedAXText(tabLabel($0)).hasPrefix(normalizedTitle)
          }), let tabDescription = tabLabel(tab)
        else {
          return nil
        }
        return MeetLatch.Anchor(
          windowID: windowID,
          tabIdentity: CrockfordBase32.sha256Hex(tabDescription),
          confirmedAt: confirmedAt
        )
      }
    )
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

public enum SlackSelectors {
  public static func huddleWindows(in snapshot: AXSnapshot) -> [AXNode] {
    var windows: [AXNode] = []
    snapshot.root.forEachDescendant { node in
      guard node.role == "AXWindow", node.subrole == "AXStandardWindow" else {
        return
      }
      if normalizedAXText(node.title).hasPrefix("huddle:") {
        windows.append(node)
      }
    }
    return windows
  }

  public static func hasHuddleControls(_ window: AXNode) -> Bool {
    var hasToolbar = false
    var hasLeave = false
    window.forEachDescendant { child in
      if child.role == "AXToolbar"
        && matchesAXText(
          child.description,
          AXLabels.huddleActions
        )
      {
        hasToolbar = true
      }
      if child.role == "AXButton"
        && normalizedAXText(child.roleDescription) == "button"
        && matchesAXText(child.description, AXLabels.leaveHuddle)
      {
        hasLeave = true
      }
    }
    return hasToolbar && hasLeave
  }

  public static func hasActiveHuddle(in snapshot: AXSnapshot) -> Bool {
    huddleWindows(in: snapshot).contains(where: hasHuddleControls)
  }
}
