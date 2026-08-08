import Foundation

public enum CredentialState<Value: Sendable>: Sendable {
  case present(Value)
  case missing
  case temporarilyUnavailable
}

extension CredentialState: Equatable where Value: Equatable {}

public enum SecretKey: String, CaseIterable, Sendable {
  case supabaseRefreshToken
  case deviceRecoveryPhrase
  case deviceID
  case deviceInstanceNonce
  case pairingCode
}

public protocol SecretStore: Sendable {
  func read(_ key: SecretKey) throws -> CredentialState<Data>
  func save(_ data: Data, for key: SecretKey) throws
  func delete(_ key: SecretKey) throws
}
