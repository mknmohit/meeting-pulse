import AppKit
import SwiftUI
import MPCore
import MPSupport

public struct SharingSection: View {
  private let store: PulseStore
  private let actions: any PulseActions
  @SwiftUI.State private var showingRotateConfirmation = false
  @SwiftUI.State private var showingRevokeConfirmation = false

  public init(store: PulseStore, actions: any PulseActions) {
    self.store = store
    self.actions = actions
  }

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: MPSpace.open) {
        Text(MPString.sharing.headline)
          .font(MPFont.sectionTitle)
          .padding(.bottom, MPSpace.tight)

        if store.viewerLinks.isEmpty {
          MPEmptyState(
            headline: MPString.sharing.emptyHeadline,
            detail: MPString.sharing.emptyBody,
            actionTitle: MPString.sharing.createLink
          ) {
            Task { await actions.createViewerLink() }
          }
        } else {
          MPGroup(title: MPString.sharing.theLink) {
            ViewerLinkCard(store: store, actions: actions)
            HStack(spacing: MPSpace.tight) {
              Button(MPString.sharing.createNewLink) {
                showingRotateConfirmation = true
              }
              .buttonStyle(.link)
              Button(MPString.sharing.stopSharing) {
                showingRevokeConfirmation = true
              }
              .buttonStyle(.link)
              .foregroundStyle(.red)
            }
            .padding(.top, MPSpace.snug)
          }

          MPGroup(title: MPString.sharing.viewers) {
            viewersContent
          }
        }
      }
      .padding(.horizontal, MPSpace.open)
      .padding(.vertical, MPSpace.breath)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .task {
      guard !store.viewerLinks.isEmpty else {
        return
      }
      await actions.loadViewers()
    }
    .mpRefreshable {
      await actions.loadViewers()
    }
    .confirmationDialog(
      MPString.sharing.createNewLinkTitle,
      isPresented: $showingRotateConfirmation,
      titleVisibility: .visible
    ) {
      Button(MPString.sharing.createNewLink, role: .destructive) {
        Task { await actions.rotateViewerLink() }
      }
      Button(MPString.cancel, role: .cancel) {}
    } message: {
      Text(MPString.sharing.createNewLinkBody)
    }
    .confirmationDialog(
      MPString.sharing.stopSharingTitle,
      isPresented: $showingRevokeConfirmation,
      titleVisibility: .visible
    ) {
      Button(MPString.sharing.stopSharing, role: .destructive) {
        Task { await actions.revokeViewerAccess() }
      }
      Button(MPString.cancel, role: .cancel) {}
    } message: {
      Text(MPString.sharing.stopSharingBody)
    }
  }

  @ViewBuilder
  private var viewersContent: some View {
    switch store.viewers {
    case .idle, .loading:
      VStack(alignment: .leading, spacing: MPSpace.tight) {
        MPSkeleton()
        MPSkeleton()
        MPSkeleton()
      }
    case .loaded(let viewers):
      if viewers.isEmpty {
        Text(MPString.sharing.noViewers)
          .font(MPFont.rowLabel)
          .foregroundStyle(.secondary)
      } else {
        ForEach(viewers) { viewer in
          MPRow(label: MPString.Relative.paired(max(Int(Date.now.timeIntervalSince(viewer.pairedAt)), 0))) {
            Button(MPString.sharing.remove) {
              Task { await actions.removeViewer(id: viewer.id) }
            }
            .buttonStyle(.link)
          }
        }
      }
      Button(MPString.refresh) {
        Task { await actions.loadViewers() }
      }
      .buttonStyle(.link)
    case .failed:
      MPRow(label: MPString.sharing.viewersLoadFailed) {
        Button(MPString.sharing.tryAgain) {
          Task { await actions.loadViewers() }
        }
        .buttonStyle(.link)
      }
    }
  }
}

private struct ViewerLinkCard: View {
  let store: PulseStore
  let actions: any PulseActions

  var body: some View {
    VStack(alignment: .leading, spacing: MPSpace.snug) {
      if let pairingCode = store.pairingCode {
        Text(PairingCodeFormat.display(pairingCode))
          .font(MPFont.code)
          .textSelection(.enabled)
        HStack(spacing: MPSpace.tight) {
          MPCopyButton(
            title: MPString.sharing.copyCode,
            value: PairingCodeFormat.display(pairingCode)
          )
          if let link = store.primaryViewerLink {
            MPCopyButton(title: MPString.sharing.copyLink, value: link.absoluteString)
            ShareLink(item: link) {
              Label(MPString.sharing.share, systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.bordered)
          }
        }
      }
      ForEach(store.viewerLinks, id: \.absoluteString) { link in
        Text(link.absoluteString)
          .font(MPFont.caption)
          .foregroundStyle(.secondary)
          .textSelection(.enabled)
      }
    }
  }
}
