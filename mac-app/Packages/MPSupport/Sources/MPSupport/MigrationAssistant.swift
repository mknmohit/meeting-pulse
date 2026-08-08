import Foundation

public struct MigrationAssistant {
  public struct Result: Equatable, Sendable {
    public let migrated: Bool
    public let copiedPairingFile: Bool
    public let preservedTelemetryIdentity: Bool

    public init(
      migrated: Bool,
      copiedPairingFile: Bool,
      preservedTelemetryIdentity: Bool
    ) {
      self.migrated = migrated
      self.copiedPairingFile = copiedPairingFile
      self.preservedTelemetryIdentity = preservedTelemetryIdentity
    }
  }

  private let defaults: UserDefaults
  private let applicationSupport: URL
  private let fileManager: FileManager
  private let secrets: (any SecretStore)?

  public init(
    defaults: UserDefaults = .standard,
    applicationSupport: URL? = nil,
    fileManager: FileManager = .default,
    secrets: (any SecretStore)? = nil
  ) {
    self.defaults = defaults
    self.applicationSupport = applicationSupport
      ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("MeetingPulse", isDirectory: true)
    self.fileManager = fileManager
    self.secrets = secrets
  }

  @discardableResult
  public func migrateIfNeeded() throws -> Result {
    let sentinel = applicationSupport.appendingPathComponent(".migrated")
    if fileManager.fileExists(atPath: sentinel.path) {
      return Result(migrated: false, copiedPairingFile: false, preservedTelemetryIdentity: false)
    }

    try fileManager.createDirectory(
      at: applicationSupport,
      withIntermediateDirectories: true
    )

    if let displayName = defaults.string(forKey: "displayName") {
      defaults.set(displayName, forKey: "owner.displayName")
    }
    if let recoveryPhrase = defaults.string(forKey: "recoveryPhrase"),
       let secrets {
      try secrets.save(Data(recoveryPhrase.utf8), for: .deviceRecoveryPhrase)
    }

    var copiedPairingFile = false
    let legacyPairings = applicationSupport.deletingLastPathComponent()
      .appendingPathComponent("pairings.json")
    let migratedPairings = applicationSupport.appendingPathComponent("pairings.json")
    if fileManager.fileExists(atPath: legacyPairings.path),
       !fileManager.fileExists(atPath: migratedPairings.path) {
      try fileManager.copyItem(at: legacyPairings, to: migratedPairings)
      copiedPairingFile = true
    }

    let telemetryIdentity = defaults.string(forKey: "telemetry.anonKey")
    if let telemetryIdentity {
      defaults.set(telemetryIdentity, forKey: "publish.anonKey")
    }

    try Data("1".utf8).write(to: sentinel, options: .atomic)
    return Result(
      migrated: true,
      copiedPairingFile: copiedPairingFile,
      preservedTelemetryIdentity: telemetryIdentity != nil
    )
  }
}
