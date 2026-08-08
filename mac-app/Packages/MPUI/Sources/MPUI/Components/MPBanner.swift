import SwiftUI

public enum MPBannerTone: Sendable {
  case info
  case caution
  case alert
}

public struct MPBanner: View {
  private let tone: MPBannerTone
  private let headline: String
  private let detail: String?
  private let actionTitle: String?
  private let action: (() -> Void)?

  public init(
    tone: MPBannerTone,
    headline: String,
    detail: String? = nil,
    actionTitle: String? = nil,
    action: (() -> Void)? = nil
  ) {
    self.tone = tone
    self.headline = headline
    self.detail = detail
    self.actionTitle = actionTitle
    self.action = action
  }

  public var body: some View {
    HStack(alignment: .top, spacing: MPSpace.tight) {
      Image(systemName: symbolName)
        .foregroundStyle(tint)
      VStack(alignment: .leading, spacing: MPSpace.hair) {
        Text(headline)
          .font(MPFont.rowLabel.weight(.semibold))
        if let detail {
          Text(detail)
            .font(MPFont.caption)
            .fixedSize(horizontal: false, vertical: true)
        }
        if let actionTitle, let action {
          Button(actionTitle, action: action)
            .buttonStyle(.link)
            .padding(.top, MPSpace.hair)
        }
      }
      Spacer(minLength: 0)
    }
    .padding(MPSpace.base)
    .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: MPRadius.well))
  }

  private var tint: Color {
    switch tone {
    case .info:
      return .accentColor
    case .caution:
      return MPColor.brass
    case .alert:
      return .red
    }
  }

  private var symbolName: String {
    switch tone {
    case .info:
      return "info.circle"
    case .caution:
      return "exclamationmark.triangle"
    case .alert:
      return "exclamationmark.octagon"
    }
  }
}
