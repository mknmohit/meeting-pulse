import ApplicationServices
import CoreFoundation
import Foundation
import MPCore

public final class AXRunLoopHost: AXElementTree, AXEventSource, @unchecked Sendable {
  public static let shared = AXRunLoopHost()

  public let events: AsyncStream<AXEvent>

  private var thread: Thread?
  private let ready = DispatchSemaphore(value: 0)
  private let eventContinuation: AsyncStream<AXEvent>.Continuation
  private let workLock = NSLock()
  private var workItems = [@Sendable () -> Void]()
  private var runLoop: CFRunLoop?
  private var workSource: CFRunLoopSource?
  private var observers = [pid_t: AXObserver]()
  private var observerContexts = [pid_t: ObserverContext]()
  private var stopped = false

  public init() {
    var continuation: AsyncStream<AXEvent>.Continuation?
    events = AsyncStream(bufferingPolicy: .bufferingNewest(1)) {
      continuation = $0
    }
    eventContinuation = continuation!
    thread = nil
    let thread = Thread { [weak self] in
      self?.run()
    }
    thread.name = "com.techdevix.meetingpulse.ax"
    self.thread = thread
    thread.start()
    ready.wait()
  }

  deinit {
    workLock.lock()
    stopped = true
    workItems.removeAll()
    workLock.unlock()
    eventContinuation.finish()
    if let runLoop {
      CFRunLoopStop(runLoop)
      CFRunLoopWakeUp(runLoop)
    }
  }

  public func snapshot(
    pid: pid_t,
    maxDepth: Int,
    maxElements: Int
  ) async throws -> AXSnapshot {
    try await performThrowing {
      guard AXIsProcessTrusted() else {
        throw AXSnapshotError.permissionDenied
      }
      let application = AXUIElementCreateApplication(pid)
      return try makeSnapshot(
        application: application,
        processIdentifier: pid,
        maxDepth: maxDepth,
        maxElements: maxElements
      )
    }
  }

  public func observe(pid: pid_t, notifications: [String]) async throws {
    try await performThrowing {
      guard AXIsProcessTrusted() else {
        throw AXSnapshotError.permissionDenied
      }
      let application = AXUIElementCreateApplication(pid)
      var observer: AXObserver?
      let createObserver:
        (
          pid_t,
          AXObserverCallback,
          UnsafeMutablePointer<AXObserver?>
        ) -> AXError = AXObserverCreate
      let result = createObserver(pid, axObserverCallback, &observer)
      guard result == .success, let observer else {
        throw AXSnapshotError.unreadable(result.rawValue)
      }

      let context = ObserverContext(host: self, processIdentifier: pid)
      for notification in notifications {
        let addResult = AXObserverAddNotification(
          observer,
          application,
          notification as CFString,
          Unmanaged.passUnretained(context).toOpaque()
        )
        guard addResult == .success || addResult == .notificationAlreadyRegistered else {
          throw AXSnapshotError.unreadable(addResult.rawValue)
        }
      }
      self.observerContexts[pid] = context
      self.observers[pid] = observer
      CFRunLoopAddSource(
        CFRunLoopGetCurrent(),
        AXObserverGetRunLoopSource(observer),
        CFRunLoopMode.defaultMode!
      )
    }
  }

  public func stopObserving(pid: pid_t) async {
    try? await performThrowing {
      guard let observer = self.observers.removeValue(forKey: pid) else {
        return
      }
      self.observerContexts.removeValue(forKey: pid)
      CFRunLoopRemoveSource(
        CFRunLoopGetCurrent(),
        AXObserverGetRunLoopSource(observer),
        CFRunLoopMode.defaultMode!
      )
    }
  }

  func yieldEvent(_ event: AXEvent) {
    eventContinuation.yield(event)
  }

  private func performThrowing<T: Sendable>(
    _ body: @escaping @Sendable () throws -> T
  ) async throws -> T {
    try await withCheckedThrowingContinuation { continuation in
      let accepted = schedule {
        do {
          continuation.resume(returning: try body())
        } catch {
          continuation.resume(throwing: error)
        }
      }
      if !accepted {
        // The host is gone and the work can never run. The caller still has
        // to be released, otherwise the detector waits for a reading that
        // will never arrive.
        do {
          continuation.resume(returning: try body())
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }

  /// Hands work to the accessibility thread.
  ///
  /// The result reports whether the work was accepted. A work item that is
  /// dropped silently leaves its caller waiting forever, so the caller needs
  /// to know that the host can no longer run the work.
  private func schedule(_ body: @escaping @Sendable () -> Void) -> Bool {
    workLock.lock()
    let accepted = runLoop != nil && workSource != nil && !stopped
    if accepted {
      workItems.append(body)
    }
    workLock.unlock()
    guard accepted else {
      return false
    }
    CFRunLoopSourceSignal(workSource!)
    CFRunLoopWakeUp(runLoop!)
    return true
  }

  private func run() {
    runLoop = CFRunLoopGetCurrent()
    var context = CFRunLoopSourceContext(
      version: 0,
      info: Unmanaged.passUnretained(self).toOpaque(),
      retain: nil,
      release: nil,
      copyDescription: nil,
      equal: nil,
      hash: nil,
      schedule: nil,
      cancel: nil,
      perform: { info in
        guard let info else {
          return
        }
        let host = Unmanaged<AXRunLoopHost>.fromOpaque(info).takeUnretainedValue()
        host.drainWork()
      }
    )
    if let source = CFRunLoopSourceCreate(nil, 0, &context) {
      workSource = source
      CFRunLoopAddSource(CFRunLoopGetCurrent(), source, CFRunLoopMode.defaultMode!)
    }
    ready.signal()
    // The previous implementation used a 1-second timeout, which meant the
    // dedicated AX thread woke up roughly every second even when no
    // notifications were pending. The thread is correctly woken by
    // `CFRunLoopWakeUp` whenever `schedule(...)` is invoked, so a 30-second
    // timeout keeps observers responsive while removing the 1 Hz spin that
    // contributed to steady CPU/RAM overhead.
    while true {
      let result = CFRunLoopRunInMode(
        CFRunLoopMode.defaultMode!,
        30,
        false
      )
      if result == .stopped {
        break
      }
    }
  }

  private func drainWork() {
    workLock.lock()
    let work = workItems
    workItems.removeAll()
    workLock.unlock()
    for item in work {
      item()
    }
  }
}

private final class ObserverContext: @unchecked Sendable {
  weak var host: AXRunLoopHost?
  let processIdentifier: pid_t

  init(host: AXRunLoopHost, processIdentifier: pid_t) {
    self.host = host
    self.processIdentifier = processIdentifier
  }
}

private func axObserverCallback(
  _: AXObserver,
  _: AXUIElement,
  notification: CFString,
  refcon: UnsafeMutableRawPointer?
) {
  guard let refcon else {
    return
  }
  let context = Unmanaged<ObserverContext>.fromOpaque(refcon).takeUnretainedValue()
  context.host?.yieldEvent(
    AXEvent(
      processIdentifier: context.processIdentifier,
      notification: notification as String
    )
  )
}
