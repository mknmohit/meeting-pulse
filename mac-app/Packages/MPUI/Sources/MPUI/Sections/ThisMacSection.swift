import SwiftUI
import MPSupport

public struct ThisMacSection: View {
  private let store: PulseStore
  private let actions: any PulseActions
  @State private var draftName = ""
  @State private var showingDeleteConfirmation = false
  @State private var deleteText = ""
  @State private var showingRecovery = false

  public init(store: PulseStore, actions: any PulseActions) {
    self.store = store
    self.actions = actions
  }

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: MPSpace.open) {
        Text(MPString.thisMac.headline)
          .font(MPFont.sectionTitle)
          .padding(.bottom, MPSpace.tight)

        if !store.installLocationIsValid {
          MPBanner(
            tone: .caution,
            headline: MPString.thisMac.installHeadline,
            detail: MPString.thisMac.installBody,
            actionTitle: MPString.thisMac.showInFinder
          ) {
            actions.revealInFinder()
          }
        }

        MPGroup(title: MPString.thisMac.yourName) {
          TextField(MPString.thisMac.name, text: $draftName)
            .textFieldStyle(.roundedBorder)
            .onSubmit {
              Task { await saveName() }
            }
          Text(MPString.thisMac.nameDetail)
            .font(MPFont.caption)
            .foregroundStyle(.secondary)
          if store.lastError == nil {
            EmptyView()
          }
        }
        .task(id: draftName) {
          guard draftName != store.displayName else {
            return
          }
          try? await Task.sleep(for: .milliseconds(600))
          guard !Task.isCancelled else {
            return
          }
          await saveName()
        }

        MPGroup(title: MPString.thisMac.startup) {
          Toggle(MPString.thisMac.openAtLogin, isOn: loginBinding)
          Toggle(MPString.thisMac.openWindowAtLogin, isOn: windowBinding)
            .disabled(!store.launchAtLogin)
        }

        MPGroup(title: MPString.thisMac.ifYouLoseThisMac) {
          RecoveryPhraseView(
            store: store,
            actions: actions,
            isPresented: $showingRecovery
          )
        }

        MPGroup(title: MPString.thisMac.dangerZone) {
          Text(MPString.thisMac.deleteDetail)
            .font(MPFont.caption)
            .foregroundStyle(.secondary)
          MPDangerButton(title: MPString.thisMac.delete) {
            deleteText = ""
            showingDeleteConfirmation = true
          }
        }
      }
      .padding(.horizontal, MPSpace.open)
      .padding(.vertical, MPSpace.breath)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .onAppear {
      draftName = store.displayName
    }
    .sheet(isPresented: $showingDeleteConfirmation) {
      deleteSheet
    }
  }

  private var loginBinding: Binding<Bool> {
    Binding(
      get: { store.launchAtLogin },
      set: { newValue in
        do {
          try actions.setLaunchAtLogin(newValue)
          store.launchAtLogin = newValue
        } catch {
          store.lastError = .loginItemBlocked
        }
      }
    )
  }

  private var windowBinding: Binding<Bool> {
    Binding(
      get: { store.openWindowAtLogin },
      set: { newValue in
        store.openWindowAtLogin = newValue
        actions.setOpenWindowAtLogin(newValue)
      }
    )
  }

  private func saveName() async {
    let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
    let bounded = String(trimmed.prefix(80))
    guard bounded != store.displayName else {
      return
    }
    store.displayName = bounded
    await actions.setDisplayName(bounded)
  }

  @ViewBuilder
  private var deleteSheet: some View {
    VStack(alignment: .leading, spacing: MPSpace.base) {
      Text(MPString.thisMac.deleteTitle)
        .font(MPFont.sectionTitle)
      Text(MPString.thisMac.deleteBody)
        .font(MPFont.rowLabel)
      Text(MPString.thisMac.typeDelete)
        .font(MPFont.caption)
        .foregroundStyle(.secondary)
      TextField("", text: $deleteText)
        .textFieldStyle(.roundedBorder)
      HStack {
        Spacer()
        Button(MPString.cancel) {
          showingDeleteConfirmation = false
        }
        Button(MPString.thisMac.deleteEverything, role: .destructive) {
          showingDeleteConfirmation = false
          Task { await actions.deleteEverything() }
        }
        .disabled(deleteText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != "delete")
      }
    }
    .padding(MPSpace.open)
    .frame(width: 480)
  }
}

struct RecoveryPhraseView: View {
  let store: PulseStore
  let actions: any PulseActions
  @Binding var isPresented: Bool
  @State private var resetID = 0

  var body: some View {
    VStack(alignment: .leading, spacing: MPSpace.snug) {
      if isPresented, let phrase = store.recoveryPhrase {
        Text(phrase)
          .font(MPFont.phrase)
          .textSelection(.enabled)
        MPCopyButton(title: MPString.thisMac.copyPhrase, value: phrase)
        Text(MPString.thisMac.recoveryWarning)
          .font(MPFont.caption)
          .foregroundStyle(.secondary)
      } else {
        Text(MPString.recoveryHidden)
          .font(MPFont.caption)
          .foregroundStyle(.secondary)
        Text(MPString.thisMac.recoveryDetail)
          .font(MPFont.caption)
          .foregroundStyle(.secondary)
      }
      Button(isPresented ? MPString.thisMac.hide : MPString.revealAgain) {
        isPresented.toggle()
        resetID += 1
        if isPresented {
          Task { await actions.revealRecoveryPhrase() }
        }
      }
      .buttonStyle(.link)
    }
    .focusable()
    .onKeyPress { _ in
      resetID += 1
      return .handled
    }
    .contentShape(Rectangle())
    .onTapGesture {
      resetID += 1
    }
    .task(id: resetID) {
      guard isPresented else {
        return
      }
      try? await Task.sleep(for: RecoveryTimerPolicy.autoHideAfter)
      guard !Task.isCancelled else {
        return
      }
      isPresented = false
    }
  }
}
