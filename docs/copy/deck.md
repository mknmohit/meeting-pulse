# Meeting Pulse copy deck

Every user-facing string in the product. Nothing is improvised at the call site.

Implementations import from here: `viewer/src/lib/copy.ts` and `MPSupport/Strings.swift`. A CI check greps both surfaces for string literals inside render code and fails on anything not sourced from a copy module.

---

## Who is reading, and how they feel

**The viewer.** She is standing near a closed door with a phone in her hand, mildly impatient, half-distracted. She wants one word. She does not want to be taught anything, does not want an apology, and will not read a second paragraph.

**The owner.** He is technical, he installed this once, and he wants to forget it exists. The only moments he reads anything are the permission request (mild alarm at a scary-sounding permission), the recovery phrase (needs to understand the stakes in one sentence), and the delete confirmation (needs to know exactly what he is about to lose).

Two rules follow from that, and they govern every line below. Say the thing in the words you would use across a kitchen table. Every failure message names what to do next and never blames the reader.

---

## The board

`{Name}` is the owner's display name when set. When it is blank, the shorter form is used and nothing shifts.

| Viewer result | Shape | Headline | Supporting line |
|---|---|---|---|
| busy, calls not okay | cone | `{Name} is in a meeting` / `In a meeting` | `Better to wait.` |
| busy, calls okay | pennant | `{Name} is in Meeting, but it's fine to ring through` / `In Meeting, but it's fine to ring through` | `He said to go ahead and interrupt.` |
| every other fresh, stale, or unsupported result | bare mast | `Meeting status unavailable` | `Check again before you call.` |
| offline | bare mast | `Meeting status unavailable` | `Connect to the internet, then check again.` |
| not paired | bare mast | `Not connected` | `Open the viewer link or enter the code he shared.` |

Only the two busy rows take `{Name}` in the headline. The other three do not, and
the name is shown in a separate line beneath the plate instead.

The neutral line is intentional. The page never tells her that the owner is
free when the Mac cannot provide a trustworthy meeting signal.

## The chalked rail

`Checked just now` · `Checked 40 seconds ago` · `Checked 4 minutes ago` · after ten minutes, `Checked a while ago`

Button: `Check again`. While fetching: `Checking`.

Both time words are plural-aware. "Checked 1 minute ago", never "1 minutes".

## Pairing

- Heading: `Enter the code`
- Lede: `Ask him for the viewer link or code. The link keeps working until he rotates it.`
- Field label: `Code`
- Button: `Connect`
- Invalid, expired, or revoked: `That code didn't work. Ask for a fresh link or code.`
- Rate limited: `Too many tries. Wait a few minutes and try again.`
- Offline: `You're offline. Connect to the internet and try again.`
- After storage eviction: `This device was signed out. Ask him for a new code.`
- After a successful pair, on iOS: `Add this to your home screen so it's one tap away.`

Four different server reasons collapse into one message on purpose. Telling her which one it was would tell an attacker whether a guessed code belongs to somebody.

---

## Owner app

### Accessibility permission

> **Meeting Pulse needs to see your windows**
>
> macOS calls this Accessibility. Meeting Pulse uses it to check two things: whether Chrome has a Google Meet call open, and whether Slack has a huddle running.
>
> It does not read page contents, meeting names, links, or anything you type. It never asks for screen recording, and it never touches your screen, microphone, or camera.
>
> `Open Accessibility settings`

Permission still missing after returning: `Still waiting on permission. Meeting Pulse can't tell whether you're on a call until you grant it, so the page will show "Meeting status unavailable".`

Two corrections were made to this section. It previously said "Three things
leave this Mac" and named the states as "free, on a call, or no signal", and it
referred to the page showing `No signal`.

Neither was accurate. `StatusPayload` carries five fields, and the display name
travels separately, so five things leave the Mac. And the viewer has never
rendered the words "free", "on a call", or "No signal"; its three plate
headlines are `In a meeting`, `In Meeting, but it's fine to ring through`, and
`Meeting status unavailable`.

The full, sourced accounting now lives in **Privacy** below. The onboarding step
that replaces this screen does not repeat the list; it links to that section
instead, so there is one place to keep correct.

### Menu

Superseded by **The reduced menu bar** below. The thirteen-item menu it described
is being cut to six, and the nine removed items now live in the station window.
The duration submenu is unchanged and is documented in the new section.

### Pairing window

Superseded by **Sharing** below. The standalone window is being removed and its
contents become a section of the station.

### Recovery phrase

> **Save this phrase**
>
> If this Mac is wiped or replaced, this code is the only way to keep your connection without asking her to pair again. Anyone who has it can take over publishing your status, so store it where you keep passwords.
>
> `I've saved it`

Superseded: `Another Mac took over publishing your status. This one has stopped. If that wasn't you, enter your recovery phrase here to take it back.`

### Delete everything

> **Delete everything?**
>
> This removes your status, your pairing codes, and her connection from the server. She'll see "Not connected" and will need a new code. This can't be undone.
>
> Type `delete` to confirm.


### The station window

The owner app's window. Four sections in a sidebar, with the mast above them.
Full specification in `docs/05-owner-app-ui-plan.md`.

#### The mast

Mode control: `Busy` · `Automatic` · `Free`. Duration label: `Until`. Toggle: `Calls are okay`.

The plate mirrors the viewer's board exactly, so its headlines and supporting
lines come from **The board** above, not from here.

Reason lines, in precedence order. The first one that applies is shown.

| When | Line |
|---|---|
| Everything was deleted | `Everything on this Mac is gone. Quit to finish.` |
| Accessibility is not granted | `Waiting for Accessibility permission` |
| Another Mac took over | `Another Mac took over. This one has stopped.` |
| Can't reach the server | `Can't reach the server. Retrying.` |
| No viewer link yet | `No one is watching yet. Create a link.` |
| Busy override, timed | `Busy for another {n} minutes` |
| Busy override, no end | `Busy until you clear it` |
| Available override, timed | `Available for another {n} minutes` |
| Available override, no end | `Available until you clear it` |
| A call was detected | `{Source} call detected` |
| A window looked like a call | `A window looked like a call. Not sure enough.` |
| Otherwise | `Watching automatically` |

When calls are okay but the state is not busy, the line gains a second sentence:
`Calls are okay when you are busy.` Without it the toggle looks broken, because
the plate cannot change until he is actually in a meeting.

#### The rail

`Nothing published yet` · `Published {relative} ago` · `Publishing...` · `No network. Waiting.` · `Another Mac is publishing now`

Relative times are coarse on purpose: `just now` under ten seconds, then seconds,
then minutes, then hours. Never a precise timestamp. This is not a log.

#### Watch

Section title: `Watch`

- Group headers: `Permission` · `What the Mac watches` · `Publishing`
- Accessibility row: `Accessibility`, value `Granted` or `Not granted`, detail `Meeting Pulse reads window titles. It never reads what is inside them.`
- Permission banner: `Meeting Pulse can't see your windows yet.` / `Turn on Accessibility so the Mac can read window titles. It never reads what is inside them.` / `Open Accessibility settings`
- If that button fails: `Open System Settings, then Privacy & Security, then Accessibility.`
- Sources: `Google Meet` · `Slack huddles`
- Source values: `In a call` · `No call` · `Can't tell` · `Not seen yet`
- Source details: `Checked {relative} ago` · `Meeting Pulse will notice the next time you join.`
- Publishing rows: `Last published` · `Checks run` (`Every {active}s in a call, {idle}s idle`) · `This Mac` (`Publishing` / `Retrying` / `Stopped`)
- Superseded banner: `Another Mac took over.` / `Meeting Pulse is running somewhere else. This Mac has stopped publishing.`

`Can't tell` is not the same as `No call` and must never be shown in its place.
The Mac says it does not know, because sometimes it does not, and pretending
otherwise is how she gets told he is free while he is in a meeting.

#### Sharing

Section title: `Sharing`

- Empty state: `No one is watching yet.` / `Create a link and send it to whoever needs to know when to call.` / `Create the viewer link`
- Group headers: `The link` · `Who has the link`
- Buttons: `Copy link` · `Copy code` · `Share` · `Create a new link` · `Stop sharing`
- After copying: `Copied`
- New link confirmation: `Create a new link?` / `The old link stops working right away. Anyone using it will need the new one.`
- Stop sharing confirmation: `Stop sharing?` / `The link stops working right away. No one will be able to see your status.`
- Viewer rows: `Paired {relative} ago`
- Empty list: `Nobody has used the link yet.`
- Failed list: `Can't load the list right now.` with `Try again`
- Remove a viewer: `Remove`

Viewer rows never carry a name, because the server does not have one. Showing
when the pairing happened is honest. Inventing a device nickname is not.

#### This Mac

Section title: `This Mac`

- Group headers: `Your name` · `Startup` · `If you lose this Mac`
- Name field: label `Name`, detail `Shown on the page as "{Name} is in a meeting". Leave it blank to stay unnamed.`, saved confirmation `Saved`
- Startup toggles: `Open at login` · `Open the window at login`
- Recovery row: `Recovery phrase`, detail `A code that lets you take over from a new Mac. Write it down somewhere safe.`, buttons `Show` / `Hide` / `Copy the phrase`
- Recovery warning: `Anyone with this code can take over your status. Keep it somewhere only you can reach.`
- Install banner: `Meeting Pulse is not in your Applications folder.` / `Move it to Applications so it keeps running after updates.` / `Show me in Finder`
- Danger zone: `Delete everything` / `Removes your status, the viewer link, and the recovery phrase. This cannot be undone.` / `Delete...`
- Delete sheet: `Delete everything?` / `This removes your status, the viewer link, and the recovery phrase from this Mac and from the server. The page anyone has open will stop working.` / `Type delete to confirm.`
- After deleting: `Everything is gone.` / `Meeting Pulse has nothing left to publish. Quit and delete the app, or set it up again.` / `Set up again`

#### Privacy

Section title: `Privacy`

Three columns, because there are three different lists and collapsing them into
two would let a reader assume the middle one does not exist.

| `What leaves this Mac` | `What she can see` | `What never leaves this Mac` |
|---|---|---|
| `In a meeting, or not` | `In a meeting, or not` | `Window titles` |
| `Whether calls are okay` | `Whether calls are okay` | `Meeting names` |
| `Whether you set it by hand` | `The name you chose` | `Who you are meeting` |
| `When that runs out` | `When it was last sent` | `Calendar events` |
| `The name you chose` | | `Screen contents` |
| | | `Audio` |
| | | `Anything you type` |

Explanation: `Meeting Pulse reads the titles of windows that are already open to work out whether you are in a call. The titles stay on this Mac.`

Boundary: `The server knows whether you set your status by hand and when that runs out. She cannot. The page she loads is not allowed to ask for those.`

The left column is `StatusPayload` plus the display name. The middle column is
what `get_paired_status()` returns. Neither is a summary of the other, and the
copy must be re-derived from the source whenever either changes.

### The reduced menu bar

The menu keeps only what someone reaches for mid-meeting. Everything else moved
into the window.

Header, two lines: the plate headline, then the reason line.

`Set busy` · `Set available` · `Back to automatic` · `Calls are okay` · `Open Meeting Pulse` · `Quit Meeting Pulse`

Duration submenu, unchanged: `15 minutes` · `30 minutes` · `45 minutes` · `1 hour` · `2 hours` · `4 hours` · `Until I clear it`

`Back to automatic` appears only while an override is running. A permanently
greyed-out item teaches nothing.

Removed from the menu: `Check and publish now`, `Display name...`,
`Create viewer link...`, `Rotate viewer link...`, `Revoke viewer access...`,
`Show recovery phrase...`, `Diagnostics...`, `Delete everything...`. All are in
the window.

### Setup

Three steps. Each one ends with the reader having done something.

1. `Meeting Pulse tells one person when to call you.` / `It notices when you are in a Google Meet or a Slack huddle and puts "In a meeting" on a private page. Nothing else leaves this Mac.` / `Get started`
2. `Let the Mac see your window titles.` / `Meeting Pulse reads the titles of open windows to work out whether you are in a call. It never reads what is inside them, and titles stay on this Mac.` / `Open Accessibility settings` / `Skip for now`
   - While waiting: `Waiting...` Once granted: `Accessibility is on.`
3. `Send this to whoever needs it.` / `They open the link and see one word. They do not need an account, and they cannot see anything else.` / `Create the link` / `Do this later` / `Open Meeting Pulse`

Step 2 advances by itself the moment permission is granted. He should be able to
grant it in System Settings and find the app already on step 3 when he switches
back.

### Failures

Every failure names what to do next. No two share a message.

| When | Line |
|---|---|
| The request failed | `Can't reach the server. Retrying.` |
| There is no network | `No network. Waiting.` |
| Local storage failed | `Meeting Pulse couldn't access its local data. Try again.` |
| Accessibility is missing | `Meeting Pulse can't see your windows yet.` |
| The recovery phrase is wrong | `That phrase doesn't match. Check for typos.` |
| macOS blocked the login item | `macOS blocked this. Open Login Items in System Settings to allow it.` |
| Creating a link failed | `Couldn't create the link. Try again.` |
| Loading the viewer list failed | `Can't load the list right now.` |

Nine `catch` blocks in `MeetingPulseApp.swift` currently share the first line,
including the local storage and permission cases. That is why this table exists.

### Setup errors

Missing configuration: `Meeting Pulse isn't configured yet. {KEY} is missing from Config.xcconfig. Copy Config.xcconfig.example and fill it in, then reopen the app.`

Wrong install location: `Move Meeting Pulse to your Applications folder first. Running it from here breaks the login item and the permission you're about to grant.` Buttons: `Move and reopen` · `Not now`

### Native owner implementation additions

These strings are used by the native owner surface and remain sourced through
`MPSupport/Strings.swift`:

- Startup: `Starting up.`
- Available override hint: `Currently available. Set busy to override.`
- Station check action: `Check and publish now` / `Publish the current status now.`
- Recovery auto-hide: `The recovery code is hidden.` / `Reveal again`
- Name save action: `Save name` / `Saved`

---

## Words this product does not use

Not out of squeamishness. Each one either misleads her or makes the product sound like it was written by a machine.

**seamless, effortless, powerful, robust, leverage, utilize, delve, elevate, unlock.** Promotional filler that says nothing.

**Oops, Uh oh, Something went wrong, An error occurred.** Cheerful vagueness at the exact moment she needs a fact.

**Please note that, In order to, At this point in time.** Filler where a shorter phrase is clearer.

**Free** as a headline. The board does not claim that the owner is free when the Mac cannot provide a trustworthy meeting signal.

**Online, Offline, Active, Idle, Status: Green.** Dashboard vocabulary. She is not monitoring a service, she is deciding whether to open a door.

**Enabled, Disabled, N/A, Unknown, Error, Failed, Success.** The same problem one layer down, in the owner app. A row that reads `Accessibility: Enabled` is a database field with a colon in it. `Granted` is a word a person would say.

**Em dashes.** Replaced with a period, a comma, or a colon everywhere, including in this list.
