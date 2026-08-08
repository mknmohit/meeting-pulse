import SwiftUI
import MPSupport

public struct OnboardingWindow: View {
  private let store: PulseStore
  private let actions: any PulseActions
  @Environment(\.dismiss) private var dismiss
  @SwiftUI.State private var step: OnboardingStep = .intro
  @SwiftUI.State private var statusLine: String?

  public init(store: PulseStore, actions: any PulseActions) {
    self.store = store
    self.actions = actions
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: MPSpace.open) {
      Group {
        switch step {
        case .intro:
          stepView(
            headline: MPString.onboardingStep1.headline,
            body: MPString.onboardingStep1.body,
            primary: MPString.onboardingStep1.cta
          ) {
            step = .permission
          }
        case .permission:
          stepView(
            headline: MPString.onboardingStep2.headline,
            body: MPString.onboardingStep2.body,
            primary: MPString.onboardingStep2.cta,
            secondary: MPString.onboardingStep2.skip
          ) {
            _ = actions.openAccessibilitySettings()
          } secondaryAction: {
            step = .sharing
          }
        case .sharing:
          stepView(
            headline: MPString.onboardingStep3.headline,
            body: MPString.onboardingStep3.body,
            primary: MPString.onboardingStep3.cta,
            secondary: MPString.onboardingStep3.later
          ) {
            Task {
              actions.completeOnboarding()
              dismiss()
              await actions.createViewerLink()
              actions.openStation(section: .sharing)
            }
          } secondaryAction: {
            actions.completeOnboarding()
            dismiss()
            actions.openStation()
          }
        }
      }
      if let statusLine {
        Text(statusLine)
          .font(MPFont.caption)
          .foregroundStyle(.secondary)
      }
    }
    .padding(MPSpace.open)
    .frame(width: 560)
    .onChange(of: store.accessibilityGranted) { _, granted in
      guard granted else {
        return
      }
      Task { await autoAdvanceIfNeeded() }
    }
    .task(id: step) {
      await autoAdvanceIfNeeded()
    }
  }

  private func stepView(
    headline: String,
    body: String,
    primary: String,
    secondary: String? = nil,
    primaryAction: @escaping () -> Void,
    secondaryAction: (() -> Void)? = nil
  ) -> some View {
    VStack(alignment: .leading, spacing: MPSpace.base) {
      Text(headline)
        .font(MPFont.sectionTitle)
      Text(body)
        .font(MPFont.rowLabel)
        .fixedSize(horizontal: false, vertical: true)
      HStack {
        Button(primary, action: primaryAction)
          .buttonStyle(.borderedProminent)
        if let secondary, let secondaryAction {
          Button(secondary, action: secondaryAction)
            .buttonStyle(.link)
        }
      }

    }
  }

  private func autoAdvanceIfNeeded() async {
    guard OnboardingProgress.shouldAutoAdvance(
      isPermissionStep: step == .permission,
      permissionGranted: store.accessibilityGranted,
      didAutoAdvance: store.didAutoAdvance
    ) else {
      return
    }
    store.didAutoAdvance = true
    statusLine = MPString.onboardingStep2.waiting
    try? await Task.sleep(for: .milliseconds(400))
    guard !Task.isCancelled else {
      return
    }
    statusLine = MPString.onboardingStep2.granted
    try? await Task.sleep(for: .milliseconds(800))
    guard !Task.isCancelled else {
      return
    }
    step = .sharing
    statusLine = nil
  }
}

private enum OnboardingStep {
  case intro
  case permission
  case sharing
}
