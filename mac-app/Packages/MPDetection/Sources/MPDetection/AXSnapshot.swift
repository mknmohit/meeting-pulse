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

func makeSnapshot(
  application: AXUIElement,
  processIdentifier: pid_t,
  maxDepth: Int,
  maxElements: Int
) throws -> AXSnapshot {
  var elementCount = 0
  var scanCompleted = true
  let root = try makeNode(
    application,
    remainingDepth: maxDepth,
    maxElements: maxElements,
    elementCount: &elementCount,
    scanCompleted: &scanCompleted
  )
  return AXSnapshot(
    capturedAt: Date(),
    processIdentifier: processIdentifier,
    scanCompleted: scanCompleted,
    root: root
  )
}
// Iterative, depth-limited accessibility tree walk.
//
// The previous implementation rebuilt this graph with recursion and retained
// a flattened copy of every subtree. Chromium-based hosts can expose large,
// deeply nested trees, so the scan now keeps only bounded payload and parent
// metadata until the final value tree is assembled.
//
// Algorithm: collect a bounded flat graph, then assemble the value tree.
//
// Pass 1 walks the tree in pre-order using an explicit work stack,
// reading attributes and pushing children in reverse (so they visit in
// source order). Each visit records a payload and parent-index entry.
// Stops at `maxDepth` and `maxElements`.
//
// Each work item carries its parent index, so siblings and nested
// descendants cannot be confused during assembly. The final recursion is
// bounded by the depth cap and only builds the immutable value tree.
//
// `AXNode` is a struct with `let` fields; assembly creates each value once.

private struct Payload {
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
  let childCount: Int
  let windowID: CGWindowID?
}

private struct WorkItem {
  let element: AXUIElement
  let remainingDepth: Int
  let parentIndex: Int
}

private func makeNode(
  _ rootElement: AXUIElement,
  remainingDepth: Int,
  maxElements: Int,
  elementCount: inout Int,
  scanCompleted: inout Bool
) throws -> AXNode {
  // ----- Pass 1: pre-order DFS, record placeholders and metadata -----

  var payloads: [Payload] = []
  payloads.reserveCapacity(min(maxElements, 4096))
  var childIndices: [[Int]] = []
  childIndices.reserveCapacity(min(maxElements, 4096))

  var work: [WorkItem] = []
  work.reserveCapacity(256)
  work.append(WorkItem(element: rootElement, remainingDepth: remainingDepth, parentIndex: -1))

  while let item = work.popLast() {
    guard payloads.count < maxElements else {
      throw AXSnapshotError.treeTooLarge
    }

    let myIndex = payloads.count
    elementCount += 1
    let childrenResult = copyAttribute(item.element, kAXChildrenAttribute as String)
    let childElements = (childrenResult.1 as? [AXUIElement]) ?? []
    let payload = readPayload(
      element: item.element,
      childCount: childElements.count,
      scanCompleted: &scanCompleted
    )
    if childrenResult.0 != .success
      && childrenResult.0 != .noValue
      && childrenResult.0 != .attributeUnsupported
      && !benignChildrenFailure(role: payload.role, error: childrenResult.0)
    {
      scanCompleted = false
    }

    payloads.append(payload)
    childIndices.append([])
    if item.parentIndex >= 0 {
      childIndices[item.parentIndex].append(myIndex)
    }

    let canDescend = item.remainingDepth > 0 && !childElements.isEmpty
    if !canDescend {
      continue
    }

    // Push children in reverse so they are visited in source order.
    for child in childElements.reversed() {
      work.append(WorkItem(
        element: child,
        remainingDepth: item.remainingDepth - 1,
        parentIndex: myIndex
      ))
    }
  }

  guard !payloads.isEmpty else {
    throw AXSnapshotError.unreadable(-1)
  }

  func assemble(_ index: Int) -> AXNode {
    let children = childIndices[index].map(assemble)
    let payload = payloads[index]
    return makeNode(payload: payload, children: children)
  }

  return assemble(0)
}

private func readPayload(
  element: AXUIElement,
  childCount: Int,
  scanCompleted: inout Bool
) -> Payload {
  // Detection only needs role and label metadata. The remaining public fields
  // stay available for compatibility but are intentionally not queried here.
  let role = attribute(element, kAXRoleAttribute as String, scanCompleted: &scanCompleted)
  let subrole = attribute(element, kAXSubroleAttribute as String, scanCompleted: &scanCompleted)
  let roleDescription = attribute(
    element,
    kAXRoleDescriptionAttribute as String,
    scanCompleted: &scanCompleted
  )
  let title = attribute(element, kAXTitleAttribute as String, scanCompleted: &scanCompleted)
  let description = attribute(
    element,
    kAXDescriptionAttribute as String,
    scanCompleted: &scanCompleted
  )
  let roleValue = stringValue(role)
  let subroleValue = stringValue(subrole)
  return Payload(
    role: roleValue,
    subrole: subroleValue,
    roleDescription: stringValue(roleDescription),
    identifier: nil,
    title: stringValue(title),
    description: stringValue(description),
    value: nil,
    help: nil,
    enabled: nil,
    focused: nil,
    childCount: childCount,
    windowID: needsWindowID(role: roleValue, subrole: subroleValue)
      ? windowID(for: element)
      : nil
  )
}

private func makeNode(payload: Payload, children: [AXNode]) -> AXNode {
  AXNode(
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
    // Truncate accessibilitiy values to keep the snapshot compact. Strings
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
