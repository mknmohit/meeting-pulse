import Foundation
import MPCore
import Testing

@testable import MPSync

struct SyncCoordinatorTests {
  @Test
  func successfulPublishUpdatesSyncMetadata() async {
    let transport = CoordinatorTransport()
    let coordinator = SyncCoordinator(
      transport: transport,
      nonce: UUID(),
      sleep: { _ in },
      randomUnit: { 0 }
    )
    let payload = payload(state: .busy)

    await coordinator.submit(payload)

    #expect(await coordinator.currentState == .idle)
    #expect(await coordinator.lastSuccessfulPayload == payload)
    #expect(await transport.published.count == 1)
  }

  @Test
  func failedWriteRetriesAndEventuallySucceeds() async {
    let transport = CoordinatorTransport(failures: 2)
    let coordinator = SyncCoordinator(
      transport: transport,
      nonce: UUID(),
      sleep: { _ in },
      randomUnit: { 0 }
    )

    await coordinator.submit(payload(state: .busy))

    #expect(await transport.attempts == 3)
    #expect(await coordinator.currentState == .idle)
  }

  @Test
  func supersededDeviceStopsPublishing() async {
    let transport = CoordinatorTransport(superseded: true)
    let coordinator = SyncCoordinator(
      transport: transport,
      nonce: UUID(),
      sleep: { _ in },
      randomUnit: { 0 }
    )

    await coordinator.submit(payload(state: .busy))

    #expect(await coordinator.currentState == .superseded)
  }
}

private func payload(state: State) -> StatusPayload {
  StatusPayload(
    state: state,
    callOkay: false,
    overrideMode: nil,
    overrideExpiresAt: nil
  )
}

private actor CoordinatorTransport: StatusTransport {
  private var remainingFailures: Int
  private let shouldSupersede: Bool
  private(set) var attempts = 0
  private(set) var published = [StatusPayload]()

  init(failures: Int = 0, superseded: Bool = false) {
    remainingFailures = failures
    shouldSupersede = superseded
  }

  func ensureSession() async throws {}

  func registerDevice(recoveryHash: String) async throws -> DeviceRegistration {
    fatalError("unused")
  }

  func publish(_ payload: StatusPayload, nonce: UUID) async throws -> PublishResult {
    attempts += 1
    if remainingFailures > 0 {
      remainingFailures -= 1
      throw TestError.failed
    }
    published.append(payload)
    return PublishResult(superseded: shouldSupersede, lastSeenAt: Date())
  }

  func updateDisplayName(_ name: String?) async throws {}
  func createPairingCode(hash: String) async throws -> UUID { fatalError("unused") }
  func rotatePairingCodes() async throws -> Int { 0 }
  func listViewers() async throws -> [ViewerRecord] { [] }
  func revokeViewer(_ id: UUID) async throws {}
  func revokeAllViewers() async throws -> Int { 0 }
  func rebindDevice(recoverySecret: String) async throws -> DeviceRegistration {
    fatalError("unused")
  }
  func deleteDevice() async throws {}
}

private enum TestError: Error {
  case failed
}
