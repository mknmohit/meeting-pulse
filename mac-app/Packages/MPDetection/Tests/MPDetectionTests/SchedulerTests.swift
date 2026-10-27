import MPCore
import Testing

@testable import MPDetection

struct SchedulerTests {
  @Test
  func activeSourceNeedsTwoInactiveSamplesToEnd() {
    var settler = ObservationSettler(value: .active)
    #expect(settler.apply(.inactive, settleCount: 2) == .active)
    #expect(settler.apply(.inactive, settleCount: 2) == .inactive)
  }

  @Test
  func unknownIsNotAVoteThatEndsAnActiveCall() {
    var settler = ObservationSettler(value: .active)

    // A single unknown sample must not turn a confirmed call into
    // "unavailable", and repeating it must not cancel a pending end either.
    #expect(settler.apply(.unknown, settleCount: 2) == .active)
    #expect(settler.apply(.unknown, settleCount: 2) == .active)
    #expect(settler.apply(.inactive, settleCount: 2) == .active)
    #expect(settler.apply(.inactive, settleCount: 2) == .inactive)
  }

  @Test
  func repeatedUnknownSettlesToUnknownWhenTheCallIsNotActive() {
    var settler = ObservationSettler(value: .inactive)
    #expect(settler.apply(.unknown, settleCount: 2) == .inactive)
    #expect(settler.apply(.unknown, settleCount: 2) == .unknown)
  }

  @Test
  func sourceAbsentUsesTheSameEndSettleRule() {
    var settler = ObservationSettler(value: .active)
    #expect(settler.apply(.sourceAbsent, settleCount: 2) == .active)
    #expect(settler.apply(.sourceAbsent, settleCount: 2) == .sourceAbsent)
  }

  @Test
  func activeObservationCancelsPendingEnd() {
    var settler = ObservationSettler(value: .active)
    #expect(settler.apply(.inactive, settleCount: 2) == .active)
    #expect(settler.apply(.active, settleCount: 2) == .active)
    #expect(settler.apply(.inactive, settleCount: 2) == .active)
  }

  @Test
  func tuningNeverAllowsZeroSettleCount() {
    #expect(DetectionTuning(endSettleCount: 0).endSettleCount == 1)
  }

  @Test
  func startupSeedsDetectorStateBeforeFirstStreamEmission() async {
    let meet = BootstrapDetector(
      sourceIdentifier: .googleMeet,
      initialObservation: .active
    )
    let slack = BootstrapDetector(
      sourceIdentifier: .slackHuddle,
      initialObservation: .sourceAbsent
    )
    let scheduler = DetectionScheduler(
      meet: meet,
      slack: slack,
      permissionProbe: GrantedPermission(),
      spaceChanges: EmptySpaceChangeSource()
    )
    let readings = await scheduler.readings

    await scheduler.start()

    var iterator = readings.makeAsyncIterator()
    let firstReading = await iterator.next()
    #expect(firstReading?.meet == .active)
    #expect(firstReading?.slack == .sourceAbsent)

    await scheduler.stop()
  }

  @Test
  func explicitSampleUsesCurrentStateWhenDetectorDoesNotEmit() async {
    let meet = BootstrapDetector(
      sourceIdentifier: .googleMeet,
      initialObservation: .inactive,
      sampleObservation: .active
    )
    let slack = BootstrapDetector(
      sourceIdentifier: .slackHuddle,
      initialObservation: .sourceAbsent
    )
    let scheduler = DetectionScheduler(
      meet: meet,
      slack: slack,
      permissionProbe: GrantedPermission(),
      spaceChanges: EmptySpaceChangeSource()
    )
    let readings = await scheduler.readings
    await scheduler.start()

    var iterator = readings.makeAsyncIterator()
    let initialReading = await iterator.next()
    let sampledReading = await iterator.next()
    #expect(initialReading?.meet == .inactive)
    #expect(sampledReading?.meet == .active)

    await scheduler.stop()
  }

  @Test
  func spaceChangeTriggersSettledResamples() async throws {
    let spaceChanges = TestSpaceChangeSource()
    let meet = BootstrapDetector(
      sourceIdentifier: .googleMeet,
      initialObservation: .active
    )
    let slack = BootstrapDetector(
      sourceIdentifier: .slackHuddle,
      initialObservation: .sourceAbsent
    )
    let scheduler = DetectionScheduler(
      meet: meet,
      slack: slack,
      permissionProbe: GrantedPermission(),
      spaceChanges: spaceChanges
    )

    await scheduler.start()
    spaceChanges.emit()
    try await Task.sleep(for: .milliseconds(1_100))

    #expect(await meet.spaceChangeCount == 1)
    #expect(await meet.sampleCount >= 3)
    await scheduler.stop()
  }
}

private struct GrantedPermission: PermissionProbe {
  let isTrusted = true
}

private final class EmptySpaceChangeSource: SpaceChangeSource, @unchecked Sendable {
  let changes: AsyncStream<Void> = AsyncStream { _ in }

  func start() {}

  func stop() {}
}

private final class TestSpaceChangeSource: SpaceChangeSource, @unchecked Sendable {
  let changes: AsyncStream<Void>
  private let continuation: AsyncStream<Void>.Continuation

  init() {
    var continuation: AsyncStream<Void>.Continuation?
    changes = AsyncStream { continuation = $0 }
    self.continuation = continuation!
  }

  func start() {}

  func stop() {}

  func emit() {
    continuation.yield(())
  }
}

private actor BootstrapDetector: MeetingDetector {
  nonisolated let sourceIdentifier: SourceID
  private let initialObservation: SourceObservation
  private let sampleObservation: SourceObservation?
  private var observation: SourceObservation = .unknown
  private var continuation: AsyncStream<SourceObservation>.Continuation?
  private(set) var sampleCount = 0
  private(set) var spaceChangeCount = 0

  let observationStream: AsyncStream<SourceObservation>

  var currentObservation: SourceObservation {
    observation
  }

  var health: DetectorHealth = .ok

  init(
    sourceIdentifier: SourceID,
    initialObservation: SourceObservation,
    sampleObservation: SourceObservation? = nil
  ) {
    self.sourceIdentifier = sourceIdentifier
    self.initialObservation = initialObservation
    self.sampleObservation = sampleObservation
    var continuation: AsyncStream<SourceObservation>.Continuation?
    observationStream = AsyncStream { continuation = $0 }
    self.continuation = continuation
  }

  func start() async {
    // Deliberately do not yield. The scheduler must seed current state itself.
    observation = initialObservation
  }

  func stop() async {
    continuation?.finish()
  }

  func invalidate() async {
    observation = .unknown
    continuation?.yield(.unknown)
  }

  func requestSample() async {
    sampleCount += 1
    if let sampleObservation {
      observation = sampleObservation
    }
  }

  func spaceDidChange() async {
    spaceChangeCount += 1
  }
}
