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

/// Matches a label exposed either as the accessibility description or as the
/// accessibility title. Chrome and Electron move labels between the two
/// attributes between releases, so both are consulted.
private func matchesAXLabel(_ node: AXNode, _ candidates: Set<String>) -> Bool {
  matchesAXText(node.description, candidates) || matchesAXText(node.title, candidates)
}

/// Buttons are the only role that carries Meet and Slack call controls. The
/// role description is optional because some releases omit it.
private func isButton(_ node: AXNode) -> Bool {
  guard node.role == "AXButton" else {
    return false
  }
  let roleDescription = normalizedAXText(node.roleDescription)
  return roleDescription.isEmpty || roleDescription == "button"
}

private enum AXLabels {
  /// The landmark region Meet renders around the in-call control bar.
  static let callControls: Set<String> = [
    "call controls",
    "call control",
    "meeting controls",
  ]
  /// The hang-up control. Google describes the button as `Leave call` and
  /// exposes `Ends the current call` as an alternative accessibility label.
  static let leaveCall: Set<String> = [
    "leave call",
    "leave the call",
    "leave meeting",
    "end call",
    "ends the current call",
  ]
  /// Controls that only exist while a Meet call is running. Any one of them
  /// corroborates the `Leave call` button, so a Meet build that hides the
  /// presentation control is still detected.
  static let inCallControls: Set<String> = [
    "share screen",
    "share your screen",
    "share tab",
    "present now",
    "stop presenting",
    "you are presenting",
    "turn on camera",
    "turn off camera",
    "turn on microphone",
    "turn off microphone",
    "mute",
    "unmute",
    "raise hand",
    "lower hand",
    "more options",
    "more actions",
    "show everyone",
    "participants",
    "people",
    "chat",
    "chat with everyone",
    "captions",
    "turn on captions",
    "turn off captions",
    "record",
    "stop recording",
    "full screen",
    "exit full screen",
    "meeting details",
    "copy meeting details",
    "report a problem",
    "reaction",
    "send a reaction",
  ]
  static let presentingSuffix = " is presenting"
  /// Slack exposes the huddle toolbar under a few different descriptions
  /// depending on the client layout.
  static let huddleActions: Set<String> = [
    "huddle window actions",
    "huddles actions",
    "huddle actions",
    "huddle controls",
    "huddle toolbar",
  ]
  static let leaveHuddle: Set<String> = [
    "leave huddle",
    "leave the huddle",
    "end huddle",
  ]
}

private func tabLabel(_ node: AXNode) -> String? {
  if let description = node.description, !description.isEmpty {
    return description
  }
  return node.title
}

/// A control that only exists inside a running Meet call.
private func isInCallControl(_ value: String?) -> Bool {
  let normalized = normalizedAXText(value)
  guard !normalized.isEmpty else {
    return false
  }
  return AXLabels.inCallControls.contains(normalized)
    || normalized.hasSuffix(AXLabels.presentingSuffix)
}

private func isMeetTabLabel(_ normalized: String) -> Bool {
  normalized == "meet"
    || normalized.hasPrefix("meet -")
    || normalized.hasPrefix("meet:")
}

/// True when the node renders Meet's in-call control bar. The bar always
/// carries the hang-up control plus at least one other call-only control, so
/// a single label never confirms a meeting.
private func callControlsPresent(in node: AXNode) -> Bool {
  var hasLeave = false
  var hasInCallControl = false
  var stack = Array(node.children.reversed())

  while let child = stack.popLast() {
    if isButton(child) {
      if matchesAXLabel(child, AXLabels.leaveCall) {
        hasLeave = true
      }
      if isInCallControl(child.description) || isInCallControl(child.title) {
        hasInCallControl = true
      }
    }
    if child.role == "AXStaticText",
      isInCallControl(child.title) || isInCallControl(child.description)
    {
      hasInCallControl = true
    }
    if hasLeave && hasInCallControl {
      return true
    }
    if !child.children.isEmpty {
      stack.append(contentsOf: child.children.reversed())
    }
  }
  return false
}

/// True when Meet renders the `Call controls` landmark region. The region is a
/// corroborating signal; it is not required for a confirmation.
private func callControlsRegionPresent(in node: AXNode) -> Bool {
  var stack = Array(node.children.reversed())
  while let child = stack.popLast() {
    if (child.role == "AXGroup" || child.role == "AXToolbar"),
      normalizedAXText(child.roleDescription) == "region"
        || normalizedAXText(child.roleDescription) == "toolbar"
        || normalizedAXText(child.roleDescription) == "group",
      matchesAXLabel(child, AXLabels.callControls)
    {
      return true
    }
    if !child.children.isEmpty {
      stack.append(contentsOf: child.children.reversed())
    }
  }
  return false
}

/// Slack titles the detached huddle window `Huddle`, `Huddle: <topic>` or
/// `Huddle - <topic>`. The plural `Huddles` title is the huddle list view and
/// never means an active huddle.
private func isHuddleWindowTitle(_ normalized: String) -> Bool {
  guard !normalized.isEmpty else {
    return false
  }
  if normalized == "huddles" || normalized.hasPrefix("huddles ") {
    return false
  }
  return normalized == "huddle"
    || normalized.hasPrefix("huddle:")
    || normalized.hasPrefix("huddle -")
    || normalized.hasPrefix("huddle with")
    || normalized.hasPrefix("huddle/")
}

/// True when a window exposes the huddle controls. The hang-up control is
/// always required so the huddle list view never reads as an active huddle.
/// The toolbar is required only for windows that are not titled as a huddle.
private func huddleControlsPresent(in window: AXNode) -> Bool {
  var hasToolbar = false
  var hasLeave = false
  let titledAsHuddle = isHuddleWindowTitle(normalizedAXText(window.title))
  var stack = Array(window.children.reversed())

  while let child = stack.popLast() {
    if child.role == "AXToolbar"
      && matchesAXText(child.description, AXLabels.huddleActions)
    {
      hasToolbar = true
    }
    if isButton(child) && matchesAXLabel(child, AXLabels.leaveHuddle) {
      hasLeave = true
    }
    if hasLeave && (hasToolbar || titledAsHuddle) {
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
  /// A Meet page is present and exposes its content. The page being readable
  /// makes the absence of call controls real end evidence.
  let meetSurfaceReadable: Bool
  /// A Meet page or a Meet tab entry exists at all.
  let meetSurfacePresent: Bool
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

  /// True for any rendered web page, independent of the page title.
  private static func isHTMLWebArea(_ node: AXNode) -> Bool {
    node.role == "AXWebArea"
      && normalizedAXText(node.roleDescription) == "html content"
  }

  public static func hasCallControls(_ node: AXNode) -> Bool {
    callControlsPresent(in: node)
  }

  public static func hasCallControlsRegion(_ node: AXNode) -> Bool {
    callControlsRegionPresent(in: node)
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

  /// Identity used when a Meet web area cannot be paired with a tab-strip
  /// entry. It stays local to the Mac and is never published.
  static func webAreaIdentity(title: String) -> String {
    CrockfordBase32.sha256Hex("web-area:" + title)
  }

  static func analyze(
    in snapshot: AXSnapshot,
    anchors: Set<MeetLatch.Anchor>,
    confirmedAt: ContinuousClock.Instant
  ) -> MeetSelectorAnalysis {
    var tabsByWindow = [CGWindowID: [MeetTab]]()
    var liveWindowIDs = Set<CGWindowID>()
    var meetWindowIDs = Set<CGWindowID>()

    // Pass 1: window liveness and the Meet tab strip.
    snapshot.root.forEachDescendant { node in
      if node.role == "AXWindow", let windowID = node.windowID {
        liveWindowIDs.insert(windowID)
      }
      guard
        node.role == "AXRadioButton",
        node.subrole == "AXTabButton",
        let windowID = node.windowID,
        let label = tabLabel(node)
      else {
        return
      }
      let normalizedLabel = normalizedAXText(label)
      guard isMeetTabLabel(normalizedLabel) else {
        return
      }
      tabsByWindow[windowID, default: []].append(
        MeetTab(
          normalizedLabel: normalizedLabel,
          identity: CrockfordBase32.sha256Hex(label)
        )
      )
      meetWindowIDs.insert(windowID)
    }

    // Pass 2: candidate Meet web areas. A web area qualifies when its own
    // title identifies Meet, or when it is hosted by a window that exposes a
    // Meet tab. The tab strip can be missing from a capture while the call
    // surface is still readable, which previously dropped the session.
    var surfaceWebAreas: [AXNode] = []
    snapshot.root.forEachDescendant { node in
      guard isHTMLWebArea(node) else {
        return
      }
      let hostedByMeetWindow =
        node.windowID.map { meetWindowIDs.contains($0) } ?? false
      guard isMeetWebArea(node) || hostedByMeetWindow else {
        return
      }
      surfaceWebAreas.append(node)
    }
    let webAreas = surfaceWebAreas.filter { callControlsPresent(in: $0) }

    // A Meet page that exposes its content proves that the page is readable,
    // so the absence of call controls is end evidence rather than a missing
    // signal. An empty web area only means the renderer did not hand the
    // page contents to the accessibility API.
    let meetSurfaceReadable = surfaceWebAreas.contains { $0.childCount > 0 }
    let meetSurfacePresent = !surfaceWebAreas.isEmpty || !tabsByWindow.isEmpty

    var confirmedSessions = Set<MeetLatch.Anchor>()
    for webArea in webAreas {
      guard
        let windowID = webArea.windowID,
        let title = webArea.title
      else {
        continue
      }
      let normalizedTitle = normalizedAXText(title)
      let tab = tabsByWindow[windowID]?.first(where: {
        $0.normalizedLabel.hasPrefix(normalizedTitle)
      }) ?? tabsByWindow[windowID]?.first
      let identity = tab?.identity ?? webAreaIdentity(title: title)
      confirmedSessions.insert(
        MeetLatch.Anchor(
          windowID: windowID,
          tabIdentity: identity,
          confirmedAt: confirmedAt
        )
      )
    }

    // A web area stays live for as long as the page is readable, which keeps
    // the latch stable when the tab strip is temporarily missing.
    var liveWebAreaIdentities = Set<String>()
    snapshot.root.forEachDescendant { node in
      guard isMeetWebArea(node),
        let windowID = node.windowID,
        let title = node.title
      else {
        return
      }
      liveWebAreaIdentities.insert(
        "\(windowID):\(webAreaIdentity(title: title))"
      )
    }

    let liveAnchors = Set(
      anchors.filter { anchor in
        guard liveWindowIDs.contains(anchor.windowID) else {
          return false
        }
        if tabsByWindow[anchor.windowID]?.contains(where: {
          $0.identity == anchor.tabIdentity
        }) == true {
          return true
        }
        return liveWebAreaIdentities.contains(
          "\(anchor.windowID):\(anchor.tabIdentity)"
        )
      }
    )
    return MeetSelectorAnalysis(
      confirmedSessions: confirmedSessions,
      liveAnchors: liveAnchors,
      meetSurfaceReadable: meetSurfaceReadable,
      meetSurfacePresent: meetSurfacePresent
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
    var liveWebAreaIdentities = Set<String>()
    snapshot.root.forEachDescendant { node in
      if node.role == "AXWindow", let windowID = node.windowID {
        liveWindowIDs.insert(windowID)
      }
      if isMeetWebArea(node), let windowID = node.windowID, let title = node.title {
        liveWebAreaIdentities.insert(
          "\(windowID):\(webAreaIdentity(title: title))"
        )
      }
    }
    return Set(
      anchors.filter {
        liveWindowIDs.contains($0.windowID)
          && (liveTabIdentities.contains("\($0.windowID):\($0.tabIdentity)")
            || liveWebAreaIdentities.contains(
              "\($0.windowID):\($0.tabIdentity)"
            ))
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
      if isHuddleWindowTitle(normalizedAXText(window.title)) || hasControls {
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
