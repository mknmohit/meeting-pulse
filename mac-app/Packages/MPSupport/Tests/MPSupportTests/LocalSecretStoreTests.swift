import Foundation
import Testing

@testable import MPSupport

struct LocalSecretStoreTests {
  @Test
  func missingStoreReturnsMissing() throws {
    let (store, directory) = makeStore()
    defer { try? FileManager.default.removeItem(at: directory) }

    #expect(try store.read(.deviceID) == .missing)
  }

  @Test
  func valuesPersistAcrossStoreInstances() throws {
    let (store, directory) = makeStore()
    defer { try? FileManager.default.removeItem(at: directory) }
    let value = Data("device-id".utf8)

    try store.save(value, for: .deviceID)
    let reloaded = LocalSecretStore(
      fileURL: directory.appendingPathComponent("secrets.plist")
    )

    #expect(try reloaded.read(.deviceID) == .present(value))
    #expect(try reloaded.read(.pairingCode) == .missing)
  }

  @Test
  func saveReplacesOneValueAndDeleteRemovesTheFileWhenEmpty() throws {
    let (store, directory) = makeStore()
    defer { try? FileManager.default.removeItem(at: directory) }
    let fileURL = directory.appendingPathComponent("secrets.plist")

    try store.save(Data("first".utf8), for: .deviceID)
    try store.save(Data("second".utf8), for: .pairingCode)
    try store.save(Data("updated".utf8), for: .deviceID)
    try store.delete(.deviceID)

    #expect(try store.read(.deviceID) == .missing)
    #expect(try store.read(.pairingCode) == .present(Data("second".utf8)))
    try store.delete(.pairingCode)
    #expect(!FileManager.default.fileExists(atPath: fileURL.path))
  }

  @Test
  func malformedStoreDataThrows() throws {
    let (store, directory) = makeStore()
    defer { try? FileManager.default.removeItem(at: directory) }
    let fileURL = directory.appendingPathComponent("secrets.plist")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try Data("{".utf8).write(to: fileURL)

    #expect(throws: LocalSecretStore.StoreError.invalidData) {
      _ = try store.read(.deviceID)
    }
  }

  @Test
  func storeAndDirectoryUseOwnerOnlyPermissions() throws {
    let (store, directory) = makeStore()
    defer { try? FileManager.default.removeItem(at: directory) }
    let fileURL = directory.appendingPathComponent("secrets.plist")

    try store.save(Data("secret".utf8), for: .deviceRecoveryPhrase)

    let directoryAttributes = try FileManager.default.attributesOfItem(atPath: directory.path)
    let fileAttributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
    #expect((directoryAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o700)
    #expect((fileAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
  }

  private func makeStore() -> (LocalSecretStore, URL) {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("MeetingPulseSecrets-\(UUID().uuidString)")
    return (
      LocalSecretStore(fileURL: directory.appendingPathComponent("secrets.plist")),
      directory
    )
  }
}
