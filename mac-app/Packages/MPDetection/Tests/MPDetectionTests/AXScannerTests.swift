import Foundation
import Testing

@testable import MPDetection

/// An in-memory accessibility tree used to exercise the bounded traversal
/// without a running application.
private struct FakeElement {
  let role: String
  let title: String?
  let description: String?
  let children: [FakeElement]
}

private struct FakeTreeSource: AXTreeSource {
  typealias Element = FakeElement

  func role(of element: FakeElement) -> String? {
    element.role
  }

  func children(of element: FakeElement) -> [FakeElement] {
    element.children
  }

  func entry(of element: FakeElement) -> AXScanEntry<FakeElement> {
    AXScanEntry(
      payload: Payload(
        role: element.role,
        subrole: nil,
        roleDescription: nil,
        identifier: nil,
        title: element.title,
        description: element.description,
        value: nil,
        help: nil,
        enabled: nil,
        focused: nil,
        childCount: element.children.count,
        windowID: nil
      ),
      children: element.children,
      complete: true
    )
  }

  func rootPayload(of element: FakeElement, childCount: Int) -> Payload {
    Payload(
      role: element.role,
      subrole: nil,
      roleDescription: nil,
      identifier: nil,
      title: element.title,
      description: element.description,
      value: nil,
      help: nil,
      enabled: nil,
      focused: nil,
      childCount: childCount,
      windowID: nil
    )
  }
}

/// A source that cannot fully read the application root.
///
/// Chrome intermittently answers the application root with an error. The
/// windows are discovered separately, so that failure must not invalidate an
/// otherwise complete scan.
private struct FailingRootSource: AXTreeSource {
  typealias Element = FakeElement

  func role(of element: FakeElement) -> String? {
    element.role
  }

  func children(of element: FakeElement) -> [FakeElement] {
    element.children
  }

  func entry(of element: FakeElement) -> AXScanEntry<FakeElement> {
    AXScanEntry(
      payload: Payload(
        role: element.role,
        subrole: nil,
        roleDescription: nil,
        identifier: nil,
        title: element.title,
        description: element.description,
        value: nil,
        help: nil,
        enabled: nil,
        focused: nil,
        childCount: element.children.count,
        windowID: nil
      ),
      children: element.children,
      complete: element.role != "AXApplication"
    )
  }

  func rootPayload(of element: FakeElement, childCount: Int) -> Payload {
    Payload(
      role: element.role,
      subrole: nil,
      roleDescription: nil,
      identifier: nil,
      title: element.title,
      description: element.description,
      value: nil,
      help: nil,
      enabled: nil,
      focused: nil,
      childCount: childCount,
      windowID: nil
    )
  }
}

private func element(
  _ role: String,
  title: String? = nil,
  description: String? = nil,
  children: [FakeElement] = []
) -> FakeElement {
  FakeElement(
    role: role,
    title: title,
    description: description,
    children: children
  )
}

private func titles(in node: AXNode) -> [String] {
  var result: [String] = []
  if let title = node.title {
    result.append(title)
  }
  for child in node.children {
    result.append(contentsOf: titles(in: child))
  }
  return result
}

struct AXScannerTests {
  @Test
  func breadthFirstTraversalReachesShallowSignalsBeforeDeepContent() {
    // A deep chain that would consume the whole budget in a depth-first walk.
    var deep = element("AXStaticText", title: "deep-leaf")
    for index in 0..<40 {
      deep = element("AXGroup", title: "deep-\(index)", children: [deep])
    }
    let root = element(
      "AXWindow",
      title: "window",
      children: [
        element(
          "AXWebArea",
          title: "Meet - standup",
          children: [
            element("AXButton", description: "Leave call"),
            deep,
          ]
        )
      ]
    )

    let result = scanBreadthFirst(
      root: root,
      maxDepth: 24,
      maxElements: 12,
      source: FakeTreeSource()
    )

    #expect(!result.scanCompleted)
    let assembled = assembleNodes(result)
    #expect(assembled != nil)
    #expect(titles(in: assembled!).contains("Meet - standup"))
    #expect(titles(in: assembled!).contains("window"))
  }

  @Test
  func truncatedScanKeepsThePartialTree() {
    var leaf = element("AXStaticText", title: "leaf")
    for index in 0..<20 {
      leaf = element("AXGroup", title: "node-\(index)", children: [leaf])
    }
    let root = element("AXWindow", title: "window", children: [leaf])

    let result = scanBreadthFirst(
      root: root,
      maxDepth: 24,
      maxElements: 5,
      source: FakeTreeSource()
    )

    #expect(!result.scanCompleted)
    #expect(result.payloads.count == 5)
    #expect(assembleNodes(result) != nil)
  }

  @Test
  func completeScanInsideTheBudgetKeepsEveryElement() {
    let root = element(
      "AXWindow",
      title: "window",
      children: [
        element(
          "AXWebArea",
          title: "Meet - standup",
          children: [element("AXButton", description: "Leave call")]
        )
      ]
    )

    let result = scanBreadthFirst(
      root: root,
      maxDepth: 24,
      maxElements: 100,
      source: FakeTreeSource()
    )

    #expect(result.scanCompleted)
    #expect(result.payloads.count == 3)
  }

  @Test
  func depthLimitStopsTheWalkWithoutFailingTheScan() {
    var leaf = element("AXStaticText", title: "leaf")
    for index in 0..<10 {
      leaf = element("AXGroup", title: "node-\(index)", children: [leaf])
    }
    let root = element("AXWindow", title: "window", children: [leaf])

    let result = scanBreadthFirst(
      root: root,
      maxDepth: 3,
      maxElements: 100,
      source: FakeTreeSource()
    )

    #expect(result.scanCompleted)
    #expect(result.payloads.count == 4)
    #expect(titles(in: assembleNodes(result)!).contains("node-7"))
    #expect(!titles(in: assembleNodes(result)!).contains("node-6"))
    #expect(!titles(in: assembleNodes(result)!).contains("leaf"))
  }

  @Test
  func windowDiscoveryFindsEveryTopLevelWindow() {
    let root = element(
      "AXApplication",
      children: [
        element("AXWindow", title: "first"),
        element(
          "AXGroup",
          children: [element("AXWindow", title: "second")]
        ),
      ]
    )

    let windows = discoverWindows(
      root: root,
      maxDepth: 6,
      maxElements: 512,
      source: FakeTreeSource()
    )

    #expect(windows.count == 2)
    #expect(windows.map(\.title) == ["first", "second"])
  }

  @Test
  func windowDiscoveryDoesNotDescendIntoWindows() {
    let root = element(
      "AXApplication",
      children: [
        element(
          "AXWindow",
          title: "first",
          children: [element("AXWindow", title: "nested")]
        )
      ]
    )

    let windows = discoverWindows(
      root: root,
      maxDepth: 6,
      maxElements: 512,
      source: FakeTreeSource()
    )

    #expect(windows.count == 1)
    #expect(windows.first?.title == "first")
  }

  @Test
  func snapshotStaysCompleteWhenTheApplicationRootCannotBeFullyRead() {
    let root = element(
      "AXApplication",
      children: [
        element(
          "AXWindow",
          title: "Meet - standup",
          children: [
            element("AXButton", description: "Leave call")
          ]
        )
      ]
    )

    let snapshot = makeSnapshot(
      root: root,
      processIdentifier: 42,
      maxDepth: 24,
      maxElements: 4_000,
      source: FailingRootSource()
    )

    // The root is only read for its payload, so the failing read of the
    // application root cannot mark the scan as incomplete.
    #expect(snapshot.scanCompleted)
    #expect(titles(in: snapshot.root).contains("Meet - standup"))
  }

  @Test
  func snapshotExposesTheScannedWindowsUnderTheRoot() {
    let root = element(
      "AXApplication",
      children: [
        element(
          "AXWindow",
          title: "Meet - standup",
          children: [
            element("AXWebArea", title: "Meet - standup")
          ]
        )
      ]
    )

    let snapshot = makeSnapshot(
      root: root,
      processIdentifier: 42,
      maxDepth: 24,
      maxElements: 4_000,
      source: FakeTreeSource()
    )

    #expect(snapshot.scanCompleted)
    #expect(snapshot.root.role == "AXApplication")
    #expect(snapshot.root.childCount == 1)
    #expect(snapshot.root.children.count == 1)
    #expect(snapshot.root.children.first?.role == "AXWindow")
  }
}
