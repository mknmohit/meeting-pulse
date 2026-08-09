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
  func unknownNeverSettlesToInactive() {
    var settler = ObservationSettler(value: .active)
    #expect(settler.apply(.unknown, settleCount: 2) == .unknown)
    #expect(settler.apply(.inactive, settleCount: 2) == .inactive)
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
      permissionProbe: GrantedPermission()
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
      permissionProbe: GrantedPermission()
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
}

private struct GrantedPermission: PermissionProbe {
  let isTrusted = true
}

private actor BootstrapDetector: MeetingDetector {
  nonisolated let sourceIdentifier: SourceID
  private let initialObservation: SourceObservation
  private let sampleObservation: SourceObservation?
  private var observation: SourceObservation = .unknown
  private var continuation: AsyncStream<SourceObservation>.Continuation?

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
    if let sampleObservation {
      observation = sampleObservation
    }
  }
}
