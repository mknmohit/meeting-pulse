import Testing
@testable import MPUI

@Test
func recoveryPhraseUsesTheSpecifiedAutoHideWindow() {
  #expect(RecoveryTimerPolicy.autoHideAfter == .seconds(60))
}
