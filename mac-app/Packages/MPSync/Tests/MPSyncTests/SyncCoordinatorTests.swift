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
    await coordinator.waitForCompletion()

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
    await coordinator.waitForCompletion()

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
    await coordinator.waitForCompletion()

    #expect(await coordinator.currentState == .superseded)
  }

  @Test
  func supersededDeviceRefreshesTheNonceAndKeepsPublishing() async {
    let transport = CoordinatorTransport(superseded: true)
    let refreshedNonce = UUID()
    let coordinator = SyncCoordinator(
      transport: transport,
      nonce: UUID(),
      sleep: { _ in },
      randomUnit: { 0 },
      nonceRefresh: { refreshedNonce }
    )

    await coordinator.submit(payload(state: .busy))
    await coordinator.waitForCompletion()

    #expect(await coordinator.currentState == .idle)
    #expect(await transport.nonces.contains(refreshedNonce))
    #expect(await transport.nonces.first != refreshedNonce)
  }

  @Test
  func unregisteredDeviceTriggersTheRecoveryPath() async {
    let transport = CoordinatorTransport(unregistered: true)
    let registration = DeviceRegistration(deviceID: UUID(), instanceNonce: UUID())
    let coordinator = SyncCoordinator(
      transport: transport,
      nonce: UUID(),
      sleep: { _ in },
      randomUnit: { 0 },
      deviceRecovery: { registration }
    )

    await coordinator.submit(payload(state: .busy))
    await coordinator.waitForCompletion()

    #expect(await coordinator.currentState == .idle)
    #expect(await transport.nonces.contains(registration.instanceNonce))
  }

  @Test
  func restoredConnectionPublishesThePendingPayloadWithoutWaiting() async {
    let transport = CoordinatorTransport(failures: 1)
    let coordinator = SyncCoordinator(
      transport: transport,
      nonce: UUID(),
      sleep: { _ in },
      randomUnit: { 0 }
    )

    await coordinator.submit(payload(state: .busy))
    await coordinator.connectionRestored()
    await coordinator.waitForCompletion()

    #expect(await coordinator.currentState == .idle)
    #expect(await transport.published.count == 1)
  }

  @Test
  func submitReturnsWhileThePublishIsStillInFlight() async {
    let transport = BlockingTransport()
    let coordinator = SyncCoordinator(
      transport: transport,
      nonce: UUID(),
      sleep: { _ in },
      randomUnit: { 0 },
      publishTimeout: .milliseconds(200)
    )
    let clock = ContinuousClock()
    let start = clock.now

    await coordinator.submit(payload(state: .busy))

    // The submit call must not wait for the network.
    #expect(start.duration(to: clock.now) < .seconds(1))
    await coordinator.stop()
  }

  @Test
  func aStalledPublishFailsAfterTheDeadline() async {
    let transport = BlockingTransport()
    let coordinator = SyncCoordinator(
      transport: transport,
      nonce: UUID(),
      sleep: { _ in },
      randomUnit: { 0 },
      publishTimeout: .milliseconds(200)
    )

    await coordinator.submit(payload(state: .busy))
    // The publish never answers, so the deadline must surface as a retry
    // instead of blocking the coordinator forever.
    try? await Task.sleep(for: .milliseconds(600))

    #expect(await coordinator.currentState == .retrying)
    await coordinator.stop()
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
  private let unregistered: Bool
  private(set) var attempts = 0
  private(set) var published = [StatusPayload]()
  private(set) var nonces = [UUID]()

  init(failures: Int = 0, superseded: Bool = false, unregistered: Bool = false) {
    remainingFailures = failures
    shouldSupersede = superseded
    self.unregistered = unregistered
  }

  func ensureSession() async throws {}

  func registerDevice(recoveryHash: String) async throws -> DeviceRegistration {
    fatalError("unused")
  }

  func publish(_ payload: StatusPayload, nonce: UUID) async throws -> PublishResult {
    attempts += 1
    nonces.append(nonce)
    if unregistered && attempts == 1 {
      throw SupabaseStatusTransport.TransportError.deviceNotRegistered
    }
    if remainingFailures > 0 {
      remainingFailures -= 1
      throw TestError.failed
    }
    published.append(payload)
    return PublishResult(superseded: shouldSupersede && attempts == 1, lastSeenAt: Date())
  }

  func updateDisplayName(_ name: String?) async throws {}
  func createPairingCode(hash: String) async throws -> UUID { fatalError("unused") }
  func rotatePairingCodes() async throws -> Int { 0 }
  func listViewers() async throws -> [ViewerRecord] { [] }
  func revokeViewer(_ id: UUID) async throws {}
  func deleteViewer(_ id: UUID) async throws {}
  func revokeAllViewers() async throws -> Int { 0 }
  func rebindDevice(recoverySecret: String) async throws -> DeviceRegistration {
    fatalError("unused")
  }
  func deleteDevice() async throws {}
}

/// A transport whose publish never answers, like a wedged network.
private actor BlockingTransport: StatusTransport {
  func ensureSession() async throws {}

  func registerDevice(recoveryHash: String) async throws -> DeviceRegistration {
    fatalError("unused")
  }

  func publish(_ payload: StatusPayload, nonce: UUID) async throws -> PublishResult {
    try await Task.sleep(for: .seconds(30))
    return PublishResult(superseded: false, lastSeenAt: Date())
  }

  func updateDisplayName(_ name: String?) async throws {}
  func createPairingCode(hash: String) async throws -> UUID { fatalError("unused") }
  func rotatePairingCodes() async throws -> Int { 0 }
  func listViewers() async throws -> [ViewerRecord] { [] }
  func revokeViewer(_ id: UUID) async throws {}
  func deleteViewer(_ id: UUID) async throws {}
  func revokeAllViewers() async throws -> Int { 0 }
  func rebindDevice(recoverySecret: String) async throws -> DeviceRegistration {
    fatalError("unused")
  }
  func deleteDevice() async throws {}
}

private enum TestError: Error {
  case failed
}
