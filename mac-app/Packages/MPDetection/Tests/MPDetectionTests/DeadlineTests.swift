import Foundation
import Testing

@testable import MPDetection

@Suite("Deadline")
struct DeadlineTests {
  @Test("A fast operation returns its value")
  func fastOperationReturnsItsValue() async throws {
    let value = try await withDeadline(.seconds(5)) {
      42
    }
    #expect(value == 42)
  }

  @Test("An operation that throws keeps its error")
  func operationErrorIsPreserved() async throws {
    struct Boom: Error {}

    await #expect(throws: Boom.self) {
      try await withDeadline(.seconds(5)) {
        throw Boom()
      }
    }
  }

  @Test("A hanging operation fails with a timeout")
  func hangingOperationTimesOut() async throws {
    let start = ContinuousClock.now

    await #expect(throws: AXSnapshotError.timedOut) {
      try await withDeadline(.milliseconds(200)) {
        // Never finishes: the caller must not wait for it.
        try await Task.sleep(for: .seconds(60))
        return 1
      }
    }

    let elapsed = ContinuousClock.now - start
    #expect(elapsed < .seconds(10))
  }

  @Test("A late result does not resume the caller twice")
  func lateResultIsDropped() async throws {
    let start = ContinuousClock.now

    await #expect(throws: AXSnapshotError.timedOut) {
      try await withDeadline(.milliseconds(100)) {
        try await Task.sleep(for: .milliseconds(400))
        return 7
      }
    }

    // Give the late result time to arrive; it must be dropped silently.
    try await Task.sleep(for: .milliseconds(600))
    let elapsed = ContinuousClock.now - start
    #expect(elapsed < .seconds(5))
  }
}
