import Foundation
import MPCore
import MPSupport
import Supabase

public final class SupabaseStatusTransport: StatusTransport, @unchecked Sendable {
  public enum TransportError: Error, Equatable, Sendable {
    case identityLost
    case invalidRemoteResponse
    case remoteFailure(String)
  }

  private let client: SupabaseClient
  private let turnstile: TurnstileGate

  public init(
    configuration: AppConfiguration,
    turnstile: TurnstileGate
  ) {
    let storage = KeychainLocalStorage(service: "com.techdevix.meetingpulse.auth")
    let options = SupabaseClientOptions(
      auth: .init(storage: storage, storageKey: "meetingpulse.auth")
    )
    client = SupabaseClient(
      supabaseURL: configuration.supabaseURL,
      supabaseKey: configuration.supabaseAnonKey,
      options: options
    )
    self.turnstile = turnstile
  }

  public init(client: SupabaseClient, turnstile: TurnstileGate) {
    self.client = client
    self.turnstile = turnstile
  }

  public func ensureSession() async throws {
    if client.auth.currentSession != nil {
      return
    }
    do {
      _ = try await client.auth.session
      return
    } catch {
      let token = try await turnstile.token(for: .firstRegistration)
      do {
        _ = try await client.auth.signInAnonymously(captchaToken: token)
      } catch {
        throw TransportError.identityLost
      }
    }
  }

  public func registerDevice(recoveryHash: String) async throws -> DeviceRegistration {
    try await ensureSession()
    let params: JSONObject = ["p_recovery_hash": .string(recoveryHash)]
    let builder = try client.rpc("register_device", params: params)
    let response: RegisterResponse = try await builder.single().execute().value
    return DeviceRegistration(
      deviceID: response.deviceID,
      instanceNonce: response.instanceNonce
    )
  }

  public func publish(_ payload: StatusPayload, nonce: UUID) async throws -> PublishResult {
    try await ensureSession()
    let params: JSONObject = [
      "p_state": .string(payload.state.rawValue),
      "p_call_okay": .bool(payload.callOkay),
      "p_instance_nonce": .string(nonce.uuidString),
      "p_override_mode": payload.overrideMode.map { .string($0.rawValue) } ?? .null,
      "p_override_expires_at": payload.overrideExpiresAt.map {
        .string(Self.iso8601String(from: $0))
      } ?? .null,
      "p_screen_sharing": payload.screenSharing.map { .string($0) } ?? .null,
    ]
    let builder = try client.rpc("publish_status", params: params)
    let response: PublishResponse = try await builder.single().execute().value
    return PublishResult(
      superseded: response.superseded,
      lastSeenAt: response.lastSeenAt
    )
  }

  public func updateDisplayName(_ name: String?) async throws {
    try await ensureSession()
    let params: JSONObject = ["p_display_name": name.map(AnyJSON.string) ?? .null]
    let builder = try client.rpc("update_device_profile", params: params)
    try await builder.execute()
  }

  public func createPairingCode(hash: String) async throws -> UUID {
    try await ensureSession()
    let params: JSONObject = ["p_code_hash": .string(hash)]
    let builder = try client.rpc("create_pairing_code", params: params)
    return try await builder.single().execute().value
  }

  public func rotatePairingCodes() async throws -> Int {
    try await ensureSession()
    let builder = try client.rpc("rotate_pairing_codes")
    return try await builder.single().execute().value
  }

  public func listViewers() async throws -> [ViewerRecord] {
    try await ensureSession()
    let builder = try client.rpc("list_viewers")
    return try await builder.execute().value
  }

  public func revokeViewer(_ id: UUID) async throws {
    try await ensureSession()
    let params: JSONObject = ["p_viewer_user_id": .string(id.uuidString)]
    let builder = try client.rpc("revoke_viewer", params: params)
    try await builder.execute()
  }

  public func revokeAllViewers() async throws -> Int {
    try await ensureSession()
    let builder = try client.rpc("revoke_all_viewers")
    return try await builder.single().execute().value
  }

  public func rebindDevice(recoverySecret: String) async throws -> DeviceRegistration {
    _ = try await turnstile.token(for: .recoveryRebind)
    try await ensureSession()
    let params: JSONObject = ["p_recovery_secret": .string(recoverySecret)]
    let builder = try client.rpc("rebind_device", params: params)
    let response: RebindResponse = try await builder.single().execute().value
    guard response.ok, let deviceID = response.deviceID, let instanceNonce = response.instanceNonce
    else {
      throw TransportError.remoteFailure(response.reason ?? "rebind_failed")
    }
    return DeviceRegistration(deviceID: deviceID, instanceNonce: instanceNonce)
  }

  public func deleteDevice() async throws {
    try await ensureSession()
    let builder = try client.rpc("delete_device")
    try await builder.execute()
  }

  private static func iso8601String(from date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
  }
}

private struct RegisterResponse: Decodable {
  let deviceID: UUID
  let instanceNonce: UUID

  enum CodingKeys: String, CodingKey {
    case deviceID = "device_id"
    case instanceNonce = "instance_nonce"
  }
}

private struct PublishResponse: Decodable {
  let superseded: Bool
  let lastSeenAt: Date?

  enum CodingKeys: String, CodingKey {
    case superseded
    case lastSeenAt = "last_seen_at"
  }
}

private struct RebindResponse: Decodable {
  let ok: Bool
  let reason: String?
  let deviceID: UUID?
  let instanceNonce: UUID?

  enum CodingKeys: String, CodingKey {
    case ok
    case reason
    case deviceID = "device_id"
    case instanceNonce = "instance_nonce"
  }
}
