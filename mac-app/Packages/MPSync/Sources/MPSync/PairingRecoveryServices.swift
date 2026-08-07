import Foundation
import MPCore
import MPSupport

public struct PairingCodeResult: Equatable, Sendable {
  public let rawCode: String
  public let displayCode: String
  public let remoteCodeID: UUID

  public init(rawCode: String, remoteCodeID: UUID) {
    self.rawCode = rawCode
    displayCode = PairingCodeFormat.display(rawCode)
    self.remoteCodeID = remoteCodeID
  }
}

public struct RecoveryRegistration: Equatable, Sendable {
  public let phrase: String
  public let registration: DeviceRegistration

  public init(phrase: String, registration: DeviceRegistration) {
    self.phrase = phrase
    self.registration = registration
  }
}

public struct PairingService: Sendable {
  private let transport: any StatusTransport

  public init(transport: any StatusTransport) {
    self.transport = transport
  }

  public func createCode() async throws -> PairingCodeResult {
    let raw = CrockfordBase32.generate(characters: PairingCodeFormat.length)
    let hash = CrockfordBase32.sha256Hex(CrockfordBase32.normalize(raw))
    let remoteID = try await transport.createPairingCode(hash: hash)
    return PairingCodeResult(rawCode: raw, remoteCodeID: remoteID)
  }
}

public struct RecoveryService: Sendable {
  private let transport: any StatusTransport
  private let secrets: any SecretStore

  public init(
    transport: any StatusTransport,
    secrets: any SecretStore
  ) {
    self.transport = transport
    self.secrets = secrets
  }

  public func registerDevice() async throws -> RecoveryRegistration {
    let rawPhrase = CrockfordBase32.generate(characters: RecoveryPhraseFormat.length)
    let normalized = CrockfordBase32.normalize(rawPhrase)
    try secrets.save(Data(rawPhrase.utf8), for: .deviceRecoveryPhrase)
    let registration = try await transport.registerDevice(
      recoveryHash: CrockfordBase32.sha256Hex(normalized)
    )
    try save(registration)
    return RecoveryRegistration(
      phrase: RecoveryPhraseFormat.display(rawPhrase),
      registration: registration
    )
  }

  public func rebindDevice(recoverySecret: String) async throws -> DeviceRegistration {
    let registration = try await transport.rebindDevice(recoverySecret: recoverySecret)
    try save(registration)
    return registration
  }

  private func save(_ registration: DeviceRegistration) throws {
    try secrets.save(
      Data(registration.deviceID.uuidString.utf8),
      for: .deviceID
    )
    try secrets.save(
      Data(registration.instanceNonce.uuidString.utf8),
      for: .deviceInstanceNonce
    )
  }
}
