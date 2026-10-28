import Dispatch
import MPCore

public struct DetectionTuning: Codable, Equatable, Sendable {
  public var idleSampleInterval: Duration
  public var activeSampleInterval: Duration
  public var endSettleCount: Int
  public var timerLeeway: Duration

  public init(
    idleSampleInterval: Duration = .seconds(20),
    activeSampleInterval: Duration = .seconds(5),
    endSettleCount: Int = 2,
    timerLeeway: Duration = .milliseconds(500)
  ) {
    self.idleSampleInterval = idleSampleInterval
    self.activeSampleInterval = activeSampleInterval
    self.endSettleCount = max(endSettleCount, 1)
    self.timerLeeway = timerLeeway
  }
}

public struct SchedulerReading: Equatable, Sendable {
  public let meet: SourceObservation
  public let slack: SourceObservation
  public let accessibilityGranted: Bool
  /// The health of the Meet detector at the time of the reading.
  public let meetHealth: DetectorHealth
  /// The health of the Slack detector at the time of the reading.
  public let slackHealth: DetectorHealth

  public init(
    meet: SourceObservation,
    slack: SourceObservation,
    accessibilityGranted: Bool,
    meetHealth: DetectorHealth = .ok,
    slackHealth: DetectorHealth = .ok
  ) {
    self.meet = meet
    self.slack = slack
    self.accessibilityGranted = accessibilityGranted
    self.meetHealth = meetHealth
    self.slackHealth = slackHealth
  }
}

/// Smooths the raw per-sample observations of a single source.
///
/// The rules are deliberately asymmetric:
///
/// * `.active` is believed immediately — a confirmed call must never be hidden.
/// * `.unknown` is *not a vote*. It means "this sample could not tell", so it
///   never flips the value on its own and never cancels an end that is already
///   settling. It only becomes visible when it repeats.
/// * A definite end (`.inactive` / `.sourceAbsent`) that follows an `.active`
///   needs `settleCount` agreeing samples before it is published.
/// * A definite value that follows a non-active value applies immediately.
///
/// The previous implementation flipped an `.active` value to `.unknown` on a
/// single noisy sample, which surfaced as a "Meeting status unavailable" flash
/// for every transient accessibility hiccup.
struct ObservationSettler: Sendable {
  private(set) var value: SourceObservation
  /// The definite candidate that is currently settling.
  private var pendingCandidate: SourceObservation?
  /// How many samples in a row agreed on `pendingCandidate`.
  private var pendingCount = 0
  /// How many consecutive `.unknown` samples were seen.
  private var unknownCount = 0

  init(value: SourceObservation = .unknown) {
    self.value = value
  }

  mutating func apply(_ next: SourceObservation, settleCount: Int) -> SourceObservation {
    let required = max(settleCount, 1)

    if next == .active {
      pendingCandidate = nil
      pendingCount = 0
      unknownCount = 0
      value = .active
      return value
    }

    if next == .unknown {
      // Unknown neither flips the value nor cancels a pending end. It only
      // surfaces once it keeps repeating, so a single bad sample is ignored.
      unknownCount += 1
      if value != .active, unknownCount >= required {
        unknownCount = 0
        value = .unknown
      }
      return value
    }

    // A definite observation: the call is over or the source is gone.
    unknownCount = 0
    guard value == .active else {
      pendingCandidate = nil
      pendingCount = 0
      value = next
      return value
    }

    if pendingCandidate != next {
      pendingCandidate = next
      pendingCount = 0
    }
    pendingCount += 1
    if pendingCount >= required {
      pendingCandidate = nil
      pendingCount = 0
      value = next
    }
    return value
  }
}

public actor DetectionScheduler {
  private let meet: any MeetingDetector
  private let slack: any MeetingDetector
  private let permissionProbe: any PermissionProbe
  private let spaceChanges: any SpaceChangeSource
  private var tuning: DetectionTuning
  private var timer: DispatchSourceTimer?
  private var scheduledInterval: Duration?
  private var meetTask: Task<Void, Never>?
  private var slackTask: Task<Void, Never>?
  private var spaceTask: Task<Void, Never>?
  private var spaceResampleTask: Task<Void, Never>?
  private var running = false
  private var meetSettler = ObservationSettler()
  private var slackSettler = ObservationSettler()
  private var accessibilityGranted = false
  private var continuation: AsyncStream<SchedulerReading>.Continuation

  public let readings: AsyncStream<SchedulerReading>

  public init(
    meet: any MeetingDetector,
    slack: any MeetingDetector,
    permissionProbe: any PermissionProbe = AccessibilityPermissionProbe(),
    tuning: DetectionTuning = DetectionTuning(),
    spaceChanges: any SpaceChangeSource = WorkspaceSpaceChangeSource()
  ) {
    self.meet = meet
    self.slack = slack
    self.permissionProbe = permissionProbe
    self.spaceChanges = spaceChanges
    self.tuning = tuning
    var continuation: AsyncStream<SchedulerReading>.Continuation?
    readings = AsyncStream { continuation = $0 }
    self.continuation = continuation!
  }

  public func start() async {
    guard !running else {
      return
    }
    running = true
    accessibilityGranted = permissionProbe.isTrusted
    let meetReadings = await meet.observationStream
    let slackReadings = await slack.observationStream
    meetTask = Task { [weak self] in
      for await value in meetReadings {
        _ = await self?.ingest(source: .googleMeet, value: value)
      }
    }
    slackTask = Task { [weak self] in
      for await value in slackReadings {
        _ = await self?.ingest(source: .slackHuddle, value: value)
      }
    }
    let spaceChanges = spaceChanges.changes
    self.spaceChanges.start()
    spaceTask = Task { [weak self] in
      for await _ in spaceChanges {
        await self?.handleSpaceChange()
      }
    }
    await meet.start()
    await slack.start()
    _ = await ingest(
      source: .googleMeet,
      value: await meet.currentObservation,
      emitReading: false
    )
    _ = await ingest(
      source: .slackHuddle,
      value: await slack.currentObservation,
      emitReading: false
    )
    await emit()
    await tick()
  }

  public func stop() async {
    running = false
    timer?.cancel()
    timer = nil
    scheduledInterval = nil
    meetTask?.cancel()
    slackTask?.cancel()
    spaceTask?.cancel()
    spaceResampleTask?.cancel()
    meetTask = nil
    slackTask = nil
    spaceTask = nil
    spaceResampleTask = nil
    spaceChanges.stop()
    await meet.stop()
    await slack.stop()
  }

  public func requestImmediateSample() async {
    await tick()
    await emit()
  }

  public func updateTuning(_ tuning: DetectionTuning) {
    self.tuning = tuning
    scheduledInterval = nil
    scheduleTimer()
  }

  private func tick() async {
    guard running else {
      return
    }
    let trusted = permissionProbe.isTrusted
    if trusted != accessibilityGranted {
      accessibilityGranted = trusted
      await meet.invalidate()
      await slack.invalidate()
      meetSettler = ObservationSettler(value: .unknown)
      slackSettler = ObservationSettler(value: .unknown)
      await emit()
    }
    if trusted {
      await meet.requestSample()
      await slack.requestSample()
      let meetChanged = await ingest(
        source: .googleMeet,
        value: await meet.currentObservation,
        emitReading: false
      )
      let slackChanged = await ingest(
        source: .slackHuddle,
        value: await slack.currentObservation,
        emitReading: false
      )
      if meetChanged || slackChanged {
        await emit()
      }
    }
    scheduleTimer()
  }

  private func handleSpaceChange() async {
    guard running else {
      return
    }
    await meet.spaceDidChange()
    await slack.spaceDidChange()
    spaceResampleTask?.cancel()
    spaceResampleTask = Task { [weak self] in
      do {
        try await Task.sleep(for: .milliseconds(300))
      } catch {
        return
      }
      guard !Task.isCancelled else {
        return
      }
      await self?.tick()
      do {
        try await Task.sleep(for: .milliseconds(700))
      } catch {
        return
      }
      guard !Task.isCancelled else {
        return
      }
      await self?.tick()
    }
  }

  private func ingest(
    source: SourceID,
    value: SourceObservation,
    emitReading: Bool = true
  ) async -> Bool {
    let previous: SourceObservation
    let next: SourceObservation
    switch source {
    case .googleMeet:
      previous = meetSettler.value
      next = meetSettler.apply(value, settleCount: tuning.endSettleCount)
    case .slackHuddle:
      previous = slackSettler.value
      next = slackSettler.apply(value, settleCount: tuning.endSettleCount)
    }
    let changed = previous != next
    if emitReading && changed {
      await emit()
    }
    scheduleTimer()
    return changed
  }

  private func emit() async {
    continuation.yield(
      SchedulerReading(
        meet: meetSettler.value,
        slack: slackSettler.value,
        accessibilityGranted: accessibilityGranted,
        meetHealth: await meet.health,
        slackHealth: await slack.health
      )
    )
  }

  private func scheduleTimer() {
    guard running else {
      return
    }
    let interval =
      meetSettler.value == .active || slackSettler.value == .active
      ? tuning.activeSampleInterval
      : tuning.idleSampleInterval
    guard timer == nil || scheduledInterval != interval else {
      return
    }
    timer?.cancel()
    let source = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
    let nanoseconds = Int(clamping: max(interval.nanoseconds, 1))
    let leeway = Int(clamping: max(tuning.timerLeeway.nanoseconds, 0))
    source.schedule(
      deadline: DispatchTime.now() + .nanoseconds(nanoseconds),
      repeating: .nanoseconds(nanoseconds),
      leeway: .nanoseconds(leeway)
    )
    let scheduler = self
    source.setEventHandler {
      Task {
        await scheduler.tick()
      }
    }
    timer = source
    scheduledInterval = interval
    source.resume()
  }
}

extension Duration {
  fileprivate var nanoseconds: Int64 {
    let components = components
    let seconds = components.seconds.multipliedReportingOverflow(by: 1_000_000_000)
    let attoseconds = components.attoseconds / 1_000_000_000
    if seconds.overflow {
      return Int64.max
    }
    return seconds.partialValue &+ attoseconds
  }
}
