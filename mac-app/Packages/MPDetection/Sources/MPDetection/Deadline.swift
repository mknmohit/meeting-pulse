import Foundation

/// Resumes a continuation exactly once.
///
/// The first result wins and the other side is dropped. That is what lets a
/// deadline release the caller while the operation itself keeps running in
/// the background.
private final class SingleResume<T: Sendable>: @unchecked Sendable {
  private let lock = NSLock()
  private var continuation: CheckedContinuation<T, Error>?

  init(_ continuation: CheckedContinuation<T, Error>) {
    self.continuation = continuation
  }

  func resume(with result: Result<T, Error>) {
    lock.lock()
    guard let continuation else {
      lock.unlock()
      return
    }
    self.continuation = nil
    lock.unlock()
    continuation.resume(with: result)
  }
}

/// Runs an operation with a deadline.
///
/// An accessibility read runs on the dedicated accessibility thread. A
/// browser that stops answering can hold that read for a long time, and a
/// detector that waits for it would never produce another reading. The
/// deadline releases the caller instead, and the detector fails closed.
func withDeadline<T: Sendable>(
  _ duration: Duration,
  operation: @escaping @Sendable () async throws -> T
) async throws -> T {
  try await withCheckedThrowingContinuation { continuation in
    let box = SingleResume(continuation)
    Task {
      do {
        box.resume(with: .success(try await operation()))
      } catch {
        box.resume(with: .failure(error))
      }
    }
    Task {
      try? await Task.sleep(for: duration)
      box.resume(with: .failure(AXSnapshotError.timedOut))
    }
  }
}
