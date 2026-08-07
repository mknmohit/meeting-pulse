import Testing

@testable import MPSupport

struct AppConfigurationTests {
  @Test
  func missingValueFailsClosed() {
    #expect(throws: AppConfiguration.ConfigurationError.missing(key: "MP_SUPABASE_HOST")) {
      try AppConfiguration(
        supabaseHost: nil,
        supabaseAnonKey: "one.two.three",
        turnstileSiteKey: "site-key"
      )
    }
  }

  @Test
  func emptyValueFailsClosed() {
    #expect(throws: AppConfiguration.ConfigurationError.missing(key: "MP_SUPABASE_HOST")) {
      try AppConfiguration(
        supabaseHost: "   ",
        supabaseAnonKey: "one.two.three",
        turnstileSiteKey: "site-key"
      )
    }
  }

  @Test
  func placeholderValueFailsClosed() {
    #expect(throws: AppConfiguration.ConfigurationError.placeholder(key: "MP_SUPABASE_HOST")) {
      try AppConfiguration(
        supabaseHost: "YOUR_PROJECT_REF.supabase.co",
        supabaseAnonKey: "one.two.three",
        turnstileSiteKey: "site-key"
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
        turnstileSiteKey: "site-key"
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
        turnstileSiteKey: "site-key"
      )
    }
  }

  @Test
  func validHostBuildsHTTPSURL() throws {
    let configuration = try AppConfiguration(
      supabaseHost: "project123456.supabase.co",
      supabaseAnonKey: "one.two.three",
      turnstileSiteKey: "site-key"
    )
    #expect(configuration.supabaseURL.absoluteString == "https://project123456.supabase.co")
  }

  @Test
  func modernPublishableKeyIsAccepted() throws {
    _ = try AppConfiguration(
      supabaseHost: "project123456.supabase.co",
      supabaseAnonKey: "sb_publishable_ci_key",
      turnstileSiteKey: "site-key"
    )
  }
}
