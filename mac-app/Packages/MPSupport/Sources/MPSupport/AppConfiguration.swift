import Foundation

public struct AppConfiguration: Sendable, Equatable {
  public let supabaseURL: URL
  public let supabaseAnonKey: String
  public let turnstileSiteKey: String

  public enum ConfigurationError: Error, CustomStringConvertible, Equatable {
    case missing(key: String)
    case placeholder(key: String)
    case malformed(key: String, expected: String)

    public var description: String {
      let detail: String
      switch self {
      case .missing(let key):
        detail = "\(key) is missing"
      case .placeholder(let key):
        detail = "\(key) is still a placeholder"
      case .malformed(let key, let expected):
        detail = "\(key) is malformed; expected \(expected)"
      }
      return "Meeting Pulse is not configured. \(detail). Copy "
        + "mac-app/Config.xcconfig.example into Config.xcconfig and fill it in."
    }
  }

  public init(
    supabaseHost: String?,
    supabaseAnonKey: String?,
    turnstileSiteKey: String?
  ) throws {
    let host = try Self.required("MP_SUPABASE_HOST", supabaseHost)
    let anonKey = try Self.required("MP_SUPABASE_ANON_KEY", supabaseAnonKey)
    let turnstileKey = try Self.required("MP_TURNSTILE_SITE_KEY", turnstileSiteKey)

    if host.contains("YOUR_") {
      throw ConfigurationError.placeholder(key: "MP_SUPABASE_HOST")
    }
    if anonKey.contains("YOUR_") {
      throw ConfigurationError.placeholder(key: "MP_SUPABASE_ANON_KEY")
    }
    if turnstileKey.contains("YOUR_") {
      throw ConfigurationError.placeholder(key: "MP_TURNSTILE_SITE_KEY")
    }

    let url = try Self.supabaseURL(from: host)
    guard Self.isJWTShape(anonKey) else {
      throw ConfigurationError.malformed(
        key: "MP_SUPABASE_ANON_KEY",
        expected: "a legacy JWT or an sb_publishable key"
      )
    }

    self.supabaseURL = url
    self.supabaseAnonKey = anonKey
    self.turnstileSiteKey = turnstileKey
  }

  public static func load(bundle: Bundle = .main) throws -> AppConfiguration {
    try AppConfiguration(
      supabaseHost: bundle.object(forInfoDictionaryKey: "MPSupabaseHost") as? String,
      supabaseAnonKey: bundle.object(forInfoDictionaryKey: "MPSupabaseAnonKey") as? String,
      turnstileSiteKey: bundle.object(forInfoDictionaryKey: "MPTurnstileSiteKey") as? String
    )
  }

  private static func required(_ key: String, _ value: String?) throws -> String {
    guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw ConfigurationError.missing(key: key)
    }
    return value.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func supabaseURL(from host: String) throws -> URL {
    if host.hasPrefix("https://") {
      guard
        let url = URL(string: host),
        url.host != nil,
        url.path == "/" || url.path.isEmpty
      else {
        throw ConfigurationError.malformed(
          key: "MP_SUPABASE_HOST",
          expected: "a Supabase host or an https URL"
        )
      }
      return url
    }

    guard host.range(of: #"^[a-z0-9-]{8,}\.supabase\.co$"#, options: .regularExpression) != nil
    else {
      throw ConfigurationError.malformed(
        key: "MP_SUPABASE_HOST",
        expected: "a Supabase host or an https URL"
      )
    }
    guard let url = URL(string: "https://\(host)") else {
      throw ConfigurationError.malformed(
        key: "MP_SUPABASE_HOST",
        expected: "a Supabase host or an https URL"
      )
    }
    return url
  }

  private static func isJWTShape(_ value: String) -> Bool {
    value.range(
      of: #"^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$"#,
      options: .regularExpression
    ) != nil
      || value.range(
        of: #"^sb_publishable_[A-Za-z0-9_-]+$"#,
        options: .regularExpression
      ) != nil
  }
}
