import Testing
@testable import MPUI

struct SetupChecklistTests {
  @Test
  func permissionIsTheFirstStepUntilTrustIsObserved() {
    #expect(
      SetupChecklistProgress.current(
        accessibilityGranted: false,
        hasViewerLink: false
      ) == .accessibility
    )
    #expect(
      SetupChecklistProgress.current(
        accessibilityGranted: false,
        hasViewerLink: true
      ) == .accessibility
    )
  }

  @Test
  func linkIsTheActiveStepAfterPermission() {
    #expect(
      SetupChecklistProgress.current(
        accessibilityGranted: true,
        hasViewerLink: false
      ) == .link
    )
  }

  @Test
  func watchingIsTheFinalStepWhenLinkExists() {
    #expect(
      SetupChecklistProgress.current(
        accessibilityGranted: true,
        hasViewerLink: true
      ) == .watching
    )
  }
}
