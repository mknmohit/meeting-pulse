import Foundation
import MPCore
import MPSupport

public enum ReasonLineBuilder {
  public static func build(
    deleteCompleted: Bool,
    accessibilityGranted: Bool,
    syncState: SyncState,
    hasViewerLink: Bool,
    mode: PulseMode,
    overrideExpiry: Date?,
    stateReason: StatusReason?,
    callsOkay: Bool,
    face: PlateFace,
    activeSource: String? = nil,
    now: Date = .now
  ) -> (String, ReasonTone) {
    if deleteCompleted {
      return (MPString.mast.resetComplete, .alert)
    }
    if !accessibilityGranted {
      return (MPString.mast.reasonAccessibilityMissing, .caution)
    }
    if syncState == .superseded {
      return (MPString.mast.reasonSuperseded, .alert)
    }
    if syncState == .retrying {
      return (MPString.mast.reasonUnreachable, .caution)
    }
    if !hasViewerLink {
      return (MPString.mast.reasonNoViewer, .info)
    }
    if mode == .busy, let overrideExpiry {
      return (
        MPString.mast.busyFor(minutes: remainingMinutes(until: overrideExpiry, now: now)),
        .info
      )
    }
    if mode == .busy {
      return (MPString.mast.reasonBusyUntil, .info)
    }
    if mode == .available, let overrideExpiry {
      return (
        MPString.mast.availableFor(minutes: remainingMinutes(until: overrideExpiry, now: now)),
        .info
      )
    }
    if mode == .available {
      return (MPString.mast.reasonAvailableUntil, .info)
    }
    if stateReason == .confirmedActiveSource {
      let source = activeSource ?? MPString.station.googleMeet
      return ("\(source) \(MPString.mast.reasonDetected)", .info)
    }
    if stateReason == .untrustedSource {
      return (MPString.mast.reasonUntrusted, .info)
    }

    let suffix = callsOkay && face == .generic
      ? " \(MPString.mast.callsOkayWhenBusy)"
      : ""
    return (MPString.mast.reasonAutomatic + suffix, .info)
  }

  private static func remainingMinutes(until date: Date, now: Date) -> Int {
    max(Int(ceil(date.timeIntervalSince(now) / 60)), 1)
  }
}
