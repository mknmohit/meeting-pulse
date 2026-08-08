import Testing
@testable import MPUI

@Test
func onboardingAdvancesOnlyAfterPermission() {
  #expect(
    OnboardingProgress.shouldAutoAdvance(
      isPermissionStep: true,
      permissionGranted: true,
      didAutoAdvance: false
    )
  )
  #expect(
    !OnboardingProgress.shouldAutoAdvance(
      isPermissionStep: true,
      permissionGranted: false,
      didAutoAdvance: false
    )
  )
  #expect(
    !OnboardingProgress.shouldAutoAdvance(
      isPermissionStep: true,
      permissionGranted: true,
      didAutoAdvance: true
    )
  )
}
