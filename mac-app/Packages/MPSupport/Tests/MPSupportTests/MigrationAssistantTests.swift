import Foundation
import MPSupport
import Testing

@Test
func migrationIsIdempotent() throws {
  let suiteName = "MeetingPulse.MigrationTests.\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suiteName))
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("MeetingPulseMigration-\(UUID().uuidString)", isDirectory: true)
  defer {
    defaults.removePersistentDomain(forName: suiteName)
    try? FileManager.default.removeItem(at: directory)
  }

  defaults.set("Owner", forKey: "displayName")
  defaults.set("anon-key", forKey: "telemetry.anonKey")
  let assistant = MigrationAssistant(
    defaults: defaults,
    applicationSupport: directory
  )

  let first = try assistant.migrateIfNeeded()
  let second = try assistant.migrateIfNeeded()

  #expect(first.migrated)
  #expect(first.preservedTelemetryIdentity)
  #expect(!second.migrated)
  #expect(defaults.string(forKey: "owner.displayName") == "Owner")
  #expect(defaults.string(forKey: "publish.anonKey") == "anon-key")
}
