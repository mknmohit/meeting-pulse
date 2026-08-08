import SwiftUI

public struct MPGroup<Content: View>: View {
  private let title: String
  private let content: Content

  public init(
    title: String,
    @ViewBuilder content: () -> Content
  ) {
    self.title = title
    self.content = content()
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: MPSpace.tight) {
      Text(title)
        .font(MPFont.groupHeader)
        .foregroundStyle(.secondary)
      VStack(alignment: .leading, spacing: 0) {
        content
      }
      .padding(.horizontal, MPSpace.base)
      .padding(.vertical, MPSpace.tight)
      .background(
        RoundedRectangle(cornerRadius: MPRadius.well, style: .continuous)
          .fill(Color(nsColor: .controlBackgroundColor))
          .overlay(
            RoundedRectangle(cornerRadius: MPRadius.well, style: .continuous)
              .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
          )
      )
    }
  }
}
