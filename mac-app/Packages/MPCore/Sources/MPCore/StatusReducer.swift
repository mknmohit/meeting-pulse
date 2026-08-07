public enum StatusReducer {
  public static func reduce(_ input: ReducerInput) -> EffectiveStatus {
    if let override = input.override, override.isActive(at: input.monotonicNow) {
      return EffectiveStatus(
        state: override.state,
        callOkay: input.callOkay,
        isOverridden: true,
        reason: .manualOverride
      )
    }

    if input.meet == .active || input.slack == .active {
      return EffectiveStatus(
        state: .busy,
        callOkay: input.callOkay,
        isOverridden: false,
        reason: .confirmedActiveSource
      )
    }

    guard input.accessibilityGranted else {
      return EffectiveStatus(
        state: .unavailable,
        callOkay: input.callOkay,
        isOverridden: false,
        reason: .permissionDenied
      )
    }

    if input.meet == .unknown || input.slack == .unknown {
      return EffectiveStatus(
        state: .unavailable,
        callOkay: input.callOkay,
        isOverridden: false,
        reason: .untrustedSource
      )
    }

    return EffectiveStatus(
      state: .available,
      callOkay: input.callOkay,
      isOverridden: false,
      reason: .allSourcesInactive
    )
  }
}
