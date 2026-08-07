import Foundation
import Security

public struct KeychainStore: SecretStore, Sendable {
  public enum KeychainError: Error, Equatable, Sendable {
    case status(OSStatus)
  }

  public let service: String
  public let accessGroup: String?

  public init(
    service: String = "com.techdevix.meetingpulse.auth",
    accessGroup: String? = nil
  ) {
    self.service = service
    self.accessGroup = accessGroup
  }

  public func read(_ key: SecretKey) throws -> CredentialState<Data> {
    var query = baseQuery(for: key)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne

    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    switch status {
    case errSecSuccess:
      guard let data = result as? Data else {
        throw KeychainError.status(errSecInternalError)
      }
      return .present(data)
    case errSecItemNotFound:
      return .missing
    case errSecInteractionNotAllowed:
      return .temporarilyUnavailable
    default:
      throw KeychainError.status(status)
    }
  }

  public func save(_ data: Data, for key: SecretKey) throws {
    var query = baseQuery(for: key)
    query[kSecValueData as String] = data

    let addStatus = SecItemAdd(query as CFDictionary, nil)
    guard addStatus == errSecDuplicateItem else {
      if addStatus == errSecSuccess {
        return
      }
      throw KeychainError.status(addStatus)
    }

    let updateStatus = SecItemUpdate(
      baseQuery(for: key) as CFDictionary,
      [kSecValueData as String: data] as CFDictionary
    )
    guard updateStatus == errSecSuccess else {
      throw KeychainError.status(updateStatus)
    }
  }

  public func delete(_ key: SecretKey) throws {
    let status = SecItemDelete(baseQuery(for: key) as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw KeychainError.status(status)
    }
  }

  private func baseQuery(for key: SecretKey) -> [String: Any] {
    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key.rawValue,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
      kSecAttrSynchronizable as String: false,
    ]
    if let accessGroup {
      query[kSecAttrAccessGroup as String] = accessGroup
    }
    return query
  }
}
