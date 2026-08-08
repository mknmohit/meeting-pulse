public actor SerialOperationQueue {
  private var tail: Task<Void, Never>?

  public init() {}

  public func enqueue<T: Sendable>(
    _ operation: @escaping @MainActor @Sendable () async throws -> T
  ) async throws -> T {
    let previous = tail
    let task = Task { @MainActor in
      await previous?.value
      return try await operation()
    }
    tail = Task { @MainActor in
      _ = try? await task.value
    }
    return try await task.value
  }

  public func cancel() {
    tail?.cancel()
    tail = nil
  }
}
