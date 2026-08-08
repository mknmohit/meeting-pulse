import SwiftUI
import MPSupport

public struct PrivacySection: View {
  public init() {}

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: MPSpace.open) {
        Text(MPString.privacy.headline)
          .font(MPFont.sectionTitle)
          .padding(.bottom, MPSpace.tight)
        HStack(alignment: .top, spacing: MPSpace.base) {
          privacyGroup(
            title: MPString.privacy.leavesThisMac,
            items: [
              MPString.privacy.inMeetingOrNot,
              MPString.privacy.whetherCallsAreOkay,
              MPString.privacy.whetherSetByHand,
              MPString.privacy.whenItRunsOut,
              MPString.privacy.nameChosen
            ]
          )
          privacyGroup(
            title: MPString.privacy.viewerSees,
            items: [
              MPString.privacy.inMeetingOrNot,
              MPString.privacy.whetherCallsAreOkay,
              MPString.privacy.nameChosen,
              MPString.privacy.whenItRunsOut
            ]
          )
          privacyGroup(
            title: MPString.privacy.staysThisMac,
            items: [
              MPString.privacy.windowTitles,
              MPString.privacy.meetingNames,
              MPString.privacy.whoMeeting,
              MPString.privacy.calendarEvents,
              MPString.privacy.screenContents,
              MPString.privacy.audio,
              MPString.privacy.anythingYouType
            ]
          )
        }
        Text(MPString.privacy.explanation)
          .font(MPFont.rowLabel)
        Text(MPString.privacy.boundary)
          .font(MPFont.rowLabel)
      }
      .padding(.horizontal, MPSpace.open)
      .padding(.vertical, MPSpace.breath)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private func privacyGroup(title: String, items: [String]) -> some View {
    MPGroup(title: title) {
      VStack(alignment: .leading, spacing: MPSpace.tight) {
        ForEach(items, id: \.self) { item in
          Text(item)
            .font(MPFont.rowLabel)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
