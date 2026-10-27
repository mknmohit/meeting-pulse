import Foundation
import Network

/// Watches connectivity and publishes de-duplicated transitions.
///
/// The monitor can be started and stopped repeatedly. Every `start()` creates a
/// fresh stream, so a coordinator that restarts after a network outage keeps
/// receiving updates instead of consuming a finished stream.
public final class NetworkMonitor: @unchecked Sendable {
  private let lock = NSLock()
  private let queue = DispatchQueue(label: "com.techdevix.meetingpulse.network")
  private var monitor: NWPathMonitor?
  private var continuation: AsyncStream<Bool>.Continuation?
  private var stream: AsyncStream<Bool>?
  private var isRunning = false
  private var hasPublishedInitial = false
  private var lastOnline = false

  /// The connectivity transitions of the current run.
  ///
  /// The stream is created by `start()`. Values published before the consumer
  /// starts iterating are buffered, so the current connectivity is never lost.
  public var changes: AsyncStream<Bool> {
    lock.lock()
    defer { lock.unlock() }
    if let stream {
      return stream
    }
    return AsyncStream { _ in }
  }

  /// Whether the last observed path was satisfied.
  public var isOnline: Bool {
    lock.lock()
    defer { lock.unlock() }
    return lastOnline
  }

  public init() {}

  public func start() {
    lock.lock()
    guard !isRunning else {
      lock.unlock()
      return
    }
    isRunning = true
    hasPublishedInitial = false
    lastOnline = false
    let monitor = NWPathMonitor()
    self.monitor = monitor
    var createdContinuation: AsyncStream<Bool>.Continuation?
    let createdStream = AsyncStream<Bool>(bufferingPolicy: .bufferingNewest(1)) { continuation in
      createdContinuation = continuation
    }
    stream = createdStream
    continuation = createdContinuation
    lock.unlock()

    monitor.pathUpdateHandler = { [weak self] path in
      self?.publish(path.status == .satisfied)
    }
    monitor.start(queue: queue)
  }

  public func stop() {
    lock.lock()
    isRunning = false
    let continuation = self.continuation
    self.continuation = nil
    stream = nil
    let monitor = self.monitor
    self.monitor = nil
    lock.unlock()

    monitor?.cancel()
    continuation?.finish()
  }

  private func publish(_ online: Bool) {
    lock.lock()
    let isFirst = !hasPublishedInitial
    let changed = online != lastOnline
    hasPublishedInitial = true
    lastOnline = online
    let continuation = self.continuation
    lock.unlock()

    guard isFirst || changed else {
      return
    }
    continuation?.yield(online)
  }
}
