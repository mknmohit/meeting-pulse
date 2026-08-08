import Testing

@testable import MPSupport

struct AppConfigurationTests {
  @Test
  func missingValueFailsClosed() {
    #expect(throws: AppConfiguration.ConfigurationError.missing(key: "MP_SUPABASE_HOST")) {
      try AppConfiguration(
        supabaseHost: nil,
        supabaseAnonKey: "one.two.three",
        turnstileSiteKey: "site-key",
        viewerScheme: "https",
        viewerHosts: "viewer.example.com"
      )
    }
  }

  @Test
  func emptyValueFailsClosed() {
    #expect(throws: AppConfiguration.ConfigurationError.missing(key: "MP_SUPABASE_HOST")) {
      try AppConfiguration(
        supabaseHost: "   ",
        supabaseAnonKey: "one.two.three",
        turnstileSiteKey: "site-key",
        viewerScheme: "https",
        viewerHosts: "viewer.example.com"
      )
    }
  }

  @Test
  func placeholderValueFailsClosed() {
    #expect(throws: AppConfiguration.ConfigurationError.placeholder(key: "MP_SUPABASE_HOST")) {
      try AppConfiguration(
        supabaseHost: "YOUR_PROJECT_REF.supabase.co",
        supabaseAnonKey: "one.two.three",
        turnstileSiteKey: "site-key",
        viewerScheme: "https",
        viewerHosts: "viewer.example.com"
      )
    }
  }

  @Test
  func malformedHostFailsClosed() {
    #expect(
      throws: AppConfiguration.ConfigurationError.malformed(
        key: "MP_SUPABASE_HOST",
        expected: "a Supabase host or an https URL"
      )
    ) {
      try AppConfiguration(
        supabaseHost: "http://not-supabase.test",
        supabaseAnonKey: "one.two.three",
        turnstileSiteKey: "site-key",
        viewerScheme: "https",
        viewerHosts: "viewer.example.com"
      )
    }
  }

  @Test
  func malformedAnonKeyFailsClosed() {
    #expect(
      throws: AppConfiguration.ConfigurationError.malformed(
        key: "MP_SUPABASE_ANON_KEY",
        expected: "a legacy JWT or an sb_publishable key"
      )
    ) {
      try AppConfiguration(
        supabaseHost: "project123456.supabase.co",
        supabaseAnonKey: "not-a-jwt",
        turnstileSiteKey: "site-key",
        viewerScheme: "https",
        viewerHosts: "viewer.example.com"
      )
    }
  }

  @Test
  func validHostBuildsHTTPSURL() throws {
    let configuration = try AppConfiguration(
      supabaseHost: "project123456.supabase.co",
      supabaseAnonKey: "one.two.three",
      turnstileSiteKey: "site-key",
      viewerScheme: "https",
      viewerHosts: "viewer.example.com"
    )
    #expect(configuration.supabaseURL.absoluteString == "https://project123456.supabase.co")
  }

  @Test
  func viewerOriginsUseConfiguredSchemeAndHosts() throws {
    let configuration = try AppConfiguration(
      supabaseHost: "project123456.supabase.co",
      supabaseAnonKey: "one.two.three",
      turnstileSiteKey: "site-key",
      viewerScheme: "http",
      viewerHosts: "127.0.0.1:4321, viewer.example.com"
    )
    #expect(
      configuration.viewerOrigins.map(\.absoluteString)
        == ["http://127.0.0.1:4321", "http://viewer.example.com"]
    )
  }

  @Test
  func viewerHostsRejectQueryStrings() {
    #expect(
      throws: AppConfiguration.ConfigurationError.malformed(
        key: "MP_VIEWER_HOSTS",
        expected: "comma-separated hosts without schemes, queries, or fragments"
      )
    ) {
      try AppConfiguration(
        supabaseHost: "project123456.supabase.co",
        supabaseAnonKey: "one.two.three",
        turnstileSiteKey: "site-key",
        viewerScheme: "https",
        viewerHosts: "viewer.example.com?code=secret"
      )
    }

  }

  @Test
  func duplicateViewerHostsFailClosed() {
    #expect(
      throws: AppConfiguration.ConfigurationError.malformed(
        key: "MP_VIEWER_HOSTS",
        expected: "unique viewer hosts"
      )
    ) {
      try AppConfiguration(
        supabaseHost: "project123456.supabase.co",
        supabaseAnonKey: "one.two.three",
        turnstileSiteKey: "site-key",
        viewerScheme: "https",
        viewerHosts: "viewer.example.com,viewer.example.com"
      )
    }
  }

  @Test
  func modernPublishableKeyIsAccepted() throws {
    _ = try AppConfiguration(
      supabaseHost: "project123456.supabase.co",
      supabaseAnonKey: "sb_publishable_ci_key",
      turnstileSiteKey: "site-key",
      viewerScheme: "https",
      viewerHosts: "viewer.example.com"
    )
  }
}
