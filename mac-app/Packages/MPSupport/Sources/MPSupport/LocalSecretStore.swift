import Foundation

public final class LocalSecretStore: SecretStore, @unchecked Sendable {
  public enum StoreError: Error, Equatable, Sendable {
    case invalidData
  }

  private let fileURL: URL
  private let fileManager: FileManager
  private let lock = NSLock()
  // Cached decoded dictionary. The previous implementation re-read the
  // entire plist from disk on every `read`, `save`, and `delete`. The
  // storage is now appended/mutated through an in-memory cache and the
  // file is only touched when the cache is undefined. The cache is
  // invalidated on stale-modified time to detect external writes.
  private var cachedValues: [String: Data]?
  private var cachedAt: Date?

  public init(
    fileURL: URL? = nil,
    fileManager: FileManager = .default
  ) {
    self.fileURL = fileURL ?? Self.defaultFileURL(fileManager: fileManager)
    self.fileManager = fileManager
  }

  public func read(_ key: SecretKey) throws -> CredentialState<Data> {
    lock.lock()
    defer { lock.unlock() }

    let values = try load()
    guard let value = values[key.rawValue] else {
      return .missing
    }
    return .present(value)
  }

  public func save(_ data: Data, for key: SecretKey) throws {
    lock.lock()
    defer { lock.unlock() }

    var values = try load()
    values[key.rawValue] = data
    try persist(values)
  }

  public func delete(_ key: SecretKey) throws {
    lock.lock()
    defer { lock.unlock() }

    var values = try load()
    values.removeValue(forKey: key.rawValue)
    try persist(values)
  }

  private func load() throws -> [String: Data] {
    if let cachedValues,
      let cachedAt,
      let modified = modificationDate(),
      abs(modified.timeIntervalSince(cachedAt)) < 0.5
    {
      return cachedValues
    }

    guard fileManager.fileExists(atPath: fileURL.path) else {
      cachedValues = [:]
      cachedAt = Date()
      return [:]
    }

    let data = try Data(contentsOf: fileURL)
    do {
      let decoded = try PropertyListDecoder().decode([String: Data].self, from: data)
      cachedValues = decoded
      cachedAt = modificationDate() ?? Date()
      return decoded
    } catch {
      // Cached state is now stale; clear it so the next call re-reads the
      // file and we don't keep returning the previous good copy after a
      // malformed write.
      cachedValues = nil
      cachedAt = nil
      throw StoreError.invalidData
    }
  }

  private func modificationDate() -> Date? {
    let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path)
    return attributes?[.modificationDate] as? Date
  }

  private func persist(_ values: [String: Data]) throws {
    guard !values.isEmpty else {
      if fileManager.fileExists(atPath: fileURL.path) {
        try fileManager.removeItem(at: fileURL)
      }
      cachedValues = [:]
      cachedAt = Date()
      return
    }

    let directory = fileURL.deletingLastPathComponent()
    try fileManager.createDirectory(
      at: directory,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )
    try fileManager.setAttributes(
      [.posixPermissions: 0o700],
      ofItemAtPath: directory.path
    )

    let encoder = PropertyListEncoder()
    encoder.outputFormat = .binary
    let data = try encoder.encode(values)
    let temporaryURL = directory.appendingPathComponent(
      ".\(fileURL.lastPathComponent).\(UUID().uuidString).tmp"
    )
    defer {
      if fileManager.fileExists(atPath: temporaryURL.path) {
        try? fileManager.removeItem(at: temporaryURL)
      }
    }

    try data.write(to: temporaryURL, options: .atomic)
    try fileManager.setAttributes(
      [.posixPermissions: 0o600],
      ofItemAtPath: temporaryURL.path
    )
    if fileManager.fileExists(atPath: fileURL.path) {
      _ = try fileManager.replaceItemAt(fileURL, withItemAt: temporaryURL)
    } else {
      try fileManager.moveItem(at: temporaryURL, to: fileURL)
    }
    try fileManager.setAttributes(
      [.posixPermissions: 0o600],
      ofItemAtPath: fileURL.path
    )
    cachedValues = values
    cachedAt = Date()
  }

  private static func defaultFileURL(fileManager: FileManager) -> URL {
    fileManager
      .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("MeetingPulse/secrets.plist")
  }
}
