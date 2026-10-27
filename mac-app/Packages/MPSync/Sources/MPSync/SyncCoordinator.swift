import Foundation
import MPCore

public actor SyncCoordinator {
  public enum State: Equatable, Sendable {
    case idle
    case retrying
    case superseded
  }

  public typealias StateChangeHandler = @MainActor @Sendable (State) async -> Void
  /// Returns a fresh instance nonce for the paired device.
  ///
  /// The handler is consulted when the remote side reports that the publish
  /// was superseded, which means the device was re-bound somewhere else.
  public typealias NonceRefreshHandler = @Sendable () async -> UUID?
  /// Re-registers the paired device and returns the fresh registration.
  ///
  /// The handler is consulted when the remote side can no longer resolve the
  /// device for the current identity.
  public typealias DeviceRecoveryHandler = @Sendable () async -> DeviceRegistration?

  /// Upper bound for a single publish request.
  ///
  /// A publish must never block the retry loop forever, for example when the
  /// network drops in the middle of a request.
  public static let publishTimeout: Duration = .seconds(30)

  private let transport: any StatusTransport
  private var nonce: UUID
  private let retryPolicy: RetryPolicy
  private let sleep: @Sendable (Duration) async -> Void
  private let randomUnit: @Sendable () -> Double
  private let onStateChange: StateChangeHandler?
  private let nonceRefresh: NonceRefreshHandler?
  private let deviceRecovery: DeviceRecoveryHandler?
  private let publishTimeout: Duration
  private var pending: StatusPayload?
  private var drainTask: Task<Void, Never>?
  private var heartbeatTask: Task<Void, Never>?
  private var state: State = .idle
  private var successfulPayload: StatusPayload?
  private var lastSync: Date?
  private var attempt = 0

  public init(
    transport: any StatusTransport,
    nonce: UUID,
    retryPolicy: RetryPolicy = RetryPolicy(),
    sleep: @escaping @Sendable (Duration) async -> Void = { duration in
      try? await Task.sleep(for: duration)
    },
    randomUnit: @escaping @Sendable () -> Double = { Double.random(in: 0...1) },
    onStateChange: StateChangeHandler? = nil,
    nonceRefresh: NonceRefreshHandler? = nil,
    deviceRecovery: DeviceRecoveryHandler? = nil,
    publishTimeout: Duration = SyncCoordinator.publishTimeout
  ) {
    self.transport = transport
    self.nonce = nonce
    self.retryPolicy = retryPolicy
    self.sleep = sleep
    self.randomUnit = randomUnit
    self.onStateChange = onStateChange
    self.nonceRefresh = nonceRefresh
    self.deviceRecovery = deviceRecovery
    self.publishTimeout = publishTimeout
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

  /// Queues a payload for publishing.
  ///
  /// The call returns as soon as the payload is queued: publishing happens in
  /// the background so a stalled network can no longer freeze the caller
  /// (the detection loop and the heartbeat used to block here).
  public func submit(_ payload: StatusPayload) async {
    pending = payload
    armDrain()
  }

  /// Waits until the queued payloads have been published or have failed.
  public func waitForCompletion() async {
    await drainTask?.value
  }

  /// Notifies the coordinator that connectivity is available again.
  ///
  /// The backoff is reset so a pending payload is published right away instead
  /// of waiting out the remaining retry delay.
  public func connectionRestored() async {
    attempt = 0
    if pending != nil {
      armDrain()
    }
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

  private func armDrain() {
    guard drainTask == nil else {
      return
    }
    drainTask = Task { [weak self] in
      await self?.drain()
    }
  }

  private func drain() async {
    defer {
      drainTask = nil
      if pending != nil {
        armDrain()
      }
    }

    while !Task.isCancelled {
      guard let payload = takePending() else {
        return
      }
      await publishWithRetry(payload)
    }
  }

  private func takePending() -> StatusPayload? {
    defer { pending = nil }
    return pending
  }

  private func publishWithRetry(_ payload: StatusPayload) async {
    var current = payload
    while !Task.isCancelled {
      do {
        let result = try await publish(current)
        if result.superseded {
          // The device was re-bound elsewhere, so a fresh nonce is required
          // before the next publish can succeed.
          guard let refreshed = await refreshNonce() else {
            await setState(.superseded)
            return
          }
          nonce = refreshed
          attempt = 0
          continue
        }
        successfulPayload = current
        lastSync = result.lastSeenAt ?? Date()
        attempt = 0
        await setState(.idle)
        return
      } catch {
        if isDeviceUnregistered(error), let registration = await recoverDevice() {
          nonce = registration.instanceNonce
          attempt = 0
          continue
        }
        await setState(.retrying)
        if let latest = takePending() {
          current = latest
          attempt = 0
          continue
        }
        let delay = retryPolicy.delay(for: attempt, randomUnit: randomUnit())
        attempt += 1
        await sleep(delay)
        if Task.isCancelled {
          return
        }
      }
    }
  }

  private func publish(_ payload: StatusPayload) async throws -> PublishResult {
    let transport = self.transport
    let nonce = self.nonce
    let timeout = publishTimeout
    return try await withDeadline(timeout) {
      try await transport.publish(payload, nonce: nonce)
    }
  }

  private func refreshNonce() async -> UUID? {
    guard let nonceRefresh else {
      return nil
    }
    return await nonceRefresh()
  }

  private func recoverDevice() async -> DeviceRegistration? {
    guard let deviceRecovery else {
      return nil
    }
    return await deviceRecovery()
  }

  private func isDeviceUnregistered(_ error: Error) -> Bool {
    guard let transportError = error as? SupabaseStatusTransport.TransportError else {
      return false
    }
    return transportError == .deviceNotRegistered
  }

  private func setState(_ newState: State) async {
    guard state != newState else {
      return
    }
    state = newState
    await onStateChange?(newState)
  }
}
