import Foundation

public enum DeadlineError: Error, Equatable, Sendable {
  case timedOut
}

private final class DeadlineState<T>: @unchecked Sendable {
  private let lock = NSLock()
  private var continuation: CheckedContinuation<T, Error>?
  private var work: Task<Void, Never>?
  private var timer: Task<Void, Never>?
  private var isFinished = false

  func install(_ continuation: CheckedContinuation<T, Error>) {
    lock.lock()
    defer { lock.unlock() }
    self.continuation = continuation
  }

  func adopt(work: Task<Void, Never>, timer: Task<Void, Never>) {
    lock.lock()
    if isFinished {
      lock.unlock()
      work.cancel()
      timer.cancel()
      return
    }
    self.work = work
    self.timer = timer
    lock.unlock()
  }

  func succeed(_ value: sending T) {
    lock.lock()
    guard !isFinished else {
      lock.unlock()
      return
    }
    isFinished = true
    let continuation = self.continuation
    self.continuation = nil
    let work = self.work
    self.work = nil
    let timer = self.timer
    self.timer = nil
    lock.unlock()

    work?.cancel()
    timer?.cancel()
    continuation?.resume(returning: value)
  }

  func fail(_ error: sending any Error) {
    lock.lock()
    guard !isFinished else {
      lock.unlock()
      return
    }
    isFinished = true
    let continuation = self.continuation
    self.continuation = nil
    let work = self.work
    self.work = nil
    let timer = self.timer
    self.timer = nil
    lock.unlock()

    work?.cancel()
    timer?.cancel()
    continuation?.resume(throwing: error)
  }
}

/// Runs an operation under a hard deadline.
///
/// The operation is abandoned when the deadline elapses so a wedged network
/// call or a stalled token provider can never block a retry loop forever.
public func withDeadline<T: Sendable>(
  _ duration: Duration,
  operation: @escaping @Sendable () async throws -> T
) async throws -> T {
  let state = DeadlineState<T>()
  return try await withTaskCancellationHandler {
    try await withCheckedThrowingContinuation { continuation in
      state.install(continuation)
      let work = Task {
        do {
          let value = try await operation()
          state.succeed(value)
        } catch {
          state.fail(error)
        }
      }
      let timer = Task {
        try? await Task.sleep(for: duration)
        state.fail(DeadlineError.timedOut)
        work.cancel()
      }
      state.adopt(work: work, timer: timer)
    }
  } onCancel: {
    state.fail(CancellationError())
  }
}
