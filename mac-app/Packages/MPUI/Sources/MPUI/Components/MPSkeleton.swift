import SwiftUI

public struct MPSkeleton: View {
  public init() {}

  public var body: some View {
    RoundedRectangle(cornerRadius: MPRadius.cell)
      .fill(Color.secondary.opacity(0.12))
      .frame(height: 32)
      .redacted(reason: .placeholder)
  }
}
