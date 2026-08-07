import Foundation
import MPCore
import MPSupport
import Testing

@testable import MPSync

struct PairingRecoveryTests {
  @Test
  func pairingServiceHashesOnlyTheNormalizedCode() async throws {
    let transport = FakeTransport()
    let service = PairingService(transport: transport)
    let result = try await service.createCode()

    #expect(result.rawCode.count == PairingCodeFormat.length)
    #expect(result.displayCode.contains("-"))
    #expect(
      transport.createdPairingHash
        == CrockfordBase32.sha256Hex(
          CrockfordBase32.normalize(result.rawCode)
        ))
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
}

private final class FakeTransport: StatusTransport, @unchecked Sendable {
  let registration = DeviceRegistration(
    deviceID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
    instanceNonce: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
  )
  var createdPairingHash: String?

  func ensureSession() async throws {}

  func registerDevice(recoveryHash: String) async throws -> DeviceRegistration {
    registration
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
  func revokeAllViewers() async throws -> Int { 0 }
  func rebindDevice(recoverySecret: String) async throws -> DeviceRegistration { registration }
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
