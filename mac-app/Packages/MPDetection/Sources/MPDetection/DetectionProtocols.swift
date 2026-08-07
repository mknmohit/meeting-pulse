import AppKit
import ApplicationServices
import CoreGraphics
import MPCore

public struct RunningApp: Equatable, Sendable {
  public let processIdentifier: pid_t
  public let bundleIdentifier: String

  public init(processIdentifier: pid_t, bundleIdentifier: String) {
    self.processIdentifier = processIdentifier
    self.bundleIdentifier = bundleIdentifier
  }
}

public struct AXEvent: Equatable, Sendable {
  public let processIdentifier: pid_t
  public let notification: String

  public init(processIdentifier: pid_t, notification: String) {
    self.processIdentifier = processIdentifier
    self.notification = notification
  }
}

public protocol AXElementTree: Sendable {
  func snapshot(
    pid: pid_t,
    maxDepth: Int,
    maxElements: Int
  ) async throws -> AXSnapshot
}

public protocol AppDiscovery: Sendable {
  func runningApps(bundleIDs: [String]) -> [RunningApp]
}

public protocol PermissionProbe: Sendable {
  var isTrusted: Bool { get }
}

public protocol AXEventSource: Sendable {
  var events: AsyncStream<AXEvent> { get }
  func observe(pid: pid_t, notifications: [String]) async throws
  func stopObserving(pid: pid_t) async
}

public struct WorkspaceAppDiscovery: AppDiscovery {
  public init() {}

  public func runningApps(bundleIDs: [String]) -> [RunningApp] {
    bundleIDs.flatMap { bundleID in
      NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        .filter { !$0.isTerminated }
        .map {
          RunningApp(
            processIdentifier: $0.processIdentifier,
            bundleIdentifier: bundleID
          )
        }
    }
  }
}

public struct AccessibilityPermissionProbe: PermissionProbe {
  public init() {}

  public var isTrusted: Bool {
    AXIsProcessTrusted()
  }
}

public protocol MeetingDetector: Actor {
  nonisolated var sourceIdentifier: SourceID { get }
  func start() async
  func stop() async
  func invalidate() async
  func requestSample() async
  var currentObservation: SourceObservation { get }
  var health: DetectorHealth { get }
  var observationStream: AsyncStream<SourceObservation> { get }
}
