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
}

@MainActor
private struct FixedTurnstileProvider: TurnstileProvider {
  let value: String

  func token(for reason: TurnstileReason) async throws -> String {
    value
  }
}
