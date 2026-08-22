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

  public init(
    meet: SourceObservation,
    slack: SourceObservation,
    accessibilityGranted: Bool
  ) {
    self.meet = meet
    self.slack = slack
    self.accessibilityGranted = accessibilityGranted
  }
}

struct ObservationSettler: Sendable {
  private(set) var value: SourceObservation
  private var pendingNonActive = 0

  init(value: SourceObservation = .unknown) {
    self.value = value
  }

  mutating func apply(_ next: SourceObservation, settleCount: Int) -> SourceObservation {
    guard next != .active else {
      pendingNonActive = 0
      value = .active
      return value
    }
    guard value == .active else {
      pendingNonActive = 0
      value = next
      return value
    }
    guard next == .inactive || next == .sourceAbsent else {
      pendingNonActive = 0
      value = .unknown
      return value
    }
    pendingNonActive += 1
    if pendingNonActive >= settleCount {
      pendingNonActive = 0
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
    _ = ingest(
      source: .googleMeet,
      value: await meet.currentObservation,
      emitReading: false
    )
    _ = ingest(
      source: .slackHuddle,
      value: await slack.currentObservation,
      emitReading: false
    )
    emit()
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
    emit()
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
      emit()
    }
    if trusted {
      await meet.requestSample()
      await slack.requestSample()
      let meetChanged = ingest(
        source: .googleMeet,
        value: await meet.currentObservation,
        emitReading: false
      )
      let slackChanged = ingest(
        source: .slackHuddle,
        value: await slack.currentObservation,
        emitReading: false
      )
      if meetChanged || slackChanged {
        emit()
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
  ) -> Bool {
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
      emit()
    }
    scheduleTimer()
    return changed
  }

  private func emit() {
    continuation.yield(
      SchedulerReading(
        meet: meetSettler.value,
        slack: slackSettler.value,
        accessibilityGranted: accessibilityGranted
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
