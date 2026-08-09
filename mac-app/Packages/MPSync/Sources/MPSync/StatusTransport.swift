import Foundation
import MPCore

public struct DeviceRegistration: Codable, Equatable, Sendable {
  public let deviceID: UUID
  public let instanceNonce: UUID

  public init(deviceID: UUID, instanceNonce: UUID) {
    self.deviceID = deviceID
    self.instanceNonce = instanceNonce
  }
}

public struct PublishResult: Codable, Equatable, Sendable {
  public let superseded: Bool
  public let lastSeenAt: Date?

  public init(superseded: Bool, lastSeenAt: Date?) {
    self.superseded = superseded
    self.lastSeenAt = lastSeenAt
  }
}

public struct StatusPayload: Codable, Equatable, Sendable {
  public let state: State
  public let callOkay: Bool
  public let overrideMode: State?
  public let overrideExpiresAt: Date?
  public let screenSharing: String?

  public init(
    state: State,
    callOkay: Bool,
    overrideMode: State?,
    overrideExpiresAt: Date?,
    screenSharing: String? = nil
  ) {
    self.state = state
    self.callOkay = callOkay
    self.overrideMode = overrideMode
    self.overrideExpiresAt = overrideExpiresAt
    self.screenSharing = screenSharing
  }
}

public struct ViewerRecord: Codable, Equatable, Sendable {
  public let viewerUserID: UUID
  public let createdAt: Date
  public let revokedAt: Date?

  public init(viewerUserID: UUID, createdAt: Date, revokedAt: Date?) {
    self.viewerUserID = viewerUserID
    self.createdAt = createdAt
    self.revokedAt = revokedAt
  }
}

public protocol StatusTransport: Sendable {
  func ensureSession() async throws
  func registerDevice(recoveryHash: String) async throws -> DeviceRegistration
  func publish(_ payload: StatusPayload, nonce: UUID) async throws -> PublishResult
  func updateDisplayName(_ name: String?) async throws
  func createPairingCode(hash: String) async throws -> UUID
  func rotatePairingCodes() async throws -> Int
  func listViewers() async throws -> [ViewerRecord]
  func revokeViewer(_ id: UUID) async throws
  func deleteViewer(_ id: UUID) async throws
  func revokeAllViewers() async throws -> Int
  func rebindDevice(recoverySecret: String) async throws -> DeviceRegistration
  func deleteDevice() async throws
}
