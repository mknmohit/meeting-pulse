import SwiftUI

public struct MPRow<Trailing: View>: View {
  private let label: String
  private let detail: String?
  private let trailing: Trailing

  public init(
    label: String,
    detail: String? = nil,
    @ViewBuilder trailing: () -> Trailing
  ) {
    self.label = label
    self.detail = detail
    self.trailing = trailing()
  }

  public var body: some View {
    HStack(alignment: .top, spacing: MPSpace.base) {
      VStack(alignment: .leading, spacing: MPSpace.tight) {
        Text(label)
          .font(MPFont.rowLabel)
        if let detail {
          Text(detail)
            .font(MPFont.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      Spacer(minLength: MPSpace.base)
      trailing
    }
    .padding(.vertical, MPSpace.snug)
    .contentShape(Rectangle())
  }
}

public extension MPRow where Trailing == EmptyView {
  init(label: String, detail: String? = nil) {
    self.init(label: label, detail: detail) {
      EmptyView()
    }
  }
}
