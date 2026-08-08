import Testing
@testable import MPUI

@Test
@MainActor
func displayNameCanBeEmptyAndIsBounded() {
  let store = PulseStore()
  store.displayName = ""
  #expect(store.displayName.isEmpty)
  store.displayName = String(repeating: "a", count: 100)
  #expect(store.displayName.count == 80)
}
