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
  /// Pre-flattened descendant list. The previous implementation recomputed
  /// this on every access via `children + children.flatMap(\.descendants)`,
  /// yielding O(N^2) work over a 5,000-element Chrome accessibility tree and
  /// allocating tens of megabytes of transient arrays per snapshot. Selectors
  /// call `descendants` 4+ times per sample, which made this the single
  /// biggest memory hotspot. The list is now built once at node construction
  /// (iterative DFS, single allocation) and stored for the lifetime of the
  /// snapshot.
  public let descendants: [AXNode]

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
    self.descendants = AXNode.flatten(children: children)
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
    let decodedChildren = try c.decode([AXNode].self, forKey: .children)
    self.children = decodedChildren
    self.descendants = AXNode.flatten(children: decodedChildren)
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

  private static func flatten(children: [AXNode]) -> [AXNode] {
    guard !children.isEmpty else {
      return []
    }
    var totalCount = 0
    for child in children {
      totalCount += 1 + child.descendants.count
    }
    var result: [AXNode] = []
    result.reserveCapacity(totalCount)
    var stack: [AXNode] = children.reversed()
    while let node = stack.popLast() {
      result.append(node)
      if !node.children.isEmpty {
        stack.append(contentsOf: node.children.reversed())
      }
    }
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

private func makeNode(
  _ element: AXUIElement,
  remainingDepth: Int,
  maxElements: Int,
  elementCount: inout Int,
  scanCompleted: inout Bool
) throws -> AXNode {
  guard elementCount < maxElements else {
    throw AXSnapshotError.treeTooLarge
  }
  elementCount += 1
  let role = attribute(
    element,
    kAXRoleAttribute as String,
    scanCompleted: &scanCompleted
  )
  let subrole = attribute(
    element,
    kAXSubroleAttribute as String,
    scanCompleted: &scanCompleted
  )
  let roleDescription = attribute(
    element,
    kAXRoleDescriptionAttribute as String,
    scanCompleted: &scanCompleted
  )
  let identifier = attribute(
    element,
    kAXIdentifierAttribute as String,
    scanCompleted: &scanCompleted
  )
  let title = attribute(
    element,
    kAXTitleAttribute as String,
    scanCompleted: &scanCompleted
  )
  let description = attribute(
    element,
    kAXDescriptionAttribute as String,
    scanCompleted: &scanCompleted
  )
  let value = attribute(
    element,
    kAXValueAttribute as String,
    scanCompleted: &scanCompleted
  )
  let help = attribute(
    element,
    kAXHelpAttribute as String,
    scanCompleted: &scanCompleted
  )
  let enabled = boolAttribute(
    element,
    kAXEnabledAttribute as String,
    scanCompleted: &scanCompleted
  )
  let focused = boolAttribute(
    element,
    kAXFocusedAttribute as String,
    scanCompleted: &scanCompleted
  )
  let childrenResult = copyAttribute(element, kAXChildrenAttribute as String)
  if childrenResult.0 != .success
    && childrenResult.0 != .noValue
    && childrenResult.0 != .attributeUnsupported
    && !benignChildrenFailure(role: stringValue(role), error: childrenResult.0)
  {
    scanCompleted = false
  }
  let childElements = (childrenResult.1 as? [AXUIElement]) ?? []
  let children: [AXNode]
  if remainingDepth > 0 {
    children = try childElements.enumerated().map { _, child in
      try makeNode(
        child,
        remainingDepth: remainingDepth - 1,
        maxElements: maxElements,
        elementCount: &elementCount,
        scanCompleted: &scanCompleted
      )
    }
  } else {
    children = []
  }

  return AXNode(
    role: stringValue(role),
    subrole: stringValue(subrole),
    roleDescription: stringValue(roleDescription),
    identifier: stringValue(identifier),
    title: stringValue(title),
    description: stringValue(description),
    value: stringValue(value),
    help: stringValue(help),
    enabled: enabled,
    focused: focused,
    childCount: childElements.count,
    windowID: windowID(for: element),
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

private func boolAttribute(
  _ element: AXUIElement,
  _ key: String,
  scanCompleted: inout Bool
) -> Bool? {
  (attribute(element, key, scanCompleted: &scanCompleted) as? NSNumber)?.boolValue
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
