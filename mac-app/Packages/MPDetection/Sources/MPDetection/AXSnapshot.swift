import ApplicationServices
import CoreGraphics
import Darwin
import Foundation

public struct AXNode: Codable, Equatable, Sendable {
  public let role: String?
  public let subrole: String?
  public let roleDescription: String?
  public let identifier: String?
  public let title: String?
  public let description: String?
  public let value: String?
  public let help: String?
  public let enabled: Bool?
  public let focused: Bool?
  public let childCount: Int
  public let windowID: CGWindowID?
  public let children: [AXNode]

  private enum CodingKeys: String, CodingKey {
    case role, subrole, roleDescription, identifier, title, description, value,
      help, enabled, focused, childCount, windowID, children
  }

  public init(
    role: String?,
    subrole: String?,
    roleDescription: String?,
    identifier: String?,
    title: String?,
    description: String?,
    value: String?,
    help: String?,
    enabled: Bool?,
    focused: Bool?,
    childCount: Int,
    windowID: CGWindowID?,
    children: [AXNode]
  ) {
    self.role = role
    self.subrole = subrole
    self.roleDescription = roleDescription
    self.identifier = identifier
    self.title = title
    self.description = description
    self.value = value
    self.help = help
    self.enabled = enabled
    self.focused = focused
    self.childCount = childCount
    self.windowID = windowID
    self.children = children
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    self.role = try c.decodeIfPresent(String.self, forKey: .role)
    self.subrole = try c.decodeIfPresent(String.self, forKey: .subrole)
    self.roleDescription = try c.decodeIfPresent(String.self, forKey: .roleDescription)
    self.identifier = try c.decodeIfPresent(String.self, forKey: .identifier)
    self.title = try c.decodeIfPresent(String.self, forKey: .title)
    self.description = try c.decodeIfPresent(String.self, forKey: .description)
    self.value = try c.decodeIfPresent(String.self, forKey: .value)
    self.help = try c.decodeIfPresent(String.self, forKey: .help)
    self.enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled)
    self.focused = try c.decodeIfPresent(Bool.self, forKey: .focused)
    self.childCount = try c.decode(Int.self, forKey: .childCount)
    self.windowID = try c.decodeIfPresent(CGWindowID.self, forKey: .windowID)
    self.children = try c.decode([AXNode].self, forKey: .children)
  }

  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encodeIfPresent(role, forKey: .role)
    try c.encodeIfPresent(subrole, forKey: .subrole)
    try c.encodeIfPresent(roleDescription, forKey: .roleDescription)
    try c.encodeIfPresent(identifier, forKey: .identifier)
    try c.encodeIfPresent(title, forKey: .title)
    try c.encodeIfPresent(description, forKey: .description)
    try c.encodeIfPresent(value, forKey: .value)
    try c.encodeIfPresent(help, forKey: .help)
    try c.encodeIfPresent(enabled, forKey: .enabled)
    try c.encodeIfPresent(focused, forKey: .focused)
    try c.encode(childCount, forKey: .childCount)
    try c.encodeIfPresent(windowID, forKey: .windowID)
    try c.encode(children, forKey: .children)
  }

  /// Visits descendants without retaining a second copy of the tree.
  public func forEachDescendant(_ visit: (AXNode) -> Void) {
    var stack = Array(children.reversed())
    while let node = stack.popLast() {
      visit(node)
      if !node.children.isEmpty {
        stack.append(contentsOf: node.children.reversed())
      }
    }
  }

  /// Compatibility accessor for callers that need a materialized list.
  ///
  /// Selectors use `forEachDescendant` so normal detection scans do not
  /// allocate or retain a flattened tree.
  public var descendants: [AXNode] {
    var result: [AXNode] = []
    result.reserveCapacity(children.count)
    forEachDescendant { result.append($0) }
    return result
  }
}

public struct AXSnapshot: Codable, Equatable, Sendable {
  public let capturedAt: Date
  public let processIdentifier: pid_t
  public let scanCompleted: Bool
  public let root: AXNode

  public init(
    capturedAt: Date,
    processIdentifier: pid_t,
    scanCompleted: Bool,
    root: AXNode
  ) {
    self.capturedAt = capturedAt
    self.processIdentifier = processIdentifier
    self.scanCompleted = scanCompleted
    self.root = root
  }
}

public enum AXSnapshotError: Error, Equatable, Sendable {
  case permissionDenied
  case treeTooLarge
  case unreadable(Int32)
}

// MARK: - Tree source

/// The attributes read from a single accessibility element.
struct Payload {
  let role: String?
  let subrole: String?
  let roleDescription: String?
  let identifier: String?
  let title: String?
  let description: String?
  let value: String?
  let help: String?
  let enabled: Bool?
  let focused: Bool?
  var childCount: Int
  let windowID: CGWindowID?
}

/// One element of a scan: its payload plus the children that were read.
struct AXScanEntry<Element> {
  let payload: Payload
  let children: [Element]
  /// False when an attribute or the child list could not be read completely.
  let complete: Bool
}

/// Abstraction over the accessibility tree so the traversal can be exercised
/// without a running application.
protocol AXTreeSource<Element> {
  associatedtype Element
  /// Cheap role read used by the window discovery pass.
  func role(of element: Element) -> String?
  /// Cheap child list read used by the window discovery pass.
  func children(of element: Element) -> [Element]
  /// Full read used by the scanning pass.
  func entry(of element: Element) -> AXScanEntry<Element>
  /// Reads the payload of the tree root without touching its child list.
  ///
  /// The children of the root are discovered and scanned separately, so
  /// reading them again here added a failure point without adding
  /// information. A failure on that redundant read marked the whole snapshot
  /// as incomplete even though every window had been scanned successfully,
  /// which turned a healthy scan into "status unavailable".
  func rootPayload(of element: Element, childCount: Int) -> Payload
}

/// Result of a bounded traversal.
struct AXScanResult {
  let payloads: [Payload]
  let childIndices: [[Int]]
  let scanCompleted: Bool
}

/// Breadth-first, depth-limited, element-bounded traversal.
///
/// The walk is breadth-first on purpose. Meet and Slack expose their call
/// controls close to the root of a window, while the page content of a long
/// running call sits much deeper. A depth-first walk spends the whole element
/// budget on the first branch and loses the call controls, which is what made
/// a long meeting read as "unavailable" once the accessibility tree grew.
///
/// The traversal never fails when the budget is exhausted. It stops, keeps the
/// partial tree and reports `scanCompleted = false` so a truncated scan still
/// carries the shallow call signals instead of discarding everything.
func scanBreadthFirst<Element>(
  root: Element,
  maxDepth: Int,
  maxElements: Int,
  source: some AXTreeSource<Element>
) -> AXScanResult {
  var payloads: [Payload] = []
  var childIndices: [[Int]] = []
  payloads.reserveCapacity(min(max(maxElements, 0), 8_192))
  childIndices.reserveCapacity(min(max(maxElements, 0), 8_192))
  var scanCompleted = true

  var work: [(element: Element, remainingDepth: Int, parentIndex: Int)] = [
    (root, maxDepth, -1)
  ]
  var head = 0

  while head < work.count {
    let item = work[head]
    head += 1

    guard payloads.count < maxElements else {
      scanCompleted = false
      break
    }

    let myIndex = payloads.count
    let read = source.entry(of: item.element)
    if !read.complete {
      scanCompleted = false
    }
    var payload = read.payload
    payload.childCount = read.children.count

    payloads.append(payload)
    childIndices.append([])
    if item.parentIndex >= 0 {
      childIndices[item.parentIndex].append(myIndex)
    }

    guard item.remainingDepth > 0 else {
      continue
    }
    for child in read.children {
      work.append(
        (child, item.remainingDepth - 1, myIndex)
      )
    }
  }

  return AXScanResult(
    payloads: payloads,
    childIndices: childIndices,
    scanCompleted: scanCompleted
  )
}

/// Shallow walk that collects the top-level windows of an application.
///
/// The pass only reads the role and the child list of each node, so it stays
/// cheap even when the application exposes a very large tree.
func discoverWindows<Element>(
  root: Element,
  maxDepth: Int,
  maxElements: Int,
  source: some AXTreeSource<Element>
) -> [Element] {
  var windows: [Element] = []
  var visited = 0
  var work: [(element: Element, remainingDepth: Int)] = [(root, maxDepth)]
  var head = 0

  while head < work.count {
    let item = work[head]
    head += 1
    guard visited < maxElements else {
      break
    }
    visited += 1
    guard item.remainingDepth > 0 else {
      continue
    }
    for child in source.children(of: item.element) {
      if source.role(of: child) == "AXWindow" {
        windows.append(child)
        continue
      }
      work.append((child, item.remainingDepth - 1))
    }
  }
  return windows
}

/// Assembles the scanned payloads into an `AXNode` tree.
func assembleNodes(_ result: AXScanResult) -> AXNode? {
  guard !result.payloads.isEmpty else {
    return nil
  }
  func assemble(_ index: Int) -> AXNode {
    let children = result.childIndices[index].map(assemble)
    let payload = result.payloads[index]
    return AXNode(
      role: payload.role,
      subrole: payload.subrole,
      roleDescription: payload.roleDescription,
      identifier: payload.identifier,
      title: payload.title,
      description: payload.description,
      value: payload.value,
      help: payload.help,
      enabled: payload.enabled,
      focused: payload.focused,
      childCount: payload.childCount,
      windowID: payload.windowID,
      children: children
    )
  }
  return assemble(0)
}

// MARK: - Accessibility implementation

private typealias AXGetWindowFunction =
  @convention(c) (
    AXUIElement,
    UnsafeMutablePointer<CGWindowID>
  ) -> AXError

private let axGetWindow: AXGetWindowFunction? = {
  guard let symbol = dlsym(dlopen(nil, RTLD_LAZY), "_AXUIElementGetWindow") else {
    return nil
  }
  return unsafeBitCast(symbol, to: AXGetWindowFunction.self)
}()

/// Reads the live accessibility tree of an application.
struct AXUITreeSource: AXTreeSource {
  typealias Element = AXUIElement

  func role(of element: AXUIElement) -> String? {
    stringValue(copyAttribute(element, kAXRoleAttribute as String).1)
  }

  func children(of element: AXUIElement) -> [AXUIElement] {
    (copyAttribute(element, kAXChildrenAttribute as String).1 as? [AXUIElement]) ?? []
  }

  func entry(of element: AXUIElement) -> AXScanEntry<AXUIElement> {
    var complete = true
    let role = self.role(of: element)
    let childrenResult = copyAttribute(
      element,
      kAXChildrenAttribute as String
    )
    let children = (childrenResult.1 as? [AXUIElement]) ?? []
    if childrenResult.0 != .success
      && childrenResult.0 != .noValue
      && childrenResult.0 != .attributeUnsupported
      && !benignChildrenFailure(role: role, error: childrenResult.0)
    {
      complete = false
    }
    let payload = readPayload(
      element: element,
      role: role,
      childCount: children.count,
      scanCompleted: &complete
    )
    return AXScanEntry(
      payload: payload,
      children: children,
      complete: complete
    )
  }

  /// Reads the application root without touching its child list.
  func rootPayload(of element: AXUIElement, childCount: Int) -> Payload {
    var complete = true
    return readPayload(
      element: element,
      role: role(of: element),
      childCount: childCount,
      scanCompleted: &complete
    )
  }
}

func makeSnapshot(
  application: AXUIElement,
  processIdentifier: pid_t,
  maxDepth: Int,
  maxElements: Int
) throws -> AXSnapshot {
  makeSnapshot(
    root: application,
    processIdentifier: processIdentifier,
    maxDepth: maxDepth,
    maxElements: maxElements,
    source: AXUITreeSource()
  )
}

/// Builds a snapshot from any tree source.
///
/// The traversal is split into a window discovery pass and a bounded scan per
/// window. The root element is only read for its payload, never for its child
/// list, so a failing read on the application root cannot invalidate an
/// otherwise complete scan.
func makeSnapshot<Element>(
  root: Element,
  processIdentifier: pid_t,
  maxDepth: Int,
  maxElements: Int,
  source: some AXTreeSource<Element>
) -> AXSnapshot {
  var scanCompleted = true

  let windows = discoverWindows(
    root: root,
    maxDepth: 6,
    maxElements: 512,
    source: source
  )

  var children: [AXNode] = []
  if windows.isEmpty {
    // No window was discovered. Fall back to a single bounded scan of the
    // application element so hosts without window nodes still produce a
    // usable snapshot.
    let result = scanBreadthFirst(
      root: root,
      maxDepth: maxDepth,
      maxElements: maxElements,
      source: source
    )
    scanCompleted = scanCompleted && result.scanCompleted
    if let assembled = assembleNodes(result) {
      children = assembled.children
    }
  } else {
    // Each window gets its own budget so one large window cannot starve the
    // others. A single Chrome window holding a two hour meeting is the common
    // case, so the per-window floor stays generous.
    let perWindowBudget = min(
      maxElements,
      max(maxElements / max(windows.count, 1), 2_000)
    )
    for window in windows {
      let result = scanBreadthFirst(
        root: window,
        maxDepth: maxDepth,
        maxElements: perWindowBudget,
        source: source
      )
      scanCompleted = scanCompleted && result.scanCompleted
      if let assembled = assembleNodes(result) {
        children.append(assembled)
      }
    }
  }

  let rootPayload = source.rootPayload(of: root, childCount: children.count)

  let root = AXNode(
    role: rootPayload.role,
    subrole: rootPayload.subrole,
    roleDescription: rootPayload.roleDescription,
    identifier: rootPayload.identifier,
    title: rootPayload.title,
    description: rootPayload.description,
    value: rootPayload.value,
    help: rootPayload.help,
    enabled: rootPayload.enabled,
    focused: rootPayload.focused,
    childCount: children.count,
    windowID: rootPayload.windowID,
    children: children
  )
  return AXSnapshot(
    capturedAt: Date(),
    processIdentifier: processIdentifier,
    scanCompleted: scanCompleted,
    root: root
  )
}

/// Attributes that are worth reading for a given role. Detection only needs
/// labels on the roles that can carry a call signal, so every other node
/// costs a single accessibility read instead of five.
private struct AttributePlan {
  let subrole: Bool
  let roleDescription: Bool
  let title: Bool
  let description: Bool

  static let none = AttributePlan(
    subrole: false,
    roleDescription: false,
    title: false,
    description: false
  )

  static let full = AttributePlan(
    subrole: true,
    roleDescription: true,
    title: true,
    description: true
  )

  static func forRole(_ role: String?) -> AttributePlan {
    switch role {
    case "AXWindow", "AXWebArea", "AXRadioButton", "AXGroup", "AXButton",
      "AXToolbar":
      return .full
    case "AXRow", "AXOutline", "AXMenuButton", "AXTabGroup", "AXList":
      return AttributePlan(
        subrole: false,
        roleDescription: true,
        title: true,
        description: true
      )
    case "AXStaticText":
      return AttributePlan(
        subrole: false,
        roleDescription: false,
        title: true,
        description: true
      )
    default:
      return .none
    }
  }
}

private func readPayload(
  element: AXUIElement,
  role: String?,
  childCount: Int,
  scanCompleted: inout Bool
) -> Payload {
  let plan = AttributePlan.forRole(role)
  let subrole = plan.subrole
    ? attribute(element, kAXSubroleAttribute as String, scanCompleted: &scanCompleted)
    : nil
  let roleDescription = plan.roleDescription
    ? attribute(
      element,
      kAXRoleDescriptionAttribute as String,
      scanCompleted: &scanCompleted
    )
    : nil
  let title = plan.title
    ? attribute(element, kAXTitleAttribute as String, scanCompleted: &scanCompleted)
    : nil
  let description = plan.description
    ? attribute(
      element,
      kAXDescriptionAttribute as String,
      scanCompleted: &scanCompleted
    )
    : nil
  return Payload(
    role: role,
    subrole: stringValue(subrole),
    roleDescription: stringValue(roleDescription),
    identifier: nil,
    title: stringValue(title),
    description: stringValue(description),
    value: nil,
    help: nil,
    enabled: nil,
    focused: nil,
    childCount: childCount,
    windowID: needsWindowID(role: role, subrole: stringValue(subrole))
      ? windowID(for: element)
      : nil
  )
}

private func copyAttribute(
  _ element: AXUIElement,
  _ attribute: String
) -> (AXError, CFTypeRef?) {
  var value: CFTypeRef?
  let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
  return (result, value)
}

private func attribute(
  _ element: AXUIElement,
  _ attribute: String,
  scanCompleted: inout Bool
) -> CFTypeRef? {
  let result = copyAttribute(element, attribute)
  if result.0 != .success && result.0 != .noValue && result.0 != .attributeUnsupported {
    scanCompleted = false
  }
  return result.1
}

private func needsWindowID(role: String?, subrole: String?) -> Bool {
  role == "AXWindow"
    || role == "AXWebArea"
    || (role == "AXRadioButton" && subrole == "AXTabButton")
}

private func benignChildrenFailure(role: String?, error: AXError) -> Bool {
  guard error == .failure else {
    return false
  }
  // Chrome exposes these leaf roles without a readable AXChildren value.
  switch role {
  case "AXButton", "AXColumn", "AXTextField":
    return true
  default:
    return false
  }
}

private func stringValue(_ value: CFTypeRef?) -> String? {
  guard let value else {
    return nil
  }
  if let string = value as? String {
    // Truncate accessibility values to keep the snapshot compact. Strings
    // already short enough are returned as-is to avoid allocating a copy.
    if string.count <= 120 {
      return string
    }
    return String(string.prefix(120))
  }
  if let number = value as? NSNumber {
    return number.stringValue
  }
  return nil
}

private func windowID(for element: AXUIElement) -> CGWindowID? {
  guard let axGetWindow else {
    return nil
  }
  var id: CGWindowID = 0
  guard axGetWindow(element, &id) == .success, id != 0 else {
    return nil
  }
  return id
}
