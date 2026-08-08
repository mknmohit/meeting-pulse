import SwiftUI

public struct MPEmptyState: View {
  private let headline: String
  private let detail: String
  private let actionTitle: String?
  private let action: (() -> Void)?

  public init(
    headline: String,
    detail: String,
    actionTitle: String? = nil,
    action: (() -> Void)? = nil
  ) {
    self.headline = headline
    self.detail = detail
    self.actionTitle = actionTitle
    self.action = action
  }

  public var body: some View {
    VStack(spacing: MPSpace.tight) {
      DayShapeView(shape: .mast, tint: MPColor.chalk)
        .frame(width: 64, height: 96)
        .opacity(0.4)
        .accessibilityHidden(true)
      Text(headline)
        .font(MPFont.sectionTitle)
        .multilineTextAlignment(.center)
      Text(detail)
        .font(MPFont.rowLabel)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: 460)
      if let actionTitle, let action {
        Button(actionTitle, action: action)
          .buttonStyle(.borderedProminent)
          .controlSize(.large)
          .padding(.top, MPSpace.tight)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(MPSpace.open)
  }
}
