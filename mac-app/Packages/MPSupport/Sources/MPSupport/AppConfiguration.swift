import Foundation

public struct AppConfiguration: Sendable, Equatable {
  public let supabaseURL: URL
  public let supabaseAnonKey: String
  public let turnstileSiteKey: String
  public let viewerOrigins: [URL]

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
    turnstileSiteKey: String?,
    viewerScheme: String?,
    viewerHosts: String?
  ) throws {
    let host = try Self.required("MP_SUPABASE_HOST", supabaseHost)
    let anonKey = try Self.required("MP_SUPABASE_ANON_KEY", supabaseAnonKey)
    let turnstileKey = try Self.required("MP_TURNSTILE_SITE_KEY", turnstileSiteKey)
    let viewerSchemeValue = try Self.required("MP_VIEWER_SCHEME", viewerScheme)
    let viewerHostsValue = try Self.required("MP_VIEWER_HOSTS", viewerHosts)

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
    let viewerURLs = try Self.viewerURLs(
      scheme: viewerSchemeValue,
      hosts: viewerHostsValue
    )
    guard Self.isJWTShape(anonKey) else {
      throw ConfigurationError.malformed(
        key: "MP_SUPABASE_ANON_KEY",
        expected: "a legacy JWT or an sb_publishable key"
      )
    }

    self.supabaseURL = url
    self.supabaseAnonKey = anonKey
    self.turnstileSiteKey = turnstileKey
    self.viewerOrigins = viewerURLs
  }

  public static func load(bundle: Bundle = .main) throws -> AppConfiguration {
    try AppConfiguration(
      supabaseHost: bundle.object(forInfoDictionaryKey: "MPSupabaseHost") as? String,
      supabaseAnonKey: bundle.object(forInfoDictionaryKey: "MPSupabaseAnonKey") as? String,
      turnstileSiteKey: bundle.object(forInfoDictionaryKey: "MPTurnstileSiteKey") as? String,
      viewerScheme: bundle.object(forInfoDictionaryKey: "MPViewerScheme") as? String,
      viewerHosts: bundle.object(forInfoDictionaryKey: "MPViewerHosts") as? String
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

  private static func viewerURLs(scheme: String, hosts: String) throws -> [URL] {
    let normalizedScheme = scheme.lowercased()
    guard
      normalizedScheme == "http" || normalizedScheme == "https"
    else {
      throw ConfigurationError.malformed(
        key: "MP_VIEWER_SCHEME",
        expected: "http or https"
      )
    }

    let entries = hosts.split(separator: ",", omittingEmptySubsequences: false)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    guard !entries.isEmpty, entries.allSatisfy({ !$0.isEmpty }) else {
      throw ConfigurationError.malformed(
        key: "MP_VIEWER_HOSTS",
        expected: "a comma-separated list of non-empty hosts"
      )
    }

    var urls = [URL]()
    for host in entries {
      guard
        !host.contains("://"),
        let url = URL(string: "\(normalizedScheme)://\(host)"),
        url.host != nil,
        url.query == nil,
        url.fragment == nil
      else {
        throw ConfigurationError.malformed(
          key: "MP_VIEWER_HOSTS",
          expected: "comma-separated hosts without schemes, queries, or fragments"
        )
      }
      urls.append(url)
    }

    guard Set(urls.map { $0.absoluteString.lowercased() }).count == urls.count else {
      throw ConfigurationError.malformed(
        key: "MP_VIEWER_HOSTS",
        expected: "unique viewer hosts"
      )
    }
    return urls
  }
}
