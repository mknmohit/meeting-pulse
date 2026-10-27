import Testing

@testable import MPSync

struct RetryPolicyTests {
  @Test
  func equalJitterStaysWithinExponentialCap() {
    let policy = RetryPolicy()
    #expect(policy.delay(for: 0, randomUnit: 1) == .seconds(1))
    #expect(policy.delay(for: 1, randomUnit: 1) == .seconds(2))
    #expect(policy.delay(for: 7, randomUnit: 1) == .seconds(60))
    // The lower jitter bound keeps a retry loop from spinning without pause.
    #expect(policy.delay(for: 3, randomUnit: 0) == .seconds(4))
  }

  @Test
  func randomUnitIsClamped() {
    let policy = RetryPolicy()
    #expect(policy.delay(for: 0, randomUnit: -1) == .seconds(0.5))
    #expect(policy.delay(for: 0, randomUnit: 2) == .seconds(1))
  }

  @Test
  func everyRetryWaitsAtLeastHalfTheBackoff() {
    let policy = RetryPolicy()
    for attempt in 0..<8 {
      let delay = policy.delay(for: attempt, randomUnit: 0)
      #expect(delay >= .milliseconds(500))
    }
  }

  @Test
  func bufferKeepsOnlyTheLatestPayload() {
    var buffer = LatestPayloadBuffer<String>()
    buffer.replace(with: "A")
    buffer.replace(with: "B")
    #expect(buffer.hasValue)
    #expect(buffer.take() == "B")
    #expect(!buffer.hasValue)
  }
}
