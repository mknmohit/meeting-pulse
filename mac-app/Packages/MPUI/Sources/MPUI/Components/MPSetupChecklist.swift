import SwiftUI
import MPSupport

struct MPSetupChecklist: View {
  let store: PulseStore
  let actions: any PulseActions

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.mpIncreaseContrast) private var increaseContrast
  @FocusState private var focusedStep: SetupChecklistStep?

  var body: some View {
    VStack(alignment: .leading, spacing: MPSpace.open) {
      VStack(alignment: .leading, spacing: MPSpace.tight) {
        Text(MPString.station.setupHeadline)
          .font(MPFont.sectionTitle)
        Text(MPString.station.setupBody)
          .font(MPFont.rowLabel)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      VStack(spacing: 0) {
        checklistRow(
          number: 1,
          step: .accessibility,
          title: MPString.station.accessibility,
          detail: store.accessibilityGranted
            ? MPString.station.readsWindowTitles
            : MPString.station.setupAccessibilityDetail
        ) {
          if store.accessibilityGranted {
            Label(MPString.station.granted, systemImage: "checkmark")
              .font(MPFont.rowValue)
              .foregroundStyle(statusColor(for: .complete))
          } else {
            Button(MPString.station.setupOpenSettings) {
              _ = actions.openAccessibilitySettings()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .focused($focusedStep, equals: .accessibility)
          }
        }

        Divider()
          .padding(.leading, 44)

        checklistRow(
          number: 2,
          step: .link,
          title: MPString.station.setupLink,
          detail: MPString.station.setupLinkDetail
        ) {
          if store.viewerLinks.isEmpty {
            VStack(alignment: .trailing, spacing: MPSpace.hair) {
              HStack(spacing: MPSpace.tight) {
                Button(
                  store.isCreatingViewerLink
                    ? MPString.station.setupCreating
                    : MPString.station.setupCreateLink
                ) {
                  Task { await actions.createViewerLink() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(store.isCreatingViewerLink)
                .focused($focusedStep, equals: .link)

                Button(MPString.station.setupDoLater) {
                  actions.completeOnboarding()
                }
                .buttonStyle(.link)
                .disabled(store.isCreatingViewerLink)
              }
              if store.lastError == .createLink {
                Label(MPString.error.createLink, systemImage: "exclamationmark.triangle")
                  .font(MPFont.caption)
                  .foregroundStyle(.red)
                  .multilineTextAlignment(.trailing)
              }
            }
          } else {
            Label(MPString.station.setupReady, systemImage: "checkmark")
              .font(MPFont.rowValue)
              .foregroundStyle(statusColor(for: .complete))
          }
        }

        Divider()
          .padding(.leading, 44)

        checklistRow(
          number: 3,
          step: .watching,
          title: MPString.station.setupWatching,
          detail: MPString.station.setupWatchingDetail
        ) {
          Text(MPString.station.setupReady)
            .font(MPFont.rowValue)
            .foregroundStyle(.secondary)
        }
      }
    }
    .padding(.top, MPSpace.tight)
    .frame(maxWidth: 640, alignment: .leading)
    .onChange(of: store.accessibilityGranted) { _, granted in
      guard granted else {
        return
      }
      focusedStep = .link
    }
    .animation(reduceMotion ? nil : MPMotion.quick, value: store.accessibilityGranted)
  }

  @ViewBuilder
  private func checklistRow<Content: View>(
    number: Int,
    step: SetupChecklistStep,
    title: String,
    detail: String,
    @ViewBuilder trailing: () -> Content
  ) -> some View {
    let status = status(for: step)
    HStack(alignment: .top, spacing: MPSpace.base) {
      ZStack {
        Circle()
          .fill(statusColor(for: status))
          .frame(width: 28, height: 28)
        if status == .complete {
          Image(systemName: "checkmark")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(MPColor.ground)
        } else {
          Text(String(number))
            .font(MPFont.caption.weight(.semibold))
            .foregroundStyle(status == .active ? MPColor.ground : .secondary)
        }
      }
      .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: MPSpace.hair) {
        Text(title)
          .font(MPFont.rowLabel.weight(.semibold))
        Text(detail)
          .font(MPFont.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      Spacer(minLength: MPSpace.base)
      trailing()
    }
    .padding(.vertical, MPSpace.base)
    .contentShape(Rectangle())
  }

  private var currentStep: SetupChecklistStep {
    SetupChecklistProgress.current(
      accessibilityGranted: store.accessibilityGranted,
      hasViewerLink: !store.viewerLinks.isEmpty
    )
  }

  private func status(for step: SetupChecklistStep) -> SetupRowStatus {
    if step.rawValue < currentStep.rawValue {
      return .complete
    }
    if step == currentStep {
      return .active
    }
    return .upcoming
  }

  private func statusColor(for status: SetupRowStatus) -> Color {
    switch status {
    case .complete, .active:
      return increaseContrast ? MPColor.brassIncreaseContrast : MPColor.brass
    case .upcoming:
      return Color.secondary.opacity(0.35)
    }
  }
}

enum SetupChecklistStep: Int, Hashable {
  case accessibility = 1
  case link = 2
  case watching = 3
}

enum SetupRowStatus: Equatable {
  case complete
  case active
  case upcoming
}

enum SetupChecklistProgress {
  static func current(
    accessibilityGranted: Bool,
    hasViewerLink: Bool
  ) -> SetupChecklistStep {
    if !accessibilityGranted {
      return .accessibility
    }
    if !hasViewerLink {
      return .link
    }
    return .watching
  }
}
