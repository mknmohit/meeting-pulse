import Foundation
import MPSupport
import Testing

@testable import MPSync

@MainActor
struct AuthSessionBootstrapTests {
  @Test
  func validSessionDoesNotRequestAnonymousSignIn() async throws {
    let auth = FakeAuthSessionProvider()
    let bootstrap = AuthSessionBootstrap(
      auth: auth,
      turnstile: TurnstileGate(provider: FixedTurnstileProvider(value: "token"))
    )

    try await bootstrap.ensureSession()

    #expect(await auth.validationCount == 1)
    #expect(await auth.signInTokens.isEmpty)
  }

  @Test
  func invalidSessionIsReplacedAndValidated() async throws {
    let auth = FakeAuthSessionProvider(validationFailures: 1)
    let bootstrap = AuthSessionBootstrap(
      auth: auth,
      turnstile: TurnstileGate(provider: FixedTurnstileProvider(value: " token "))
    )

    try await bootstrap.ensureSession()

    #expect(await auth.validationCount == 2)
    #expect(await auth.signInTokens == ["token"])
  }

  @Test
  func authStorageIgnoresSupabaseMigrationKeys() throws {
    let secrets = AuthStorageSecrets()
    let storage = MeetingPulseAuthStorage(secrets: secrets)
    let value = Data("session".utf8)

    try storage.store(key: MeetingPulseAuthStorage.storageKey, value: value)
    try storage.remove(key: "supabase.session")

    #expect(try storage.retrieve(key: MeetingPulseAuthStorage.storageKey) == value)
    #expect(try storage.retrieve(key: "supabase.session") == nil)
  }
}

private actor FakeAuthSessionProvider: AuthSessionProvider {
  private var remainingValidationFailures: Int
  private(set) var validationCount = 0
  private(set) var signInTokens = [String]()

  init(validationFailures: Int = 0) {
    remainingValidationFailures = validationFailures
  }

  func requireValidSession() async throws {
    validationCount += 1
    if remainingValidationFailures > 0 {
      remainingValidationFailures -= 1
      throw TestError.invalidSession
    }
  }

  func signInAnonymously(captchaToken: String) async throws {
    signInTokens.append(captchaToken)
  }
}

@MainActor
private struct FixedTurnstileProvider: TurnstileProvider {
  let value: String

  func token(for reason: TurnstileReason) async throws -> String {
    value
  }
}

private enum TestError: Error {
  case invalidSession
}

private final class AuthStorageSecrets: SecretStore, @unchecked Sendable {
  private var values = [SecretKey: Data]()

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
