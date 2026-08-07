import MPCore

public enum ChromeFamily {
  public static let bundleIDs = ["com.google.Chrome"]
}

public enum SlackFamily {
  public static let bundleIDs = ["com.tinyspeck.slackmacgap"]
}

public enum MeetSelectors {
  public static func isMeetWebArea(_ node: AXNode) -> Bool {
    node.role == "AXWebArea"
      && node.roleDescription == "HTML content"
      && node.title?.hasPrefix("Meet -") == true
  }

  public static func hasCallControls(_ node: AXNode) -> Bool {
    let descendants = node.descendants
    let hasRegion = descendants.contains {
      $0.role == "AXGroup"
        && $0.subrole == "AXLandmarkRegion"
        && $0.roleDescription == "region"
        && $0.description == "Call controls"
    }
    let controls = Set(
      descendants.compactMap { child -> String? in
        guard child.role == "AXButton", child.roleDescription == "button" else {
          return nil
        }
        return child.description
      }
    )
    return hasRegion && controls.isSuperset(of: ["Leave call", "Share screen"])
  }

  public static func tabEntries(in snapshot: AXSnapshot) -> [AXNode] {
    snapshot.root.descendants.filter {
      $0.role == "AXRadioButton"
        && $0.subrole == "AXTabButton"
        && $0.description?.hasPrefix("Meet -") == true
    }
  }

  public static func strongAnchors(
    in snapshot: AXSnapshot,
    confirmedAt: ContinuousClock.Instant
  ) -> Set<MeetLatch.Anchor> {
    let tabs = tabEntries(in: snapshot)
    return Set(
      snapshot.root.descendants.compactMap { webArea in
        guard isMeetWebArea(webArea), hasCallControls(webArea), let windowID = webArea.windowID,
          let title = webArea.title
        else {
          return nil
        }
        guard
          let tab = tabs.first(where: {
            $0.windowID == windowID && $0.description?.hasPrefix(title) == true
          }), let tabDescription = tab.description
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
        guard let description = tab.description, let windowID = tab.windowID else {
          return nil
        }
        return "\(windowID):\(CrockfordBase32.sha256Hex(description))"
      }
    )
    let liveWindowIDs = Set(
      snapshot.root.descendants.compactMap { node in
        node.role == "AXWindow" ? node.windowID : nil
      }
    )
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
    snapshot.root.descendants.filter {
      $0.role == "AXWindow"
        && $0.subrole == "AXStandardWindow"
        && $0.title?.hasPrefix("Huddle:") == true
    }
  }

  public static func hasHuddleControls(_ window: AXNode) -> Bool {
    let descendants = window.descendants
    let hasToolbar = descendants.contains {
      $0.role == "AXToolbar"
        && ($0.description == "Huddle window actions" || $0.description == "Huddles actions")
    }
    let hasLeave = descendants.contains {
      $0.role == "AXButton"
        && $0.roleDescription == "button"
        && $0.description?.caseInsensitiveCompare("Leave Huddle") == .orderedSame
    }
    return hasToolbar && hasLeave
  }

  public static func hasActiveHuddle(in snapshot: AXSnapshot) -> Bool {
    huddleWindows(in: snapshot).contains(where: hasHuddleControls)
  }
}
