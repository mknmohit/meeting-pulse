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
}
