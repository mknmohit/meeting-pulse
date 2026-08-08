import Foundation
import Testing

@testable import MPCore

struct PairingCodeTests {
  @Test
  func normalizationMapsBeforeStripping() {
    #expect(CrockfordBase32.normalize("i-l-o-u 012") == "1101012")
    #expect(CrockfordBase32.normalize("ab!c\u{2013}d") == "ABCD")
  }

  @Test
  func hashingUsesCanonicalSHA256() {
    #expect(
      CrockfordBase32.sha256Hex("")
        == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    )
    #expect(
      CrockfordBase32.sha256Hex("abc")
        == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    )
  }

  @Test
  func generatedCodesUseTheCrockfordAlphabet() {
    let code = CrockfordBase32.generate(characters: PairingCodeFormat.length)
    #expect(code.count == PairingCodeFormat.length)
    #expect(code.allSatisfy { CrockfordBase32.alphabet.contains($0) })
    #expect(PairingCodeFormat.display("1234567890") == "1234567890")
  }

  @Test
  func recoveryDisplayUsesFiveCharacterGroups() {
    #expect(
      RecoveryPhraseFormat.display("12345678901234567890123456")
        == ["12345", "67890", "12345", "67890", "12345", "6"].joined(separator: "-"))
  }

  @Test
  func sharedFixtureMatchesSwiftNormalization() throws {
    var fixtureURL = URL(fileURLWithPath: #filePath)
    for _ in 0..<6 {
      fixtureURL.deleteLastPathComponent()
    }
    fixtureURL.appendPathComponent("docs/fixtures/code-normalization.json")
    let fixture = try JSONDecoder().decode(
      NormalizationFixture.self,
      from: Data(contentsOf: fixtureURL)
    )

    for entry in fixture.entries {
      #expect(CrockfordBase32.normalize(entry.input) == entry.normalized)
      #expect(CrockfordBase32.sha256Hex(entry.normalized) == entry.sha256)
    }
  }
}

private struct NormalizationFixture: Decodable {
  let entries: [NormalizationEntry]
}

private struct NormalizationEntry: Decodable {
  let input: String
  let normalized: String
  let sha256: String
}
