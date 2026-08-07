import Foundation
import Network

public final class NetworkMonitor: @unchecked Sendable {
  public let changes: AsyncStream<Bool>

  private let monitor: NWPathMonitor
  private let queue: DispatchQueue
  private let continuation: AsyncStream<Bool>.Continuation

  public init() {
    monitor = NWPathMonitor()
    queue = DispatchQueue(label: "com.techdevix.meetingpulse.network")
    var continuation: AsyncStream<Bool>.Continuation?
    changes = AsyncStream { continuation = $0 }
    self.continuation = continuation!
  }

  public func start() {
    monitor.pathUpdateHandler = { [continuation] path in
      continuation.yield(path.status == .satisfied)
    }
    monitor.start(queue: queue)
  }

  public func stop() {
    monitor.cancel()
    continuation.finish()
  }
}
