import Foundation
import Testing

struct FixturePrivacyTests {
  @Test
  func fixturesContainNoRawPrivateContent() throws {
    let fixtureNames = [
      "Fixtures/meet/active-foreground",
      "Fixtures/meet/background-tab",
      "Fixtures/meet/ended",
      "Fixtures/slack/idle",
      "Fixtures/slack/huddle-window",
      "Fixtures/slack/huddle-ended",
    ]

    for fixtureName in fixtureNames {
      guard let url = Bundle.module.url(forResource: fixtureName, withExtension: "json") else {
        Issue.record("Missing fixture \(fixtureName)")
        continue
      }
      let contents = try String(contentsOf: url, encoding: .utf8)
      #expect(!contents.contains("@"))
      #expect(!contents.contains("https://"))
      #expect(!contents.contains("meet.google.com"))
      #expect(!contents.contains("supabase.co"))
    }
  }
}
