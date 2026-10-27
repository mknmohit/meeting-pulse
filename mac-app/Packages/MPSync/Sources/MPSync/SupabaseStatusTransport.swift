import Auth
import Foundation
import MPCore
import MPSupport
import PostgREST

public final class SupabaseStatusTransport: StatusTransport, @unchecked Sendable {
  public enum TransportError: Error, Equatable, Sendable {
    case identityLost
    case recoveryHashConflict
    case invalidRemoteResponse
    case remoteFailure(String)
    /// The device row is no longer bound to the signed-in identity, so
    /// `publish_status` cannot resolve `mp_current_device_id()`.
    case deviceNotRegistered
  }

  private let client: SupabaseClientLite
  private let turnstile: TurnstileGate
  private let sessionBootstrap: AuthSessionBootstrap

  public init(
    configuration: AppConfiguration,
    turnstile: TurnstileGate,
    secrets: any SecretStore = LocalSecretStore()
  ) {
    let storage = MeetingPulseAuthStorage(secrets: secrets)
    client = SupabaseClientLite(
      supabaseURL: configuration.supabaseURL,
      supabaseKey: configuration.supabaseAnonKey,
      authStorage: storage,
      authStorageKey: MeetingPulseAuthStorage.storageKey
    )
    self.turnstile = turnstile
    sessionBootstrap = AuthSessionBootstrap(
      auth: SupabaseAuthSessionProvider(auth: client.auth),
      turnstile: turnstile
    )
  }

  init(
    client: SupabaseClientLite,
    turnstile: TurnstileGate,
    secrets: any SecretStore = LocalSecretStore()
  ) {
    self.client = client
    self.turnstile = turnstile
    sessionBootstrap = AuthSessionBootstrap(
      auth: SupabaseAuthSessionProvider(auth: client.auth),
      turnstile: turnstile
    )
  }

  public func ensureSession() async throws {
    try await sessionBootstrap.ensureSession()
  }

  public func registerDevice(recoveryHash: String) async throws -> DeviceRegistration {
    try await ensureSession()
    let params: JSONObject = ["p_recovery_hash": .string(recoveryHash)]
    let response: RegisterResponse
    do {
      response = try await client.rpc("register_device", params: params)
        .single()
        .execute()
        .value
    } catch let error as PostgrestError
      where Self.isRecoveryHashConflict(code: error.code, message: error.message) {
      throw TransportError.recoveryHashConflict
    } catch let error as PostgrestError where error.code == "23503" {
      throw TransportError.identityLost
    }
    return DeviceRegistration(
      deviceID: response.deviceID,
      instanceNonce: response.instanceNonce
    )
  }

  static func isRecoveryHashConflict(code: String?, message: String) -> Bool {
    code == "23505" && message.contains("devices_recovery_hash_key")
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
    let response: PublishResponse
    do {
      response = try await client.rpc("publish_status", params: params)
        .single()
        .execute()
        .value
    } catch let error as PostgrestError where error.code == "42704" {
      // `mp_current_device_id()` resolved to NULL, which means the device is
      // not bound to the current identity. Retrying the same publish can never
      // succeed, so the caller is told to re-register the device instead.
      throw TransportError.deviceNotRegistered
    }
    return PublishResult(
      superseded: response.superseded,
      lastSeenAt: response.lastSeenAt
    )
  }

  public func updateDisplayName(_ name: String?) async throws {
    try await ensureSession()
    let params: JSONObject = ["p_display_name": name.map(AnyJSON.string) ?? .null]
    _ = try await client.rpc("update_device_profile", params: params).execute().value
  }

  public func createPairingCode(hash: String) async throws -> UUID {
    try await ensureSession()
    let params: JSONObject = ["p_code_hash": .string(hash)]
    let result: UUID = try await client.rpc("create_pairing_code", params: params)
      .single()
      .execute()
      .value
    return result
  }

  public func rotatePairingCodes() async throws -> Int {
    try await ensureSession()
    let result: Int = try await client.rpc("rotate_pairing_codes").single().execute().value
    return result
  }

  public func listViewers() async throws -> [ViewerRecord] {
    try await ensureSession()
    let result: [ViewerRecord] = try await client.rpc("list_viewers").execute().value
    return result
  }

  public func revokeViewer(_ id: UUID) async throws {
    try await ensureSession()
    let params: JSONObject = ["p_viewer_user_id": .string(id.uuidString)]
    _ = try await client.rpc("revoke_viewer", params: params).execute().value
  }

  public func deleteViewer(_ id: UUID) async throws {
    try await ensureSession()
    let params: JSONObject = ["p_viewer_user_id": .string(id.uuidString)]
    _ = try await client.rpc("delete_viewer", params: params).execute().value
  }

  public func revokeAllViewers() async throws -> Int {
    try await ensureSession()
    let result: Int = try await client.rpc("revoke_all_viewers").single().execute().value
    return result
  }

  public func rebindDevice(recoverySecret: String) async throws -> DeviceRegistration {
    _ = try await turnstile.token(for: .recoveryRebind)
    try await ensureSession()
    let params: JSONObject = ["p_recovery_secret": .string(recoverySecret)]
    let response: RebindResponse = try await client.rpc("rebind_device", params: params)
      .single()
      .execute()
      .value
    guard response.ok != false,
      let deviceID = response.deviceID,
      let instanceNonce = response.instanceNonce
    else {
      throw TransportError.remoteFailure(response.reason ?? "rebind_failed")
    }
    return DeviceRegistration(deviceID: deviceID, instanceNonce: instanceNonce)
  }

  public func deleteDevice() async throws {
    try await ensureSession()
    _ = try await client.rpc("delete_device").execute().value
  }

  private static func iso8601String(from date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
  }
}

/// Lightweight replacement for `SupabaseClient` using only `Auth` + `PostgREST`.
/// Replicates the small subset of the umbrella API used by `SupabaseStatusTransport`.
struct SupabaseClientLite: Sendable {
  let auth: AuthClient
  private let postgrest: PostgrestClient
  private let supabaseKey: String

  init(
    supabaseURL: URL,
    supabaseKey: String,
    authStorage: any AuthLocalStorage,
    authStorageKey: String
  ) {
    self.supabaseKey = supabaseKey
    let headers: [String: String] = [
      "Authorization": "Bearer \(supabaseKey)",
      "Apikey": supabaseKey,
    ]
    let authClient = AuthClient(
      url: supabaseURL.appendingPathComponent("/auth/v1"),
      headers: headers,
      storageKey: authStorageKey,
      localStorage: authStorage
    )
    auth = authClient
    postgrest = PostgrestClient(
      url: supabaseURL.appendingPathComponent("/rest/v1"),
      headers: headers,
      fetch: { request in
        var request = request
        let token = try await authClient.session.accessToken
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try await URLSession.shared.data(for: request)
      }
    )
  }

  func rpc(
    _ fn: String,
    params: some Encodable,
    count: CountOption? = nil
  ) throws -> PostgrestFilterBuilder {
    try postgrest.rpc(fn, params: params, count: count)
  }

  func rpc(
    _ fn: String,
    count: CountOption? = nil
  ) throws -> PostgrestFilterBuilder {
    try postgrest.rpc(fn, count: count)
  }
}

protocol AuthSessionProvider: Sendable {
  func requireValidSession() async throws
  /// Reports whether a session is still stored locally.
  ///
  /// A stored session means the device already belongs to an identity, so a
  /// failed refresh is a transient condition rather than a reason to mint a
  /// brand new identity.
  func hasStoredSession() async -> Bool
  func signInAnonymously(captchaToken: String) async throws
}

struct AuthSessionBootstrap: Sendable {
  private let auth: any AuthSessionProvider
  private let turnstile: TurnstileGate

  init(auth: any AuthSessionProvider, turnstile: TurnstileGate) {
    self.auth = auth
    self.turnstile = turnstile
  }

  func ensureSession() async throws {
    do {
      try await auth.requireValidSession()
    } catch {
      // Signing in anonymously here would create a *new* identity. The
      // previously paired device would then be orphaned: `mp_current_device_id()`
      // resolves to NULL and every publish fails with `no_device`. A stored
      // session whose refresh failed is a transient condition (offline, or a
      // failed refresh request), so the error is surfaced instead.
      guard await auth.hasStoredSession() == false else {
        throw error
      }
      let token = try await turnstile.token(for: .firstRegistration)
      try await auth.signInAnonymously(captchaToken: token)
      try await auth.requireValidSession()
    }
  }
}

private struct SupabaseAuthSessionProvider: AuthSessionProvider {
  let auth: AuthClient

  func requireValidSession() async throws {
    _ = try await auth.session
  }

  func hasStoredSession() async -> Bool {
    auth.currentSession != nil
  }

  func signInAnonymously(captchaToken: String) async throws {
    _ = try await auth.signInAnonymously(captchaToken: captchaToken)
  }
}

struct MeetingPulseAuthStorage: AuthLocalStorage {
  static let storageKey = "meetingpulse.auth"

  let secrets: any SecretStore

  func store(key: String, value: Data) throws {
    guard key == Self.storageKey else {
      return
    }
    try secrets.save(value, for: .supabaseRefreshToken)
  }

  func retrieve(key: String) throws -> Data? {
    guard key == Self.storageKey else {
      return nil
    }
    switch try secrets.read(.supabaseRefreshToken) {
    case .present(let data):
      return data
    case .missing:
      return nil
    case .temporarilyUnavailable:
      throw AuthStorageError.temporarilyUnavailable
    }
  }

  func remove(key: String) throws {
    guard key == Self.storageKey else {
      return
    }
    try secrets.delete(.supabaseRefreshToken)
  }
}

private enum AuthStorageError: Error {
  case temporarilyUnavailable
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

struct RebindResponse: Decodable {
  let ok: Bool?
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
