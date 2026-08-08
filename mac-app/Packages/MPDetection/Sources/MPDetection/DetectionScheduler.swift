import Dispatch
import MPCore

public struct DetectionTuning: Codable, Equatable, Sendable {
  public var idleSampleInterval: Duration
  public var activeSampleInterval: Duration
  public var endSettleCount: Int
  public var maxLatchDuration: Duration
  public var timerLeeway: Duration

  public init(
    idleSampleInterval: Duration = .seconds(15),
    activeSampleInterval: Duration = .seconds(2),
    endSettleCount: Int = 2,
    maxLatchDuration: Duration = .seconds(14_400),
    timerLeeway: Duration = .milliseconds(500)
  ) {
    self.idleSampleInterval = idleSampleInterval
    self.activeSampleInterval = activeSampleInterval
    self.endSettleCount = max(endSettleCount, 1)
    self.maxLatchDuration = maxLatchDuration
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
  private var tuning: DetectionTuning
  private var timer: DispatchSourceTimer?
  private var meetTask: Task<Void, Never>?
  private var slackTask: Task<Void, Never>?
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
    tuning: DetectionTuning = DetectionTuning()
  ) {
    self.meet = meet
    self.slack = slack
    self.permissionProbe = permissionProbe
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
    await meet.start()
    await slack.start()
    let meetReadings = await meet.observationStream
    let slackReadings = await slack.observationStream
    meetTask = Task { [weak self] in
      for await value in meetReadings {
        await self?.ingest(source: .googleMeet, value: value)
      }
    }
    slackTask = Task { [weak self] in
      for await value in slackReadings {
        await self?.ingest(source: .slackHuddle, value: value)
      }
    }
    emit()
    await tick()
  }

  public func stop() async {
    running = false
    timer?.cancel()
    timer = nil
    meetTask?.cancel()
    slackTask?.cancel()
    meetTask = nil
    slackTask = nil
    await meet.stop()
    await slack.stop()
  }

  public func requestImmediateSample() async {
    await tick()
    emit()
  }

  public func updateTuning(_ tuning: DetectionTuning) {
    self.tuning = tuning
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
    }
    scheduleTimer()
  }

  private func ingest(source: SourceID, value: SourceObservation) {
    switch source {
    case .googleMeet:
      _ = meetSettler.apply(value, settleCount: tuning.endSettleCount)
    case .slackHuddle:
      _ = slackSettler.apply(value, settleCount: tuning.endSettleCount)
    }
    emit()
    scheduleTimer()
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
    timer?.cancel()
    let interval =
      meetSettler.value == .active || slackSettler.value == .active
      ? tuning.activeSampleInterval
      : tuning.idleSampleInterval
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
