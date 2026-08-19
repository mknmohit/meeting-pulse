import CoreGraphics
import Foundation
import MPCore
import Testing

@testable import MPDetection

struct SelectorTests {
  @Test
  func meetStrongSelectorRequiresBothCallControls() {
    let snapshot = meetSnapshot(includeControls: true)
    #expect(
      MeetSelectors.strongAnchors(
        in: snapshot,
        confirmedAt: ContinuousClock().now
      ).count == 1
    )
    #expect(
      MeetSelectors.strongAnchors(in: meetSnapshot(includeControls: false), confirmedAt: now)
        .isEmpty)
  }

  @Test
  func meetAcceptsKnownPresentationControlLabels() {
    for label in ["Share screen", "Share your screen", "Present now", "Stop presenting"] {
      #expect(
        MeetSelectors.strongAnchors(
          in: meetSnapshot(presentationDescription: label),
          confirmedAt: now
        ).count == 1
      )
    }
  }

  @Test
  func meetAcceptsDynamicPresenterStatusLabel() {
    let snapshot = meetSnapshot(presentationDescription: "A presenter is presenting")

    #expect(
      MeetSelectors.strongAnchors(in: snapshot, confirmedAt: now).count == 1
    )
  }

  @Test
  func meetNormalizesPresentationLabels() {
    let snapshot = meetSnapshot(
      presentationDescription: "  SHARE   YOUR   SCREEN  "
    )

    #expect(
      MeetSelectors.strongAnchors(in: snapshot, confirmedAt: now).count == 1
    )
  }

  @Test
  func meetDoesNotConfirmWithLeaveCallOnly() {
    let snapshot = meetSnapshot(presentationDescription: nil)

    #expect(
      MeetSelectors.strongAnchors(in: snapshot, confirmedAt: now).isEmpty
    )
  }

  @Test
  func meetTabLivenessSurvivesBackgroundedWebArea() {
    let snapshot = meetBackgroundSnapshot()
    let anchor = MeetLatch.Anchor(
      windowID: 7,
      tabIdentity: CrockfordBase32.sha256Hex("Meet - test tab"),
      confirmedAt: now
    )
    #expect(MeetSelectors.liveAnchors(in: snapshot, anchors: [anchor]) == [anchor])
  }

  @Test
  func slackRequiresDedicatedWindowAndLeaveControl() {
    let snapshot = slackSnapshot(active: true)
    #expect(SlackSelectors.huddleWindows(in: snapshot).count == 1)
    #expect(SlackSelectors.hasActiveHuddle(in: snapshot))
    #expect(!SlackSelectors.hasActiveHuddle(in: slackSnapshot(active: false)))
  }

  @Test
  func slackAcceptsCaseInsensitiveHuddleLabels() {
    let snapshot = slackSnapshot(
      active: true,
      title: "huddle: test",
      leaveDescription: "leave huddle"
    )
    #expect(SlackSelectors.hasActiveHuddle(in: snapshot))
  }

  @Test
  func descendantTraversalPreservesNestedSiblings() {
    let root = node(
      role: "AXApplication",
      children: [
        node(
          role: "AXGroup",
          children: [node(role: "AXButton", description: "nested")]
        ),
        node(role: "AXWindow", title: "second"),
      ]
    )
    var roles: [String?] = []
    root.forEachDescendant { roles.append($0.role) }
    #expect(roles == ["AXGroup", "AXButton", "AXWindow"])
  }
}

private let now = ContinuousClock().now

private func meetSnapshot(presentationDescription: String?) -> AXSnapshot {
  var controls: [AXNode] = [
    node(
      role: "AXGroup", subrole: "AXLandmarkRegion", roleDescription: "region",
      description: "Call controls"),
    node(role: "AXButton", roleDescription: "button", description: "Leave call"),
  ]
  if let presentationDescription {
    controls.append(
      node(role: "AXButton", roleDescription: "button", description: presentationDescription)
    )
  }
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
  return snapshot(children: [node(role: "AXWindow", windowID: 7, children: [webArea, tab])])
}

private func meetSnapshot(includeControls: Bool) -> AXSnapshot {
  meetSnapshot(presentationDescription: includeControls ? "Share screen" : nil)
}

private func meetBackgroundSnapshot() -> AXSnapshot {
  let webArea = node(
    role: "AXWebArea",
    roleDescription: "HTML content",
    title: "New Tab",
    windowID: 7
  )
  let tab = node(
    role: "AXRadioButton",
    subrole: "AXTabButton",
    roleDescription: "radio button",
    description: "Meet - test tab",
    windowID: 7
  )
  return snapshot(children: [node(role: "AXWindow", windowID: 7, children: [webArea, tab])])
}

private func slackSnapshot(
  active: Bool,
  title: String = "Huddle: test",
  leaveDescription: String = "Leave Huddle",
  includeToolbar: Bool = true
) -> AXSnapshot {
  let toolbar: [AXNode] =
    includeToolbar
    ? [
      node(role: "AXToolbar", description: "Huddle window actions"),
      node(role: "AXToolbar", description: "Huddles actions"),
    ]
    : []
  let children: [AXNode] =
    active
    ? [
      node(role: "AXWebArea", title: title, windowID: 8),
    ] + toolbar + [
      node(role: "AXButton", roleDescription: "button", description: leaveDescription),
    ]
    : []
  let main = node(
    role: "AXWindow", windowID: 9,
    children: [
      node(role: "AXRow", subrole: "AXOutlineRow", description: "Huddles"),
      node(role: "AXButton", description: "Start huddle with <contact>"),
    ])
  let windows =
    active
    ? [
      node(
        role: "AXWindow", subrole: "AXStandardWindow", title: title, windowID: 8,
        children: children), main,
    ]
    : [main]
  return snapshot(children: windows)
}

private func snapshot(children: [AXNode]) -> AXSnapshot {
  AXSnapshot(
    capturedAt: Date(),
    processIdentifier: 1,
    scanCompleted: true,
    root: node(role: "AXApplication", children: children)
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
