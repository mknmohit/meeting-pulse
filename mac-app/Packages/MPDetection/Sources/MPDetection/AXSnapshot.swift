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
  public let path: String
  public let windowID: CGWindowID?
  public let children: [AXNode]

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
    path: String,
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
    self.path = path
    self.windowID = windowID
    self.children = children
  }

  public var descendants: [AXNode] {
    children + children.flatMap(\.descendants)
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
    path: "application",
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
  path: String,
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
    children = try childElements.enumerated().map { index, child in
      try makeNode(
        child,
        path: "\(path)/\(index)",
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
    path: path,
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
