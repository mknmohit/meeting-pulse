import Testing

@testable import MPSync

@MainActor
struct TurnstileTests {
  @Test
  func unavailableProviderFailsClosed() async {
    let gate = TurnstileGate(provider: UnavailableTurnstileProvider())
    await #expect(throws: TurnstileError.unavailable) {
      try await gate.token(for: .firstRegistration)
    }
  }

  @Test
  func emptyProviderTokenFailsClosed() async {
    let gate = TurnstileGate(provider: FixedTurnstileProvider(value: "   "))
    await #expect(throws: TurnstileError.emptyToken) {
      try await gate.token(for: .recoveryRebind)
    }
  }

  @Test
  func validTokenIsTrimmed() async throws {
    let gate = TurnstileGate(provider: FixedTurnstileProvider(value: " token "))
    #expect(try await gate.token(for: .firstRegistration) == "token")
  }

  @Test
  func tokenCompletionReleasesProviderAndNotifiesCaller() async throws {
    let provider = ShutdownTrackingProvider()
    let completion = CompletionTrackingProvider()
    let gate = TurnstileGate(
      provider: provider,
      onTokenFinished: {
        completion.finishedCount += 1
      }
    )

    #expect(try await gate.token(for: .firstRegistration) == "token")

    #expect(provider.shutdownCount == 1)
    #expect(completion.finishedCount == 1)
  }

  @Test
  func shutdownIsForwardedToProvider() async {
    let provider = ShutdownTrackingProvider()
    let gate = TurnstileGate(provider: provider)

    await gate.shutdown()

    #expect(provider.shutdownCount == 1)
  }
}

@MainActor
private struct FixedTurnstileProvider: TurnstileProvider {
  let value: String

  func token(for reason: TurnstileReason) async throws -> String {
    value
  }
}

@MainActor
private final class ShutdownTrackingProvider: TurnstileProvider {
  private(set) var shutdownCount = 0

  func token(for reason: TurnstileReason) async throws -> String {
    "token"
  }

  func shutdown() {
    shutdownCount += 1
  }
}

@MainActor
private final class CompletionTrackingProvider {
  var finishedCount = 0
}
