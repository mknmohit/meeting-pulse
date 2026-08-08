import SwiftUI
import MPSupport

public struct PublishRail: View {
  private let store: PulseStore
  @Environment(\.mpIncreaseContrast) private var increaseContrast

  public init(store: PulseStore) {
    self.store = store
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: MPSpace.hair) {
      HStack(spacing: MPSpace.hair) {
        Image(systemName: railSymbol)
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(railColor)
          .accessibilityHidden(true)
        Text(railLabel)
          .font(MPFont.chalkLine)
          .foregroundStyle(store.syncState == .idle ? MPColor.chalk : MPColor.brass)
          .lineLimit(1)
      }
    }
    .padding(.horizontal, MPSpace.base)
    .padding(.vertical, MPSpace.snug)
    .frame(maxWidth: .infinity, alignment: .leading)
    .overlay(alignment: .top) {
      Rectangle()
        .fill(MPColor.chalk.opacity(0.14))
        .frame(height: 1)
    }
  }

  private var railColor: Color {
    store.syncState == .idle
      ? MPColor.chalk
      : (increaseContrast ? MPColor.brassIncreaseContrast : MPColor.brass)
  }

  private var railSymbol: String {
    if !store.isOnline {
      return "wifi.slash"
    }
    switch store.publishState {
    case .never:
      return "circle.dashed"
    case .publishing:
      return "arrow.up.circle"
    case .retrying:
      return "arrow.clockwise.circle"
    case .offline:
      return "wifi.slash"
    case .superseded:
      return "exclamationmark.triangle"
    case .published:
      return "checkmark.circle.fill"
    }
  }

  private var railLabel: String {
    if !store.isOnline {
      return MPString.mast.noNetwork
    }
    switch store.publishState {
    case .never:
      return MPString.mast.nothingPublished
    case .publishing:
      return MPString.mast.publishing
    case .retrying:
      return MPString.mast.reasonUnreachable
    case .offline:
      return MPString.mast.noNetwork
    case .superseded:
      return MPString.mast.anotherMacPublishing
    case .published(let date):
      let seconds = max(Int(Date.now.timeIntervalSince(date)), 0)
      return MPString.Relative.published(seconds)
    }
  }
}
