import Foundation
import MPCore
import MPSupport

public struct PairingCodeResult: Equatable, Sendable {
  public let rawCode: String
  public let displayCode: String
  public let remoteCodeID: UUID?

  public init(rawCode: String, remoteCodeID: UUID? = nil) {
    self.rawCode = rawCode
    displayCode = PairingCodeFormat.display(rawCode)
    self.remoteCodeID = remoteCodeID
  }
}

public enum PairingServiceError: Error, Equatable, Sendable {
  case invalidStoredCode
  case secretStoreUnavailable
  case invalidViewerOrigin
}

public enum RecoveryServiceError: Error, Equatable, Sendable {
  case invalidStoredPhrase
  case secretStoreUnavailable
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
  private let secrets: any SecretStore

  public init(
    transport: any StatusTransport,
    secrets: any SecretStore
  ) {
    self.transport = transport
    self.secrets = secrets
  }

  public func createCode() async throws -> PairingCodeResult {
    let raw = CrockfordBase32.generate(characters: PairingCodeFormat.length)
    let hash = CrockfordBase32.sha256Hex(CrockfordBase32.normalize(raw))
    let remoteID = try await transport.createPairingCode(hash: hash)
    try secrets.save(Data(raw.utf8), for: .pairingCode)
    return PairingCodeResult(rawCode: raw, remoteCodeID: remoteID)
  }

  public func storedCode() throws -> PairingCodeResult? {
    switch try secrets.read(.pairingCode) {
    case .missing:
      return nil
    case .temporarilyUnavailable:
      throw PairingServiceError.secretStoreUnavailable
    case .present(let data):
      guard
        let value = String(data: data, encoding: .utf8),
        CrockfordBase32.normalize(value).count == PairingCodeFormat.length
      else {
        throw PairingServiceError.invalidStoredCode
      }
      return PairingCodeResult(rawCode: CrockfordBase32.normalize(value))
    }
  }

  public func deleteStoredCode() throws {
    try secrets.delete(.pairingCode)
  }

  public func link(
    for code: PairingCodeResult,
    viewerOrigin: URL
  ) throws -> URL {
    guard
      var components = URLComponents(
        url: viewerOrigin,
        resolvingAgainstBaseURL: false
      )
    else {
      throw PairingServiceError.invalidViewerOrigin
    }
    components.fragment = "code=\(CrockfordBase32.normalize(code.rawCode))"
    guard let link = components.url else {
      throw PairingServiceError.invalidViewerOrigin
    }
    return link
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

  public func registerStoredDevice() async throws -> DeviceRegistration? {
    switch try secrets.read(.deviceRecoveryPhrase) {
    case .missing:
      return nil
    case .temporarilyUnavailable:
      throw RecoveryServiceError.secretStoreUnavailable
    case .present(let data):
      let rawPhrase = String(decoding: data, as: UTF8.self)
      let normalized = CrockfordBase32.normalize(rawPhrase)
      guard normalized.count == RecoveryPhraseFormat.length else {
        throw RecoveryServiceError.invalidStoredPhrase
      }
      let registration = try await transport.registerDevice(
        recoveryHash: CrockfordBase32.sha256Hex(normalized)
      )
      try save(registration)
      return registration
    }
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
