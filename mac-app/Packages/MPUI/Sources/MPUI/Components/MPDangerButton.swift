import SwiftUI

public struct MPDangerButton: View {
  private let title: String
  private let action: () -> Void

  public init(title: String, action: @escaping () -> Void) {
    self.title = title
    self.action = action
  }

  public var body: some View {
    Button(title, role: .destructive, action: action)
      .buttonStyle(.plain)
      .foregroundStyle(.white)
      .padding(.horizontal, MPSpace.snug)
      .padding(.vertical, MPSpace.tight)
      .background(.red, in: RoundedRectangle(cornerRadius: MPRadius.cell))
  }
}
