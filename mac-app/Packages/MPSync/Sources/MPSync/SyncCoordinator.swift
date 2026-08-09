import Foundation
import MPCore

public actor SyncCoordinator {
  public enum State: Equatable, Sendable {
    case idle
    case retrying
    case superseded
  }

  public typealias StateChangeHandler = @MainActor @Sendable (State) async -> Void

  private let transport: any StatusTransport
  private let nonce: UUID
  private let retryPolicy: RetryPolicy
  private let sleep: @Sendable (Duration) async -> Void
  private let randomUnit: @Sendable () -> Double
  private let onStateChange: StateChangeHandler?
  private var pending: StatusPayload?
  private var drainTask: Task<Void, Never>?
  private var heartbeatTask: Task<Void, Never>?
  private var state: State = .idle
  private var successfulPayload: StatusPayload?
  private var lastSync: Date?

  public init(
    transport: any StatusTransport,
    nonce: UUID,
    retryPolicy: RetryPolicy = RetryPolicy(),
    sleep: @escaping @Sendable (Duration) async -> Void = { duration in
      try? await Task.sleep(for: duration)
    },
    randomUnit: @escaping @Sendable () -> Double = { Double.random(in: 0...1) },
    onStateChange: StateChangeHandler? = nil
  ) {
    self.transport = transport
    self.nonce = nonce
    self.retryPolicy = retryPolicy
    self.sleep = sleep
    self.randomUnit = randomUnit
    self.onStateChange = onStateChange
  }

  public var currentState: State {
    state
  }

  public var lastSuccessfulPayload: StatusPayload? {
    successfulPayload
  }

  public var lastSuccessfulSync: Date? {
    lastSync
  }

  public func submit(_ payload: StatusPayload) async {
    pending = payload
    if drainTask == nil {
      drainTask = Task { [weak self] in
        await self?.drain()
      }
    }
    await drainTask?.value
  }

  public func stop() {
    drainTask?.cancel()
    drainTask = nil
    heartbeatTask?.cancel()
    heartbeatTask = nil
  }

  public func startHeartbeat(
    interval: Duration = .seconds(60),
    payload: @escaping @Sendable () async -> StatusPayload
  ) {
    heartbeatTask?.cancel()
    heartbeatTask = Task { [weak self] in
      while !Task.isCancelled {
        guard let self else {
          return
        }
        await self.submit(await payload())
        do {
          try await Task.sleep(for: interval)
        } catch {
          return
        }
      }
    }
  }

  private func drain() async {
    defer {
      drainTask = nil
      if pending != nil, state != .superseded {
        drainTask = Task { [weak self] in
          await self?.drain()
        }
      }
    }

    var attempt = 0
    while pending != nil, state != .superseded {
      guard var payload = pending else {
        return
      }
      pending = nil

      while state != .superseded {
        do {
          let result = try await transport.publish(payload, nonce: nonce)
          if result.superseded {
            await setState(.superseded)
            return
          }
          successfulPayload = payload
          lastSync = result.lastSeenAt ?? Date()
          await setState(.idle)
          attempt = 0
          break
        } catch {
          await setState(.retrying)
          if let latest = pending {
            payload = latest
            pending = nil
            attempt = 0
            continue
          }
          let delay = retryPolicy.delay(
            for: attempt,
            randomUnit: randomUnit()
          )
          attempt += 1
          await sleep(delay)
        }
      }
    }
  }

  private func setState(_ newState: State) async {
    guard state != newState else {
      return
    }
    state = newState
    await onStateChange?(newState)
  }
}
