import AppKit
import ApplicationServices
import CoreGraphics
import Darwin
import Foundation

private enum AXDumpError: Error, CustomStringConvertible {
  case usage(String)
  case accessibilityDenied
  case applicationNotRunning(String)
  case applicationLookupFailed(String)
  case captureFailed(String)
  case outputFailed(String)

  var description: String {
    switch self {
    case .usage(let message):
      return message
    case .accessibilityDenied:
      return
        "Accessibility permission is not granted. Open System Settings > Privacy & Security > Accessibility, then try again."
    case .applicationNotRunning(let bundle):
      return "No running application found for bundle \(bundle)."
    case .applicationLookupFailed(let bundle):
      return "Could not inspect the running application \(bundle)."
    case .captureFailed(let message):
      return "Accessibility capture failed: \(message)"
    case .outputFailed(let message):
      return "Could not write output: \(message)"
    }
  }
}

private struct AXNode: Codable, Equatable {
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
  let path: String
  let windowNumber: CGWindowID?
  let diagnosticCode: String?
  let children: [AXNode]
}

private struct AXSnapshot: Codable {
  let schemaVersion: Int
  let capturedAt: Date
  let bundleIdentifier: String
  let processIdentifier: Int32
  let root: AXNode
}

private struct WatchEvent: Encodable {
  let timestamp: Date
  let bundleIdentifier: String
  let processIdentifier: Int32
  let notification: String
  let role: String?
}

private struct DiffResult: Encodable {
  let added: [String]
  let removed: [String]
  let changed: [String]
}

private struct Options {
  var bundleIdentifier: String?
  var depth = 20
  var outputPath: String?
  var watch = false
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

private func copyAttribute(_ element: AXUIElement, _ attribute: String) -> (AXError, CFTypeRef?) {
  var value: CFTypeRef?
  let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
  return (result, value)
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

private func boolValue(_ value: CFTypeRef?) -> Bool? {
  (value as? NSNumber)?.boolValue
}

private func childrenValue(_ value: CFTypeRef?) -> [AXUIElement] {
  (value as? [AXUIElement]) ?? []
}

private func diagnosticCode(for error: AXError) -> String {
  switch error {
  case .apiDisabled:
    return "AX_API_DISABLED"
  case .notImplemented:
    return "AX_NOT_IMPLEMENTED"
  case .invalidUIElement:
    return "AX_INVALID_UI_ELEMENT"
  case .cannotComplete:
    return "AX_CANNOT_COMPLETE"
  default:
    return "AX_ERROR_\(error.rawValue)"
  }
}

private func windowNumber(for element: AXUIElement) -> CGWindowID? {
  guard let axGetWindow else {
    return nil
  }
  var number: CGWindowID = 0
  guard axGetWindow(element, &number) == .success else {
    return nil
  }
  return number == 0 ? nil : number
}

private func node(
  from element: AXUIElement,
  path: String,
  remainingDepth: Int,
  elementCount: inout Int
) throws -> AXNode {
  guard elementCount < 5_000 else {
    throw AXDumpError.captureFailed("AX_TREE_TOO_LARGE")
  }
  try Task.checkCancellation()
  elementCount += 1

  let roleResult = copyAttribute(element, kAXRoleAttribute as String)
  let subroleResult = copyAttribute(element, kAXSubroleAttribute as String)
  let roleDescriptionResult = copyAttribute(element, kAXRoleDescriptionAttribute as String)
  let identifierResult = copyAttribute(element, kAXIdentifierAttribute as String)
  let titleResult = copyAttribute(element, kAXTitleAttribute as String)
  let descriptionResult = copyAttribute(element, kAXDescriptionAttribute as String)
  let valueResult = copyAttribute(element, kAXValueAttribute as String)
  let helpResult = copyAttribute(element, kAXHelpAttribute as String)
  let enabledResult = copyAttribute(element, kAXEnabledAttribute as String)
  let focusedResult = copyAttribute(element, kAXFocusedAttribute as String)
  let childrenResult = copyAttribute(element, kAXChildrenAttribute as String)

  let childElements = childrenValue(childrenResult.1)
  let children: [AXNode]
  if remainingDepth > 0 {
    children = try childElements.enumerated().map { index, child in
      try node(
        from: child,
        path: "\(path)/\(index)",
        remainingDepth: remainingDepth - 1,
        elementCount: &elementCount
      )
    }
  } else {
    children = []
  }

  let errors = [
    roleResult.0,
    subroleResult.0,
    roleDescriptionResult.0,
    identifierResult.0,
    titleResult.0,
    descriptionResult.0,
    valueResult.0,
    helpResult.0,
    enabledResult.0,
    focusedResult.0,
    childrenResult.0,
  ].filter { $0 != .success }

  return AXNode(
    role: stringValue(roleResult.1),
    subrole: stringValue(subroleResult.1),
    roleDescription: stringValue(roleDescriptionResult.1),
    identifier: stringValue(identifierResult.1),
    title: stringValue(titleResult.1),
    description: stringValue(descriptionResult.1),
    value: stringValue(valueResult.1),
    help: stringValue(helpResult.1),
    enabled: boolValue(enabledResult.1),
    focused: boolValue(focusedResult.1),
    childCount: childElements.count,
    path: path,
    windowNumber: windowNumber(for: element),
    diagnosticCode: errors.first.map(diagnosticCode),
    children: children
  )
}

private func runningApplication(bundleIdentifier: String) -> NSRunningApplication? {
  NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
    .first(where: { !$0.isTerminated })
}

private func capture(bundleIdentifier: String, depth: Int) throws -> AXSnapshot {
  guard AXIsProcessTrusted() else {
    throw AXDumpError.accessibilityDenied
  }
  guard let application = runningApplication(bundleIdentifier: bundleIdentifier) else {
    throw AXDumpError.applicationNotRunning(bundleIdentifier)
  }

  let appElement = AXUIElementCreateApplication(application.processIdentifier)
  let windowsResult = copyAttribute(appElement, kAXWindowsAttribute as String)
  guard windowsResult.0 == .success else {
    throw AXDumpError.applicationLookupFailed(bundleIdentifier)
  }

  let windows = childrenValue(windowsResult.1)
  var count = 0
  let root = try node(
    from: appElement,
    path: "application",
    remainingDepth: 0,
    elementCount: &count
  )
  let rootWithWindows = AXNode(
    role: root.role,
    subrole: root.subrole,
    roleDescription: root.roleDescription,
    identifier: root.identifier,
    title: root.title,
    description: root.description,
    value: root.value,
    help: root.help,
    enabled: root.enabled,
    focused: root.focused,
    childCount: windows.count,
    path: root.path,
    windowNumber: root.windowNumber,
    diagnosticCode: root.diagnosticCode,
    children: try windows.enumerated().map { index, window in
      try node(
        from: window,
        path: "application/window-\(index)",
        remainingDepth: max(depth - 1, 0),
        elementCount: &count
      )
    }
  )

  return AXSnapshot(
    schemaVersion: 1,
    capturedAt: Date(),
    bundleIdentifier: bundleIdentifier,
    processIdentifier: application.processIdentifier,
    root: rootWithWindows
  )
}

private func emitJSON<T: Encodable>(_ value: T, to outputPath: String?) throws {
  let encoder = JSONEncoder()
  encoder.dateEncodingStrategy = .iso8601
  encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
  let data = try encoder.encode(value)
  guard let outputPath else {
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
    return
  }
  do {
    try data.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
  } catch {
    throw AXDumpError.outputFailed(error.localizedDescription)
  }
}

private func flattened(_ node: AXNode, into values: inout [String: AXNode]) {
  values[node.path] = node
  for child in node.children {
    flattened(child, into: &values)
  }
}

private func diff(_ firstPath: String, _ secondPath: String) throws -> DiffResult {
  let decoder = JSONDecoder()
  decoder.dateDecodingStrategy = .iso8601
  let first = try decoder.decode(
    AXSnapshot.self, from: Data(contentsOf: URL(fileURLWithPath: firstPath)))
  let second = try decoder.decode(
    AXSnapshot.self, from: Data(contentsOf: URL(fileURLWithPath: secondPath)))

  var firstNodes = [String: AXNode]()
  var secondNodes = [String: AXNode]()
  flattened(first.root, into: &firstNodes)
  flattened(second.root, into: &secondNodes)

  let firstPaths = Set(firstNodes.keys)
  let secondPaths = Set(secondNodes.keys)
  let added = secondPaths.subtracting(firstPaths).sorted()
  let removed = firstPaths.subtracting(secondPaths).sorted()
  let changed = firstPaths.intersection(secondPaths).filter {
    firstNodes[$0] != secondNodes[$0]
  }.sorted()
  return DiffResult(added: added, removed: removed, changed: changed)
}

private final class WatchContext {
  let bundleIdentifier: String
  let processIdentifier: pid_t

  init(bundleIdentifier: String, processIdentifier: pid_t) {
    self.bundleIdentifier = bundleIdentifier
    self.processIdentifier = processIdentifier
  }
}

private func watchCallback(
  _: AXObserver,
  element: AXUIElement,
  notification: CFString,
  refcon: UnsafeMutableRawPointer?
) {
  guard let refcon else {
    return
  }
  let context = Unmanaged<WatchContext>.fromOpaque(refcon).takeUnretainedValue()
  let event = WatchEvent(
    timestamp: Date(),
    bundleIdentifier: context.bundleIdentifier,
    processIdentifier: context.processIdentifier,
    notification: notification as String,
    role: stringValue(copyAttribute(element, kAXRoleAttribute as String).1)
  )
  do {
    try emitJSON(event, to: nil)
  } catch {
    fputs("axdump: watch output failed: \(error)\n", stderr)
  }
}

private func watch(bundleIdentifier: String) throws -> Never {
  guard AXIsProcessTrusted() else {
    throw AXDumpError.accessibilityDenied
  }
  guard let application = runningApplication(bundleIdentifier: bundleIdentifier) else {
    throw AXDumpError.applicationNotRunning(bundleIdentifier)
  }

  let context = WatchContext(
    bundleIdentifier: bundleIdentifier,
    processIdentifier: application.processIdentifier
  )
  var observer: AXObserver?
  let callback: AXObserverCallback = watchCallback
  let createObserver:
    (
      pid_t,
      AXObserverCallback,
      UnsafeMutablePointer<AXObserver?>
    ) -> AXError = AXObserverCreate
  let result = createObserver(
    application.processIdentifier,
    callback,
    &observer
  )
  guard result == .success, let observer else {
    throw AXDumpError.captureFailed("AX_OBSERVER_ATTACH_FAILED_\(result.rawValue)")
  }

  let appElement = AXUIElementCreateApplication(application.processIdentifier)
  let notifications = [
    kAXFocusedWindowChangedNotification,
    kAXWindowCreatedNotification,
    kAXUIElementDestroyedNotification,
    kAXSelectedChildrenChangedNotification,
    kAXValueChangedNotification,
  ]
  for notification in notifications {
    _ = AXObserverAddNotification(
      observer,
      appElement,
      notification as CFString,
      Unmanaged.passUnretained(context).toOpaque()
    )
  }
  CFRunLoopAddSource(
    CFRunLoopGetCurrent(),
    AXObserverGetRunLoopSource(observer),
    .defaultMode
  )
  CFRunLoopRun()
  exit(EXIT_SUCCESS)
}

private func parseOptions() throws -> (mode: String, options: Options, diffPaths: [String]) {
  var options = Options()
  var arguments = Array(CommandLine.arguments.dropFirst())
  if arguments.first == "--diff" {
    arguments.removeFirst()
    guard arguments.count == 2 else {
      throw AXDumpError.usage("Usage: axdump --diff <before.json> <after.json>")
    }
    return ("diff", options, arguments)
  }

  while !arguments.isEmpty {
    let argument = arguments.removeFirst()
    switch argument {
    case "--bundle":
      guard let bundle = arguments.first else {
        throw AXDumpError.usage("--bundle requires a bundle identifier.")
      }
      options.bundleIdentifier = bundle
      arguments.removeFirst()
    case "--depth":
      guard let rawDepth = arguments.first, let depth = Int(rawDepth), depth >= 0 else {
        throw AXDumpError.usage("--depth requires a non-negative integer.")
      }
      options.depth = min(depth, 20)
      arguments.removeFirst()
    case "--out":
      guard let outputPath = arguments.first else {
        throw AXDumpError.usage("--out requires a file path.")
      }
      options.outputPath = outputPath
      arguments.removeFirst()
    case "--watch":
      options.watch = true
    case "--help", "-h":
      throw AXDumpError.usage(
        """
        Usage:
          axdump --bundle <bundle-id> [--depth <n>] [--out <file>]
          axdump --watch --bundle <bundle-id>
          axdump --diff <before.json> <after.json>
        """
      )
    default:
      throw AXDumpError.usage("Unknown argument \(argument). Use --help for usage.")
    }
  }

  guard let bundleIdentifier = options.bundleIdentifier, !bundleIdentifier.isEmpty else {
    throw AXDumpError.usage("--bundle is required.")
  }
  if options.watch, options.outputPath != nil {
    throw AXDumpError.usage("--out cannot be used with --watch.")
  }
  return ("capture", options, [])
}

@main
private struct AXDumpCommand {
  static func main() {
    do {
      let parsed = try parseOptions()
      if parsed.mode == "diff" {
        let result = try diff(parsed.diffPaths[0], parsed.diffPaths[1])
        try emitJSON(result, to: nil)
        return
      }
      guard let bundleIdentifier = parsed.options.bundleIdentifier else {
        throw AXDumpError.usage("--bundle is required.")
      }
      if parsed.options.watch {
        try watch(bundleIdentifier: bundleIdentifier)
      }
      let snapshot = try capture(
        bundleIdentifier: bundleIdentifier,
        depth: parsed.options.depth
      )
      try emitJSON(snapshot, to: parsed.options.outputPath)
    } catch {
      fputs("axdump: \(error)\n", stderr)
      exit(EXIT_FAILURE)
    }
  }
}
