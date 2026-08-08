import MPCore

public enum MPString {
  public enum Board {
    public static let busyHeadline = "In a meeting"
    public static let busySubhead = "Better to wait."
    public static let callOkayHeadline = "In Meeting, but it's fine to ring through"
    public static let callOkaySubhead = "He said to go ahead and interrupt."
    public static let genericHeadline = "Meeting status unavailable"
    public static let genericSubhead = "Check again before you call."
    public static let offlineSubhead = "Connect to the internet, then check again."
    public static let unpairedHeadline = "Not connected"
    public static let unpairedSubhead = "Open the viewer link or enter the code he shared."

    public static func busyHeadline(named name: String?) -> String {
      guard let name, !name.isEmpty else { return busyHeadline }
      return "\(name) is in a meeting"
    }

    public static func callOkayHeadline(named name: String?) -> String {
      guard let name, !name.isEmpty else { return callOkayHeadline }
      return "\(name) is in Meeting, but it's fine to ring through"
    }
  }

  public enum Mast {
    public static let busyHeadline = Board.busyHeadline
    public static let busySubhead = Board.busySubhead
    public static let callOkayHeadline = Board.callOkayHeadline
    public static let callOkaySubhead = Board.callOkaySubhead
    public static let genericHeadline = Board.genericHeadline
    public static let genericSubhead = Board.genericSubhead
    public static let offlineHeadline = Board.genericHeadline
    public static let offlineSubhead = Board.offlineSubhead
    public static let unpairedHeadline = Board.unpairedHeadline
    public static let unpairedSubhead = Board.unpairedSubhead
    public static let modeBusy = "Busy"
    public static let modeAutomatic = "Automatic"
    public static let modeAvailable = "Available"
    public static let modeFree = "Free"
    public static let duration = "Until"
    public static let callsAreOkay = "Calls are okay"
    public static let reasonAccessibilityMissing = "Waiting for Accessibility permission"
    public static let reasonSuperseded = "Another Mac took over. This one has stopped."
    public static let reasonUnreachable = "Can't reach the server. Retrying."
    public static let reasonNoViewer = "No one is watching yet. Create a link."
    public static let reasonBusyUntil = "Busy until you clear it"
    public static let reasonAvailableUntil = "Available until you clear it"
    public static let reasonDetected = "call detected"
    public static let reasonUntrusted = "A window looked like a call. Not sure enough."
    public static let reasonAutomatic = "Watching automatically"
    public static let callsOkayWhenBusy = "Calls are okay when you are busy."
    public static let nothingPublished = "Nothing published yet"
    public static let publishing = "Publishing..."
    public static let noNetwork = "No network. Waiting."
    public static let anotherMacPublishing = "Another Mac is publishing now"
    public static let lastPublishedJustNow = "Last published just now"
    public static let resetComplete = "Everything on this Mac is gone. Quit to finish."

    public static func durationLabel(_ duration: ManualOverride.Duration) -> String {
      switch duration {
      case .m15: return "15 minutes"
      case .m30: return "30 minutes"
      case .m45: return "45 minutes"
      case .h1: return "1 hour"
      case .h2: return "2 hours"
      case .h4: return "4 hours"
      case .untilCleared: return "Until I clear it"
      }
    }

    public static func busyFor(minutes: Int) -> String {
      "\(busyForPrefix) \(minutes) \(minutes == 1 ? "minute" : "minutes")"
    }

    public static func availableFor(minutes: Int) -> String {
      "\(availableForPrefix) \(minutes) \(minutes == 1 ? "minute" : "minutes")"
    }

    public static func busyRemaining(_ remaining: String) -> String {
      "Busy - \(remaining)"
    }

    public static func availableRemaining(_ remaining: String) -> String {
      "Available - \(remaining)"
    }

    public static func busyUntil(time: String, remaining: String) -> String {
      "Busy until \(time) - \(remaining) remaining"
    }

    public static func availableUntil(time: String, remaining: String) -> String {
      "Available until \(time) - \(remaining) remaining"
    }

    private static let busyForPrefix = "Busy for another"
    private static let availableForPrefix = "Available for another"
  }

  public enum Station {
    public static let windowTitle = "Meeting Pulse"
    public static let watch = "Watch"
    public static let sharing = "Sharing"
    public static let thisMac = "This Mac"
    public static let privacy = "Privacy"
    public static let checkNow = "Check and publish now"
    public static let checkNowHelp = "Publish the current status now."
    public static let permission = "Permission"
    public static let whatMacWatches = "What the Mac watches"
    public static let publishing = "Publishing"
    public static let accessibility = "Accessibility"
    public static let granted = "Granted"
    public static let notGranted = "Not granted"
    public static let readsWindowTitles = "Meeting Pulse reads window titles. It never reads what is inside them."
    public static let setupHeadline = "Let's get your signal online."
    public static let setupBody = "Meeting Pulse reads window titles only. Nothing inside your calls leaves this Mac."
    public static let setupAccessibilityDetail = "Allow Meeting Pulse to read Meet and Slack window titles."
    public static let setupLink = "Private viewer link"
    public static let setupLinkDetail = "Send one word to whoever needs to know when to call."
    public static let setupWatching = "Keep watching"
    public static let setupWatchingDetail = "The menu bar will keep the signal up to date."
    public static let setupOpenSettings = "Open System Settings"
    public static let setupCreateLink = "Create private link"
    public static let setupCreating = "Creating..."
    public static let setupDoLater = "Do this later"
    public static let setupReady = "Ready"
    public static let setupLinkHeadline = "Your signal is live."
    public static let setupLinkBody = "Create a private viewer link from Sharing when you're ready."
    public static let setupOpenSharing = "Open Sharing"
    public static let securityCheckHeadline = "Quick security check"
    public static let securityCheckBody = "Complete this once to connect your private link."
    public static let permissionHeadline = "Meeting Pulse can't see your windows yet."
    public static let permissionBody = "Turn on Accessibility so the Mac can read window titles. It never reads what is inside them."
    public static let openAccessibilitySettings = "Open Accessibility settings"
    public static let accessibilityFallback = "Open System Settings, then Privacy & Security, then Accessibility."
    public static let googleMeet = "Google Meet"
    public static let slackHuddles = "Slack huddles"
    public static let inCall = "In a call"
    public static let noCall = "No call"
    public static let cannotTell = "Can't tell"
    public static let notSeenYet = "Not seen yet"
    public static let willNoticeNextJoin = "Meeting Pulse will notice the next time you join."
    public static let lastPublished = "Last published"
    public static let checksRun = "Checks run"
    public static let thisMacPublishing = "This Mac"
    public static let publishingState = "Publishing"
    public static let retrying = "Retrying"
    public static let stopped = "Stopped"
    public static let syncCadence = "Every \(activeCheckSeconds) seconds in a call, \(idleCheckSeconds) seconds idle"
    public static let activeCheckSeconds = 5
    public static let idleCheckSeconds = 20
    public static let supersededHeadline = "Another Mac took over."
    public static let supersededBody = "Meeting Pulse is running somewhere else. This Mac has stopped publishing."
  }

  public enum Sharing {
    public static let headline = "Sharing"
    public static let body = "Create a link and send it to whoever needs to know when to call."
    public static let emptyHeadline = "No one is watching yet."
    public static let emptyBody = "Create a link and send it to whoever needs to know when to call."
    public static let createLink = "Create the viewer link"
    public static let theLink = "The link"
    public static let whoHasTheLink = "Who has the link"
    public static let copyLink = "Copy link"
    public static let copyCode = "Copy code"
    public static let share = "Share"
    public static let copied = "Copied"
    public static let createNewLink = "Create a new link"
    public static let stopSharing = "Stop sharing"
    public static let createNewLinkTitle = "Create a new link?"
    public static let createNewLinkBody = "The old link stops working right away. Anyone using it will need the new one."
    public static let stopSharingTitle = "Stop sharing?"
    public static let stopSharingBody = "The link stops working right away. No one will be able to see your status."
    public static let viewers = "Who has the link"
    public static let noViewers = "Nobody has used the link yet."
    public static let viewersLoadFailed = "Can't load the list right now."
    public static let tryAgain = "Try again"
    public static let remove = "Remove"
    public static let doThisLater = "Do this later"
    public static let unnamedOwner = "Meeting Pulse"

    public static func copyHostLink(_ host: String) -> String {
      "Copy \(host) link"
    }
  }

  public enum ThisMac {
    public static let headline = "This Mac"
    public static let yourName = "Your name"
    public static let name = "Name"
    public static let optionalName = "Optional name"
    public static let nameDetail = "Shown on the page as \"{Name} is in a meeting\". Leave it blank to stay unnamed."
    public static let saved = "Saved"
    public static let saveName = "Save name"
    public static let viewerNameDetail = "The name appears above the meeting status on the viewer."
    public static let startup = "Startup"
    public static let openAtLogin = "Open at login"
    public static let openWindowAtLogin = "Open the window at login"
    public static let ifYouLoseThisMac = "If you lose this Mac"
    public static let recoveryPhrase = "Recovery phrase"
    public static let recoveryDetail = "A code that lets you take over from a new Mac. Write it down somewhere safe."
    public static let show = "Show"
    public static let hide = "Hide"
    public static let showRecoveryPhrase = "Show recovery phrase..."
    public static let copyPhrase = "Copy the phrase"
    public static let recoveryWarning = "Anyone with this code can take over your status. Keep it somewhere only you can reach."
    public static let recoveryUnavailable = "The recovery phrase is not available."
    public static let installHeadline = "Meeting Pulse is not in your Applications folder."
    public static let installBody = "Move it to Applications so it keeps running after updates."
    public static let showInFinder = "Show me in Finder"
    public static let dangerZone = "Danger zone"
    public static let deleteEverything = "Delete everything"
    public static let deleteDetail = "Removes your status, the viewer link, and the recovery phrase. This cannot be undone."
    public static let delete = "Delete..."
    public static let deleteTitle = "Delete everything?"
    public static let deleteBody = "This removes your status, the viewer link, and the recovery phrase from this Mac and from the server. The page anyone has open will stop working."
    public static let typeDelete = "Type delete to confirm."
    public static let everythingGone = "Everything is gone."
    public static let nothingLeft = "Meeting Pulse has nothing left to publish. Quit and delete the app, or set it up again."
    public static let setUpAgain = "Quit and set up again"
  }

  public enum Privacy {
    public static let headline = "Privacy"
    public static let leavesThisMac = "What leaves this Mac"
    public static let viewerSees = "What she can see"
    public static let staysThisMac = "What never leaves this Mac"
    public static let inMeetingOrNot = "In a meeting, or not"
    public static let whetherCallsAreOkay = "Whether calls are okay"
    public static let whetherSetByHand = "Whether you set it by hand"
    public static let whenItRunsOut = "When that runs out"
    public static let nameChosen = "The name you chose"
    public static let windowTitles = "Window titles"
    public static let meetingNames = "Meeting names"
    public static let whoMeeting = "Who you are meeting"
    public static let calendarEvents = "Calendar events"
    public static let screenContents = "Screen contents"
    public static let audio = "Audio"
    public static let anythingYouType = "Anything you type"
    public static let explanation = "Meeting Pulse reads the titles of windows that are already open to work out whether you are in a call. The titles stay on this Mac."
    public static let boundary = "The server knows whether you set your status by hand and when that runs out. She cannot. The page she loads is not allowed to ask for those."
  }

  public enum Setup {
    public static let step1Headline = "Meeting Pulse tells one person when to call you."
    public static let step1Body = "It notices when you are in a Google Meet or a Slack huddle and puts \"In a meeting\" on a private page. Nothing else leaves this Mac."
    public static let step1CTA = "Get started"
    public static let step2Headline = "Let the Mac see your window titles."
    public static let step2Body = "Meeting Pulse reads the titles of open windows to work out whether you are in a call. It never reads what is inside them, and titles stay on this Mac."
    public static let step2CTA = "Open Accessibility settings"
    public static let step2Skip = "Skip for now"
    public static let step2Waiting = "Waiting..."
    public static let step2Granted = "Accessibility is on."
    public static let step3Headline = "Send this to whoever needs it."
    public static let step3Body = "They open the link and see one word. They do not need an account, and they cannot see anything else."
    public static let step3CTA = "Create the link"
    public static let step3Later = "Do this later"
    public static let step3OpenApp = "Open Meeting Pulse"
  }

  public enum OnboardingStep1 {
    public static let headline = Setup.step1Headline
    public static let body = Setup.step1Body
    public static let cta = Setup.step1CTA
  }

  public enum OnboardingStep2 {
    public static let headline = Setup.step2Headline
    public static let body = Setup.step2Body
    public static let cta = Setup.step2CTA
    public static let skip = Setup.step2Skip
    public static let waiting = Setup.step2Waiting
    public static let granted = Setup.step2Granted
  }

  public enum OnboardingStep3 {
    public static let headline = Setup.step3Headline
    public static let body = Setup.step3Body
    public static let cta = Setup.step3CTA
    public static let later = Setup.step3Later
    public static let openApp = Setup.step3OpenApp
  }

  public enum MenuBar {
    public static let setBusy = "Set busy"
    public static let setAvailable = "Set available"
    public static let backToAutomatic = "Back to automatic"
    public static let callsAreOkay = "Calls are okay"
    public static let openStation = "Open Dashboard"
    public static let quit = "Quit Meeting Pulse"
    public static let availableOverride = "Currently available. Set busy to override."
  }

  public enum ErrorCopy {
    public static let starting = "Starting up."
    public static let unreachable = "Can't reach the server. Retrying."
    public static let noNetwork = "No network. Waiting."
    public static let localStorage = "Meeting Pulse couldn't access its local data. Try again."
    public static let permission = "Meeting Pulse can't see your windows yet."
    public static let invalidPhrase = "That phrase doesn't match. Check for typos."
    public static let loginItem = "macOS blocked this. Open Login Items in System Settings to allow it."
    public static let createLink = "Couldn't create the link. Try again."
    public static let viewers = "Can't load the list right now."
    public static let genericSetup = "Meeting Pulse isn't configured yet."
    public static let launchFailed = "Meeting Pulse couldn't start."
    public static let tryAgain = "Try again"
  }

  public enum SetupError {
    public static let installHeadline = "Move Meeting Pulse to your Applications folder first."
    public static let installBody = "Running it from here breaks the login item and the permission you're about to grant."
    public static let installCTA = "Move and reopen"
    public static let genericHeadline = "Meeting Pulse isn't configured yet."
    public static let genericBody = "Copy Config.xcconfig.example and fill it in, then reopen the app."
  }

  public enum Diagnostics {
    public static let headline = "Diagnostics"
    public static let state = "State"
    public static let connection = "Connection"
    public static let privacy = "Meeting Pulse never records meeting titles, links, participants, audio, video, or screen contents."
  }

  public enum Relative {
    public static let justNow = "just now"
    public static let secondsAgo = "seconds ago"
    public static let minuteAgo = "minute ago"
    public static let minutesAgo = "minutes ago"
    public static let hourAgo = "hour ago"
    public static let hoursAgo = "hours ago"
    public static let checkedAgo = "Checked"
    public static let pairedAgo = "Paired"

    public static func elapsed(_ seconds: Int) -> String {
      if seconds < 10 {
        return justNow
      }
      if seconds < 60 {
        return "\(seconds) \(seconds == 1 ? "second" : secondsAgo)"
      }
      let minutes = seconds / 60
      if minutes < 60 {
        return "\(minutes) \(minutes == 1 ? minuteAgo : minutesAgo)"
      }
      let hours = minutes / 60
      return "\(hours) \(hours == 1 ? hourAgo : hoursAgo)"
    }

    public static func published(_ seconds: Int) -> String {
      "Published \(elapsed(seconds))"
    }

    public static func checked(_ seconds: Int) -> String {
      "\(checkedAgo) \(elapsed(seconds))"
    }

    public static func paired(_ seconds: Int) -> String {
      "\(pairedAgo) \(elapsed(seconds))"
    }
  }

  public static let cancel = "Cancel"
  public static let refresh = "Refresh"
  public static let waiting = "Waiting..."
  public static let revealAgain = "Reveal again"
  public static let recoveryHidden = "The recovery code is hidden."
  public static let recoveryRevealed = "Reveal again"
  public static let pairing = "Pairing"
  public static let settings = "Meeting Pulse Settings"
  public static let recovery = "Recovery"
  public static let code = "Code"
  public static let copy = "Copy"
  public static let openApp = "Open Meeting Pulse"
  public static let quit = "Quit Meeting Pulse"
  public static let stillWaiting = "Still waiting on permission. Meeting Pulse can't tell whether you're on a call until you grant it, so the page will show \"Meeting status unavailable\"."
  public static let setBusy = MenuBar.setBusy
  public static let setAvailable = MenuBar.setAvailable
  public static let backToAutomatic = MenuBar.backToAutomatic
  public static let callsAreOkay = MenuBar.callsAreOkay
  public static let openAccessibilitySettings = Station.openAccessibilitySettings
  public static let reasonAccessibilityMissing = Mast.reasonAccessibilityMissing
  public static let reasonNotPaired = Mast.reasonNoViewer

  public typealias board = Board
  public typealias mast = Mast
  public typealias station = Station
  public typealias sharing = Sharing
  public typealias thisMac = ThisMac
  public typealias privacy = Privacy
  public typealias onboardingStep1 = OnboardingStep1
  public typealias onboardingStep2 = OnboardingStep2
  public typealias onboardingStep3 = OnboardingStep3
  public typealias menuBar = MenuBar
  public typealias error = ErrorCopy
  public typealias setupError = SetupError
  public typealias diagnostics = Diagnostics
}
