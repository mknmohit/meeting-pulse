import SwiftUI
import WebKit
import MPSupport

struct MPTurnstileRail: View {
  let webView: WKWebView

  var body: some View {
    VStack(alignment: .leading, spacing: MPSpace.tight) {
      HStack(alignment: .top, spacing: MPSpace.tight) {
        Image(systemName: "shield.checkered")
          .foregroundStyle(MPColor.brass)
        VStack(alignment: .leading, spacing: MPSpace.hair) {
          Text(MPString.station.securityCheckHeadline)
            .font(MPFont.rowLabel.weight(.semibold))
          Text(MPString.station.securityCheckBody)
            .font(MPFont.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        Spacer(minLength: 0)
      }

      TurnstileWebView(webView: webView)
        .id(ObjectIdentifier(webView))
        .frame(height: 92)
        .clipShape(RoundedRectangle(cornerRadius: MPRadius.cell, style: .continuous))
        .accessibilityIdentifier("meetingpulse.turnstile")
    }
    .padding(MPSpace.tight)
    .background(
      MPColor.brass.opacity(0.08),
      in: RoundedRectangle(cornerRadius: MPRadius.well, style: .continuous)
    )
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("meetingpulse.turnstile-rail")
  }
}

private struct TurnstileWebView: NSViewRepresentable {
  let webView: WKWebView

  func makeNSView(context: Context) -> WKWebView {
    webView.setValue(false, forKey: "drawsBackground")
    return webView
  }

  func updateNSView(_ nsView: WKWebView, context: Context) {}
}
