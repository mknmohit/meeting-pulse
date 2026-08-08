public enum OnboardingProgress {
  public static func shouldAutoAdvance(
    isPermissionStep: Bool,
    permissionGranted: Bool,
    didAutoAdvance: Bool
  ) -> Bool {
    isPermissionStep && permissionGranted && !didAutoAdvance
  }
}
