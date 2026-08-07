import Foundation
import Testing

@testable import MPSupport

struct RedactorTests {
  @Test
  func removesEveryForbiddenValueClass() {
    var redactor = Redactor()
    redactor.registerSensitiveValue("Display Name")
    let pairingCode = ["ABCDE", "FGHJK"].joined(separator: "-")
    let recoveryPhrase = ["ABCDE", "FGHJK", "MNPQR", "STVWX", "YZ012", "3"]
      .joined(separator: "-")
    let email = ["wife", "example.com"].joined(separator: "@")
    let supabaseURL = "https://" + String(repeating: "a", count: 20) + ".supabase.co"
    let dirty = """
      https://meet.google.com/abc-defg-hij \(email) \(pairingCode)
      \(recoveryPhrase)
      a1b2c3d4-0000-4000-8000-000000000000
      \(supabaseURL)
      Display Name
      """

    let clean = redactor.redact(dirty)

    #expect(!clean.contains("https://"))
    #expect(!clean.contains("@"))
    #expect(!clean.contains(pairingCode))
    #expect(!clean.contains(recoveryPhrase))
    #expect(!clean.contains("a1b2c3d4-0000-4000-8000-000000000000"))
    #expect(!clean.contains("Display Name"))
    #expect(clean.contains("<redacted>"))
  }
}
