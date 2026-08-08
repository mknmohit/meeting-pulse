import AppKit
import SwiftUI
import MPSupport

public struct MPCopyButton: View {
  private let title: String
  private let value: String
  @State private var copied = false

  public init(title: String, value: String) {
    self.title = title
    self.value = value
  }

  public var body: some View {
    Button {
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(value, forType: .string)
      copied = true
      Task {
        try? await Task.sleep(for: .seconds(1.6))
        guard !Task.isCancelled else {
          return
        }
        copied = false
      }
    } label: {
      Label(
        copied ? MPString.sharing.copied : title,
        systemImage: copied ? "checkmark" : "doc.on.doc"
      )
    }
    .buttonStyle(.bordered)
    .animation(MPMotion.quick, value: copied)
  }
}
