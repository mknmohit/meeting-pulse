import Testing
@testable import MPSupport

struct SerialOperationQueueTests {
  @Test
  @MainActor
  func operationsRunInEnqueueOrder() async throws {
    let queue = SerialOperationQueue()
    let recorder = Recorder()
    let gate = Gate()

    let first = Task {
      try await queue.enqueue {
        await recorder.append("first-start")
        await gate.wait()
        await recorder.append("first-end")
      }
    }

    await recorder.waitFor("first-start")

    let second = Task {
      try await queue.enqueue {
        await recorder.append("second")
      }
    }

    for _ in 0..<10 {
      await Task.yield()
    }
    #expect(await recorder.snapshot() == ["first-start"])

    await gate.release()
    try await first.value
    try await second.value
    #expect(await recorder.snapshot() == ["first-start", "first-end", "second"])
  }
}

private actor Recorder {
  private var values = [String]()

  func append(_ value: String) {
    values.append(value)
  }

  func snapshot() -> [String] {
    values
  }

  func waitFor(_ value: String) async {
    while !values.contains(value) {
      await Task.yield()
    }
  }
}

private actor Gate {
  private var isReleased = false
  private var waiters = [CheckedContinuation<Void, Never>]()

  func wait() async {
    guard !isReleased else {
      return
    }
    await withCheckedContinuation { continuation in
      waiters.append(continuation)
    }
  }

  func release() {
    isReleased = true
    let waiters = self.waiters
    self.waiters.removeAll()
    for waiter in waiters {
      waiter.resume()
    }
  }
}
