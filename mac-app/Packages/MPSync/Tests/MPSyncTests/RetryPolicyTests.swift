import Testing

@testable import MPSync

struct RetryPolicyTests {
  @Test
  func fullJitterStaysWithinExponentialCap() {
    let policy = RetryPolicy()
    #expect(policy.delay(for: 0, randomUnit: 1) == .seconds(1))
    #expect(policy.delay(for: 1, randomUnit: 1) == .seconds(2))
    #expect(policy.delay(for: 7, randomUnit: 1) == .seconds(60))
    #expect(policy.delay(for: 3, randomUnit: 0) == .zero)
  }

  @Test
  func randomUnitIsClamped() {
    let policy = RetryPolicy()
    #expect(policy.delay(for: 0, randomUnit: -1) == .zero)
    #expect(policy.delay(for: 0, randomUnit: 2) == .seconds(1))
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
