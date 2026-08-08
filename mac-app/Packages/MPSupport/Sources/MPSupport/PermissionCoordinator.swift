@preconcurrency import ApplicationServices
import Foundation

public actor PermissionCoordinator {
  public let changes: AsyncStream<Bool>

  private let trustProvider: @Sendable () -> Bool
  private var pollInterval: Duration
  private var continuation: AsyncStream<Bool>.Continuation
  private var task: Task<Void, Never>?
  private var lastValue: Bool?

  public init(
    pollInterval: Duration = .seconds(1),
    trustProvider: @escaping @Sendable () -> Bool = { AXIsProcessTrusted() }
  ) {
    self.trustProvider = trustProvider
    self.pollInterval = pollInterval
    var continuation: AsyncStream<Bool>.Continuation?
    changes = AsyncStream { continuation = $0 }
    self.continuation = continuation!
  }

  public func start() {
    guard task == nil else {
      return
    }
    refresh()
    task = Task { [weak self] in
      while !Task.isCancelled {
        guard let self else {
          return
        }
        await self.poll()
        do {
          try await Task.sleep(for: pollInterval)
        } catch {
          return
        }
      }
    }
  }

  public func stop() {
    task?.cancel()
    task = nil
  }

  public func updatePollInterval(_ interval: Duration) {
    guard pollInterval != interval else {
      return
    }
    pollInterval = interval
    guard task != nil else {
      return
    }
    task?.cancel()
    task = nil
    start()
  }

  public func refresh() {
    poll()
  }

  public func promptIfRequested() -> Bool {
    AXIsProcessTrustedWithOptions(
      [
        kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
      ] as CFDictionary)
  }

  private func poll() {
    let trusted = trustProvider()
    guard lastValue != trusted else {
      return
    }
    lastValue = trusted
    continuation.yield(trusted)
  }
}
