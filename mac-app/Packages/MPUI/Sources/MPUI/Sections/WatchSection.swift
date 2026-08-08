import SwiftUI
import MPCore
import MPSupport

public struct WatchSection: View {
  private let store: PulseStore
  private let actions: any PulseActions

  public init(store: PulseStore, actions: any PulseActions) {
    self.store = store
    self.actions = actions
  }

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: MPSpace.loose) {
        Text(MPString.station.watch)
          .font(MPFont.sectionTitle)

        if let setupFailure = store.setupFailure {
          MPBanner(tone: .alert, headline: MPString.error.genericSetup, detail: setupFailure)
        }

        MPGroup(title: MPString.station.permission) {
          MPRow(
            label: MPString.station.accessibility,
            detail: MPString.station.readsWindowTitles
          ) {
            Text(store.accessibilityGranted ? MPString.station.granted : MPString.station.notGranted)
              .font(MPFont.rowValue)
          }
          if !store.accessibilityGranted {
            MPBanner(
              tone: .caution,
              headline: MPString.station.permissionHeadline,
              detail: MPString.station.permissionBody,
              actionTitle: MPString.station.openAccessibilitySettings
            ) {
              _ = actions.openAccessibilitySettings()
            }
          }
        }

        MPGroup(title: MPString.station.whatMacWatches) {
          sourceRow(
            title: MPString.station.googleMeet,
            symbol: "video",
            observation: store.meet,
            seenAt: store.meetSeenAt
          )
          sourceRow(
            title: MPString.station.slackHuddles,
            symbol: "waveform",
            observation: store.slack,
            seenAt: store.slackSeenAt
          )
        }

        MPGroup(title: MPString.station.publishing) {
          MPRow(label: MPString.station.lastPublished, detail: MPRelativeTime.text(since: store.lastPublished))
          MPRow(label: MPString.station.checksRun, detail: MPString.station.syncCadence)
          MPRow(label: MPString.station.thisMacPublishing) {
            Text(publishingValue)
              .font(MPFont.rowValue)
          }
        }

        if store.syncState == .superseded {
          MPBanner(
            tone: .alert,
            headline: MPString.station.supersededHeadline,
            detail: MPString.station.supersededBody
          )
        }
      }
      .padding(.horizontal, MPSpace.open)
      .padding(.vertical, MPSpace.loose)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private func sourceRow(
    title: String,
    symbol: String,
    observation: SourceObservation?,
    seenAt: Date?
  ) -> some View {
    MPRow(
      label: title,
      detail: detail(for: seenAt, observation: observation)
    ) {
      HStack(spacing: MPSpace.tight) {
        Image(systemName: symbol)
          .foregroundStyle(.secondary)
        MPStateChip(observation: observation)
      }
    }
  }

  private func detail(for seenAt: Date?, observation: SourceObservation?) -> String {
    guard observation != nil else {
      return MPString.station.willNoticeNextJoin
    }
    return MPString.Relative.checked(max(Int(Date.now.timeIntervalSince(seenAt ?? .now)), 0))
  }

  private var publishingValue: String {
    switch store.syncState {
    case .idle:
      return MPString.station.publishingState
    case .retrying:
      return MPString.station.retrying
    case .superseded:
      return MPString.station.stopped
    }
  }
}
