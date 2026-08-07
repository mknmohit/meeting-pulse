import Foundation
import MPCore

public protocol OverrideFileSystem: Sendable {
  func read(_ url: URL) throws -> Data?
  func atomicWrite(_ data: Data, to url: URL) throws
  func remove(_ url: URL) throws
}

public struct LocalOverrideFileSystem: OverrideFileSystem, Sendable {
  public init() {}

  public func read(_ url: URL) throws -> Data? {
    guard FileManager.default.fileExists(atPath: url.path) else {
      return nil
    }
    return try Data(contentsOf: url)
  }

  public func atomicWrite(_ data: Data, to url: URL) throws {
    let directory = url.deletingLastPathComponent()
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    let temporaryURL = directory.appendingPathComponent(".\(url.lastPathComponent).tmp")
    try data.write(to: temporaryURL, options: .atomic)
    if FileManager.default.fileExists(atPath: url.path) {
      _ = try FileManager.default.replaceItemAt(url, withItemAt: temporaryURL)
    } else {
      try FileManager.default.moveItem(at: temporaryURL, to: url)
    }
  }

  public func remove(_ url: URL) throws {
    guard FileManager.default.fileExists(atPath: url.path) else {
      return
    }
    try FileManager.default.removeItem(at: url)
  }
}

public actor ManualOverrideStore {
  public typealias Publish = @Sendable (ManualOverride?) async -> Void
  public typealias Log = @Sendable (String) -> Void

  private let fileURL: URL
  private let wallClock: any WallClock
  private let monotonic: any Monotonic
  private let fileSystem: any OverrideFileSystem
  private let publish: Publish
  private let log: Log
  private var currentOverride: ManualOverride?
  private var expiryTask: Task<Void, Never>?

  public init(
    fileURL: URL? = nil,
    wallClock: any WallClock = SystemWallClock(),
    monotonic: any Monotonic = SystemMonotonicClock(),
    fileSystem: any OverrideFileSystem = LocalOverrideFileSystem(),
    publish: @escaping Publish = { _ in },
    log: @escaping Log = { _ in }
  ) {
    self.fileURL = fileURL ?? Self.defaultFileURL()
    self.wallClock = wallClock
    self.monotonic = monotonic
    self.fileSystem = fileSystem
    self.publish = publish
    self.log = log
  }

  public var current: ManualOverride? {
    currentOverride
  }

  @discardableResult
  public func load() async -> ManualOverride? {
    cancelExpiryTask()
    do {
      guard let data = try fileSystem.read(fileURL) else {
        currentOverride = nil
        return nil
      }
      let decoder = JSONDecoder()
      decoder.dateDecodingStrategy = .iso8601
      let persisted = try decoder.decode(ManualOverride.self, from: data)
      guard let rebuilt = try rebuild(persisted) else {
        currentOverride = nil
        try discardPersistedFile()
        return nil
      }
      currentOverride = rebuilt
      armExpiry(for: rebuilt)
      return rebuilt
    } catch {
      log("OVERRIDE_FILE_INVALID")
      currentOverride = nil
      try? discardPersistedFile()
      return nil
    }
  }

  @discardableResult
  public func set(
    state: State,
    duration: ManualOverride.Duration
  ) throws -> ManualOverride {
    cancelExpiryTask()
    let createdAt = wallClock.now
    let seconds = duration.seconds
    let expiresAt = seconds.map { createdAt.addingTimeInterval($0) }
    let deadline = seconds.map { monotonic.now().advanced(by: .seconds($0)) }
    let override = try ManualOverride(
      state: state,
      createdAtWall: createdAt,
      expiresAtWall: expiresAt,
      deadline: deadline
    )
    try persist(override)
    currentOverride = override
    armExpiry(for: override)
    return override
  }

  public func clear() throws {
    cancelExpiryTask()
    try fileSystem.remove(fileURL)
    currentOverride = nil
  }

  public func rearmExpiry() {
    if let currentOverride {
      armExpiry(for: currentOverride)
    }
  }

  private func rebuild(_ persisted: ManualOverride) throws -> ManualOverride? {
    guard let expiresAt = persisted.expiresAtWall else {
      return try ManualOverride(
        state: persisted.state,
        createdAtWall: persisted.createdAtWall,
        expiresAtWall: nil,
        deadline: nil
      )
    }

    let remaining = expiresAt.timeIntervalSince(wallClock.now)
    guard remaining > 0 else {
      return nil
    }
    let originalDuration = max(
      persisted.expiresAtWall?.timeIntervalSince(persisted.createdAtWall) ?? remaining,
      0
    )
    let cappedRemaining = min(remaining, originalDuration)
    let deadline = monotonic.now().advanced(by: .seconds(cappedRemaining))
    return try ManualOverride(
      state: persisted.state,
      createdAtWall: persisted.createdAtWall,
      expiresAtWall: expiresAt,
      deadline: deadline
    )
  }

  private func persist(_ override: ManualOverride) throws {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(override)
    try fileSystem.atomicWrite(data, to: fileURL)
  }

  private func discardPersistedFile() throws {
    do {
      try fileSystem.remove(fileURL)
    } catch {
      log("OVERRIDE_FILE_REMOVE_FAILED")
    }
  }

  private func armExpiry(for override: ManualOverride) {
    cancelExpiryTask()
    guard let deadline = override.deadline else {
      return
    }
    let clock = monotonic
    let publish = publish
    let log = log
    expiryTask = Task { [weak self] in
      do {
        try await clock.sleep(until: deadline)
      } catch {
        return
      }
      guard let self else {
        return
      }
      await self.expire(override, publish: publish, log: log)
    }
  }

  private func expire(
    _ expected: ManualOverride,
    publish: Publish,
    log: Log
  ) async {
    guard currentOverride == expected else {
      return
    }
    do {
      try fileSystem.remove(fileURL)
    } catch {
      log("OVERRIDE_FILE_REMOVE_FAILED")
    }
    currentOverride = nil
    await publish(nil)
  }

  private func cancelExpiryTask() {
    expiryTask?.cancel()
    expiryTask = nil
  }

  private static func defaultFileURL() -> URL {
    FileManager.default
      .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("MeetingPulse/override.json")
  }
}
