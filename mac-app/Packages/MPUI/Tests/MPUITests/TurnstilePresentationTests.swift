import Testing
@testable import MPUI

@Test
@MainActor
func turnstilePresentationStartsHiddenAndCanCollapse() {
  let store = PulseStore()
  #expect(store.turnstilePresentation == .hidden)

  store.turnstilePresentation = .verifying
  #expect(store.turnstilePresentation == .verifying)

  store.turnstilePresentation = .hidden
  #expect(store.turnstilePresentation == .hidden)
}
