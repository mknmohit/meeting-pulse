import AppKit
import Darwin
import Foundation
import ServiceManagement

public struct InstallLocation: Sendable {
  public init() {}

  public func isValid(bundleURL: URL = Bundle.main.bundleURL) -> Bool {
    let path = bundleURL.standardizedFileURL.path
    return path.hasPrefix("/Applications/")
      && !path.contains("/AppTranslocation/")
      && bundleURL.pathExtension == "app"
  }

  public func openApplicationsFolder() {
    NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications"))
  }
}

public struct LoginItem: Sendable {
  public init() {}

  @discardableResult
  public func register() throws -> SMAppService.Status {
    let service = SMAppService.mainApp
    try service.register()
    return service.status
  }

  public func unregister() throws {
    try SMAppService.mainApp.unregister()
  }
}

public final class SingleInstanceLock: @unchecked Sendable {
  public enum LockError: Error, Equatable, Sendable {
    case unavailable
    case openFailed(Int32)
  }

  private let descriptor: Int32

  public init(
    url: URL = FileManager.default
      .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("MeetingPulse/instance.lock")
  ) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    let descriptor = Darwin.open(url.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
    guard descriptor >= 0 else {
      throw LockError.openFailed(errno)
    }
    guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
      close(descriptor)
      throw LockError.unavailable
    }
    self.descriptor = descriptor
  }

  deinit {
    _ = flock(descriptor, LOCK_UN)
    close(descriptor)
  }
}
