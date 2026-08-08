import Foundation
import Security

public protocol LegacyKeychainCleaner: Sendable {
  func removeMeetingPulseItems() throws
}

public struct LegacyKeychainCleanup: LegacyKeychainCleaner, Sendable {
  public enum CleanupError: Error, Equatable, Sendable {
    case status(OSStatus)
  }

  public static let service = "com.techdevix.meetingpulse.auth"

  public init() {}

  public func removeMeetingPulseItems() throws {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: Self.service,
    ]
    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw CleanupError.status(status)
    }
  }
}

public struct LegacyStorageReset {
  public static let sentinelKey = "meetingpulse.localStorage.reset.v1"

  private let defaults: UserDefaults
  private let cleaner: any LegacyKeychainCleaner

  public init(
    defaults: UserDefaults = .standard,
    cleaner: any LegacyKeychainCleaner = LegacyKeychainCleanup()
  ) {
    self.defaults = defaults
    self.cleaner = cleaner
  }

  @discardableResult
  public func resetIfNeeded() throws -> Bool {
    guard !defaults.bool(forKey: Self.sentinelKey) else {
      return false
    }

    try cleaner.removeMeetingPulseItems()
    defaults.removeObject(forKey: "setup.completed")
    defaults.set(true, forKey: Self.sentinelKey)
    return true
  }
}
