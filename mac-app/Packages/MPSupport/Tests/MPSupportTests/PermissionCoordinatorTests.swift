import Foundation
import Testing
@testable import MPSupport

struct PermissionCoordinatorTests {
  @Test
  func refreshPublishesOnlyTrustChanges() async {
    let probe = MutableTrustProbe()
    let coordinator = PermissionCoordinator(
      pollInterval: .seconds(60),
      trustProvider: { probe.read() }
    )
    let stream = await coordinator.changes
    var iterator = stream.makeAsyncIterator()

    await coordinator.start()
    #expect(await iterator.next() == false)

    probe.set(true)
    await coordinator.refresh()
    #expect(await iterator.next() == true)
    await coordinator.stop()
  }
}

private final class MutableTrustProbe: @unchecked Sendable {
  private let lock = NSLock()
  private var value = false

  func read() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return value
  }

  func set(_ value: Bool) {
    lock.lock()
    self.value = value
    lock.unlock()
  }
}
