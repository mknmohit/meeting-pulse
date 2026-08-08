import Foundation
import MPCore
import MPSupport

public enum ReasonLinePresentation: Equatable, Sendable {
  case station
  case menuBar
}

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
    presentation: ReasonLinePresentation = .station,
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
    if mode == .busy {
      return (
        overrideLine(
          mode: mode,
          overrideExpiry: overrideExpiry,
          presentation: presentation,
          now: now
        ),
        .info
      )
    }
    if mode == .available {
      return (
        overrideLine(
          mode: mode,
          overrideExpiry: overrideExpiry,
          presentation: presentation,
          now: now
        ),
        .info
      )
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

  public static func overrideLine(
    mode: PulseMode,
    overrideExpiry: Date?,
    presentation: ReasonLinePresentation,
    now: Date = .now
  ) -> String {
    guard let overrideExpiry else {
      switch mode {
      case .busy:
        return MPString.mast.reasonBusyUntil
      case .available:
        return MPString.mast.reasonAvailableUntil
      case .automatic:
        return MPString.mast.reasonAutomatic
      }
    }

    let remaining = remainingDuration(until: overrideExpiry, now: now)
    switch (mode, presentation) {
    case (.busy, .station):
      return MPString.mast.busyUntil(
        time: formattedEndTime(overrideExpiry),
        remaining: remaining.long
      )
    case (.available, .station):
      return MPString.mast.availableUntil(
        time: formattedEndTime(overrideExpiry),
        remaining: remaining.long
      )
    case (.busy, .menuBar):
      return MPString.mast.busyRemaining(remaining.compact)
    case (.available, .menuBar):
      return MPString.mast.availableRemaining(remaining.compact)
    case (.automatic, _):
      return MPString.mast.reasonAutomatic
    }
  }

  private static func formattedEndTime(_ date: Date) -> String {
    date.formatted(date: .omitted, time: .shortened)
  }

  private static func remainingDuration(until date: Date, now: Date) -> RemainingDuration {
    let seconds = date.timeIntervalSince(now)
    guard seconds >= 60 else {
      return RemainingDuration(compact: "<1m", long: "less than a minute")
    }

    let totalMinutes = Int(ceil(seconds / 60))
    let hours = totalMinutes / 60
    let minutes = totalMinutes % 60

    let long: String
    if hours == 0 {
      long = "\(minutes) \(minutes == 1 ? "minute" : "minutes")"
    } else if minutes == 0 {
      long = "\(hours) \(hours == 1 ? "hour" : "hours")"
    } else {
      long = "\(hours) \(hours == 1 ? "hour" : "hours") " +
        "\(minutes) \(minutes == 1 ? "minute" : "minutes")"
    }

    let compact = minutes == 0
      ? "\(hours)h"
      : hours == 0
        ? "\(minutes)m"
        : "\(hours)h \(minutes)m"

    return RemainingDuration(compact: compact, long: long)
  }

  private struct RemainingDuration {
    let compact: String
    let long: String
  }
}
