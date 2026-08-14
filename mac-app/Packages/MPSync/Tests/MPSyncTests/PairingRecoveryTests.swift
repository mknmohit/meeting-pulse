import Foundation
import MPCore
import MPSupport
import Testing

@testable import MPSync

struct PairingRecoveryTests {
  @Test
  func pairingServiceHashesOnlyTheNormalizedCode() async throws {
    let transport = FakeTransport()
    let secrets = InMemorySecrets()
    let service = PairingService(transport: transport, secrets: secrets)
    let result = try await service.createCode()

    #expect(result.rawCode.count == PairingCodeFormat.length)
    #expect(result.displayCode == result.rawCode)
    #expect(
      transport.createdPairingHash
        == CrockfordBase32.sha256Hex(
          CrockfordBase32.normalize(result.rawCode)
        ))
    #expect(try service.storedCode()?.rawCode == result.rawCode)
    #expect(try service.storedCode()?.displayCode == result.displayCode)
  }

  @Test
  func pairingServiceBuildsFragmentLink() async throws {
    let transport = FakeTransport()
    let secrets = InMemorySecrets()
    let service = PairingService(transport: transport, secrets: secrets)
    let result = try await service.createCode()

    let link = try service.link(
      for: result,
      viewerOrigin: URL(string: "https://viewer.example.com/")!
    )

    #expect(link.fragment == "code=\(result.rawCode)")
  }

  @Test
  func recoveryRegistrationStoresPhraseAndDeviceIdentity() async throws {
    let transport = FakeTransport()
    let secrets = InMemorySecrets()
    let service = RecoveryService(transport: transport, secrets: secrets)
    let result = try await service.registerDevice()

    #expect(result.phrase.count == RecoveryPhraseFormat.length + 5)
    #expect(secrets.values[.deviceRecoveryPhrase] != nil)
    #expect(secrets.values[.deviceID] != nil)
    #expect(secrets.values[.deviceInstanceNonce] != nil)
  }

  @Test
  func storedRecoveryPhraseReRegistersTheExistingDevice() async throws {
    let transport = FakeTransport()
    let secrets = InMemorySecrets()
    try secrets.save(
      Data(String(repeating: "A", count: RecoveryPhraseFormat.length).utf8),
      for: .deviceRecoveryPhrase
    )
    let service = RecoveryService(transport: transport, secrets: secrets)

    let registration = try await service.registerStoredDevice()

    #expect(registration == transport.registration)
    #expect(secrets.values[.deviceID] != nil)
    #expect(secrets.values[.deviceInstanceNonce] != nil)
  }

  @Test
  func storedRecoveryPhraseRebindsAfterRecoveryHashConflict() async throws {
    let transport = FakeTransport()
    transport.shouldThrowRecoveryHashConflict = true
    let secrets = InMemorySecrets()
    let rawPhrase = String(repeating: "A", count: RecoveryPhraseFormat.length)
    try secrets.save(
      Data(rawPhrase.utf8),
      for: .deviceRecoveryPhrase
    )
    let service = RecoveryService(transport: transport, secrets: secrets)

    let registration = try await service.registerStoredDevice()

    #expect(registration == transport.registration)
    #expect(transport.reboundSecret == rawPhrase)
    #expect(secrets.values[.deviceID] != nil)
    #expect(secrets.values[.deviceInstanceNonce] != nil)
  }

  @Test
  func recoveryHashConflictMatcherRequiresTheExpectedPostgresError() {
    #expect(
      SupabaseStatusTransport.isRecoveryHashConflict(
        code: "23505",
        message: #"duplicate key value violates unique constraint "devices_recovery_hash_key""#
      )
    )
    #expect(
      !SupabaseStatusTransport.isRecoveryHashConflict(
        code: "23505",
        message: #"duplicate key value violates unique constraint "devices_one_active_per_owner""#
      )
    )
    #expect(
      !SupabaseStatusTransport.isRecoveryHashConflict(
        code: "23503",
        message: #"duplicate key value violates unique constraint "devices_recovery_hash_key""#
      )
    )
  }

  @Test
  func rebindResponseAcceptsTheSuccessfulRpcShape() throws {
    let deviceID = "00000000-0000-0000-0000-000000000001"
    let instanceNonce = "00000000-0000-0000-0000-000000000002"
    let data = Data(
      """
      {"device_id":"\(deviceID)","instance_nonce":"\(instanceNonce)"}
      """.utf8
    )

    let response = try JSONDecoder().decode(RebindResponse.self, from: data)

    #expect(response.ok == nil)
    #expect(response.deviceID == UUID(uuidString: deviceID))
    #expect(response.instanceNonce == UUID(uuidString: instanceNonce))
  }
}

private final class FakeTransport: StatusTransport, @unchecked Sendable {
  let registration = DeviceRegistration(
    deviceID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
    instanceNonce: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
  )
  var createdPairingHash: String?
  var shouldThrowRecoveryHashConflict = false
  var reboundSecret: String?

  func ensureSession() async throws {}

  func registerDevice(recoveryHash: String) async throws -> DeviceRegistration {
    if shouldThrowRecoveryHashConflict {
      throw SupabaseStatusTransport.TransportError.recoveryHashConflict
    }
    return registration
  }

  func publish(_: StatusPayload, nonce: UUID) async throws -> PublishResult {
    PublishResult(superseded: false, lastSeenAt: Date())
  }

  func updateDisplayName(_: String?) async throws {}

  func createPairingCode(hash: String) async throws -> UUID {
    createdPairingHash = hash
    return registration.deviceID
  }

  func rotatePairingCodes() async throws -> Int { 0 }
  func listViewers() async throws -> [ViewerRecord] { [] }
  func revokeViewer(_: UUID) async throws {}
  func deleteViewer(_: UUID) async throws {}
  func revokeAllViewers() async throws -> Int { 0 }
  func rebindDevice(recoverySecret: String) async throws -> DeviceRegistration {
    reboundSecret = recoverySecret
    return registration
  }
  func deleteDevice() async throws {}
}

private final class InMemorySecrets: SecretStore, @unchecked Sendable {
  var values = [SecretKey: Data]()

  func read(_ key: SecretKey) throws -> CredentialState<Data> {
    values[key].map(CredentialState.present) ?? .missing
  }

  func save(_ data: Data, for key: SecretKey) throws {
    values[key] = data
  }

  func delete(_ key: SecretKey) throws {
    values[key] = nil
  }
}
