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
  func meetSurfaceIsReadableWhenThePageExposesItsContent() {
    // The Meet page is still rendered after the call ended, so the missing
    // call controls are end evidence rather than a missing signal.
    let analysis = MeetSelectors.analyze(
      in: meetSurfaceSnapshot(readable: true),
      anchors: [],
      confirmedAt: now
    )
    #expect(analysis.meetSurfaceReadable)
    #expect(analysis.meetSurfacePresent)
    #expect(analysis.confirmedSessions.isEmpty)
  }

  @Test
  func meetSurfaceIsPresentButUnreadableWithoutRenderedContent() {
    let analysis = MeetSelectors.analyze(
      in: meetSurfaceSnapshot(readable: false),
      anchors: [],
      confirmedAt: now
    )
    #expect(!analysis.meetSurfaceReadable)
    #expect(analysis.meetSurfacePresent)
  }

  @Test
  func meetSurfaceIsAbsentWhenNoPageAndNoTabRemain() {
    let analysis = MeetSelectors.analyze(
      in: meetSurfaceSnapshot(readable: false, includeSurface: false, includeTab: false),
      anchors: [],
      confirmedAt: now
    )
    #expect(!analysis.meetSurfaceReadable)
    #expect(!analysis.meetSurfacePresent)
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
  func slackRecognizesEmbeddedHuddleControls() {
    let snapshot = slackEmbeddedSnapshot(active: true)

    #expect(SlackSelectors.huddleWindows(in: snapshot).count == 1)
    #expect(SlackSelectors.hasActiveHuddle(in: snapshot))
    #expect(
      SlackSelectors.activeAnchors(in: snapshot, confirmedAt: now).count == 1
    )
  }

  @Test
  func slackDoesNotConfirmAnEmbeddedHuddleWithoutBothControls() {
    for snapshot in [
      slackEmbeddedSnapshot(includeToolbar: false),
      slackEmbeddedSnapshot(includeLeaveButton: false),
    ] {
      #expect(!SlackSelectors.hasActiveHuddle(in: snapshot))
      #expect(
        SlackSelectors.activeAnchors(in: snapshot, confirmedAt: now).isEmpty
      )
    }
  }

  @Test
  func slackDoesNotCombineEmbeddedControlsAcrossWindows() {
    let snapshot = snapshot(
      children: [
        node(
          role: "AXWindow",
          subrole: "AXStandardWindow",
          windowID: 9,
          children: [node(role: "AXToolbar", description: "Huddles actions")]
        ),
        node(
          role: "AXWindow",
          subrole: "AXStandardWindow",
          windowID: 10,
          children: [
            node(role: "AXButton", roleDescription: "button", description: "Leave Huddle")
          ]
        ),
      ]
    )

    #expect(!SlackSelectors.hasActiveHuddle(in: snapshot))
    #expect(
      SlackSelectors.activeAnchors(in: snapshot, confirmedAt: now).isEmpty
    )
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

  @Test
  func meetAcceptsTheEndsTheCurrentCallLabel() {
    let snapshot = meetWebAreaSnapshot(
      controls: [
        node(role: "AXButton", roleDescription: "button", description: "Ends the current call"),
        node(role: "AXButton", roleDescription: "button", description: "Turn on camera"),
      ]
    )

    #expect(MeetSelectors.strongAnchors(in: snapshot, confirmedAt: now).count == 1)
  }

  @Test
  func meetAcceptsTheLeaveLabelFromTheTitleAttribute() {
    let snapshot = meetWebAreaSnapshot(
      controls: [
        node(role: "AXButton", roleDescription: "button", title: "Leave call"),
        node(role: "AXButton", roleDescription: "button", title: "Participants"),
      ]
    )

    #expect(MeetSelectors.strongAnchors(in: snapshot, confirmedAt: now).count == 1)
  }

  @Test
  func meetDoesNotConfirmWithoutTheLeaveControl() {
    let snapshot = meetWebAreaSnapshot(
      controls: [
        node(role: "AXButton", roleDescription: "button", description: "Share screen"),
        node(role: "AXButton", roleDescription: "button", description: "Turn on camera"),
      ]
    )

    #expect(MeetSelectors.strongAnchors(in: snapshot, confirmedAt: now).isEmpty)
  }

  @Test
  func meetConfirmsWithoutATabStripEntry() {
    let snapshot = meetWebAreaSnapshot(
      controls: [
        node(role: "AXButton", roleDescription: "button", description: "Leave call"),
        node(role: "AXButton", roleDescription: "button", description: "Share screen"),
      ],
      includeTab: false
    )

    let anchors = MeetSelectors.strongAnchors(in: snapshot, confirmedAt: now)
    #expect(anchors.count == 1)
    #expect(
      anchors.first?.tabIdentity
        == MeetSelectors.webAreaIdentity(title: "Meet - test")
    )
  }

  @Test
  func meetConfirmsWhenTheWebAreaTitleIsNotAMeetTitle() {
    let webArea = node(
      role: "AXWebArea",
      roleDescription: "HTML content",
      title: "New Tab",
      windowID: 7,
      children: [
        node(role: "AXButton", roleDescription: "button", description: "Leave call"),
        node(role: "AXButton", roleDescription: "button", description: "Share screen"),
      ]
    )
    let tab = node(
      role: "AXRadioButton",
      subrole: "AXTabButton",
      description: "Meet - test tab",
      windowID: 7
    )
    let snapshot = snapshot(
      children: [node(role: "AXWindow", windowID: 7, children: [webArea, tab])]
    )

    #expect(MeetSelectors.strongAnchors(in: snapshot, confirmedAt: now).count == 1)
  }

  @Test
  func meetDoesNotConfirmAnUnrelatedWebArea() {
    let webArea = node(
      role: "AXWebArea",
      roleDescription: "HTML content",
      title: "New Tab",
      windowID: 7,
      children: [
        node(role: "AXButton", roleDescription: "button", description: "Leave call"),
        node(role: "AXButton", roleDescription: "button", description: "Share screen"),
      ]
    )
    let snapshot = snapshot(
      children: [node(role: "AXWindow", windowID: 7, children: [webArea])]
    )

    #expect(MeetSelectors.strongAnchors(in: snapshot, confirmedAt: now).isEmpty)
  }

  @Test
  func slackAcceptsTheDetachedHuddleWindowTitle() {
    let window = node(
      role: "AXWindow",
      subrole: "AXStandardWindow",
      title: "Huddle",
      windowID: 8,
      children: [
        node(role: "AXWebArea", title: "Huddle", windowID: 8),
        node(role: "AXButton", roleDescription: "button", description: "Leave Huddle"),
      ]
    )
    let snapshot = snapshot(children: [window])

    #expect(SlackSelectors.huddleWindows(in: snapshot).count == 1)
    #expect(SlackSelectors.hasActiveHuddle(in: snapshot))
  }

  @Test
  func slackAcceptsTheLeaveTheHuddleLabel() {
    let window = node(
      role: "AXWindow",
      subrole: "AXStandardWindow",
      title: "Huddle - standup",
      windowID: 8,
      children: [
        node(role: "AXButton", roleDescription: "button", description: "Leave the huddle"),
      ]
    )
    let snapshot = snapshot(children: [window])

    #expect(SlackSelectors.hasActiveHuddle(in: snapshot))
  }

  @Test
  func slackAcceptsTheHuddleActionsToolbar() {
    let window = node(
      role: "AXWindow",
      subrole: "AXStandardWindow",
      title: "test-channel - Slack",
      windowID: 9,
      children: [
        node(role: "AXToolbar", description: "huddle actions"),
        node(role: "AXButton", roleDescription: "button", description: "Leave Huddle"),
      ]
    )
    let snapshot = snapshot(children: [window])

    #expect(SlackSelectors.hasActiveHuddle(in: snapshot))
  }

  @Test
  func slackIgnoresTheHuddlesListWindow() {
    let window = node(
      role: "AXWindow",
      subrole: "AXStandardWindow",
      title: "Huddles",
      windowID: 8,
      children: [
        node(role: "AXRow", subrole: "AXOutlineRow", description: "Huddles"),
        node(role: "AXButton", description: "Start huddle with <contact>"),
      ]
    )
    let snapshot = snapshot(children: [window])

    #expect(SlackSelectors.huddleWindows(in: snapshot).isEmpty)
    #expect(!SlackSelectors.hasActiveHuddle(in: snapshot))
  }

  @Test
  func slackDoesNotConfirmALeaveButtonWithoutTheToolbar() {
    let window = node(
      role: "AXWindow",
      subrole: "AXStandardWindow",
      title: "test-channel - Slack",
      windowID: 9,
      children: [
        node(role: "AXButton", roleDescription: "button", description: "Leave Huddle"),
      ]
    )
    let snapshot = snapshot(children: [window])

    #expect(!SlackSelectors.hasActiveHuddle(in: snapshot))
  }
}

private func meetWebAreaSnapshot(
  controls: [AXNode],
  includeTab: Bool = true
) -> AXSnapshot {
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
  let children = includeTab ? [webArea, tab] : [webArea]
  return snapshot(children: [node(role: "AXWindow", windowID: 7, children: children)])
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

/// A Meet window without any call controls.
///
/// `readable` models the renderer handing the page contents to the
/// accessibility API, which is what turns a missing call control into end
/// evidence.
private func meetSurfaceSnapshot(
  readable: Bool,
  includeSurface: Bool = true,
  includeTab: Bool = true
) -> AXSnapshot {
  let content: [AXNode] =
    readable
    ? [node(role: "AXGroup", roleDescription: "group", description: "Meet page")]
    : []
  let webArea = node(
    role: "AXWebArea",
    roleDescription: "HTML content",
    title: "Meet - test",
    windowID: 7,
    children: content
  )
  let tab = node(
    role: "AXRadioButton",
    subrole: "AXTabButton",
    roleDescription: "radio button",
    description: "Meet - test tab",
    windowID: 7
  )
  var children: [AXNode] = []
  if includeSurface {
    children.append(webArea)
  }
  if includeTab {
    children.append(tab)
  }
  return snapshot(children: [node(role: "AXWindow", windowID: 7, children: children)])
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

private func slackEmbeddedSnapshot(
  active: Bool = true,
  includeToolbar: Bool = true,
  includeLeaveButton: Bool = true
) -> AXSnapshot {
  let activeControls: [AXNode] =
    (includeToolbar
      ? [node(role: "AXToolbar", description: "Huddles actions")]
      : [])
      + (includeLeaveButton
        ? [node(role: "AXButton", roleDescription: "button", description: "Leave Huddle")]
        : [])
  let children: [AXNode] =
    active
    ? activeControls
    : [
      node(role: "AXRow", subrole: "AXOutlineRow", description: "Huddles"),
      node(role: "AXButton", description: "Start huddle with <contact>"),
    ]
  return snapshot(
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
