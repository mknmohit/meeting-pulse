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

| State | Shape | Headline | Supporting line |
|---|---|---|---|
| available | disc | `{Name} is free` / `Free` | `Go ahead.` |
| busy | cone | `{Name} is on a call` / `On a call` | `Better to wait.` |
| busy + call okay | cone + pennant | `{Name} is on a call` / `On a call` | `He said it's fine to interrupt.` |
| unavailable | bare mast | `No signal` | `His Mac stopped reporting a few minutes ago. This could be wrong either way, so assume he might be busy.` |
| not paired | bare mast | `Not connected` | `Ask him for a code and enter it below.` |
| offline | bare mast | `No signal` | `Your phone is offline. This is the last thing we heard.` |
| schema too new | bare mast | `No signal` | `This page is out of date and can't read the latest status. Reload it.` |

The `unavailable` line is the most important sentence in the product. It refuses to guess in either direction, and it tells her what to assume. Anything shorter would leave her to fill the gap herself, and she would fill it with "he's probably free".

## The chalked rail

`Checked just now` · `Checked 40 seconds ago` · `Checked 4 minutes ago` · after ten minutes, `Checked a while ago`

Button: `Check again`. While fetching: `Checking`.

Both time words are plural-aware. "Checked 1 minute ago", never "1 minutes".

## Pairing

- Heading: `Enter the code`
- Lede: `Ask him for a code from the menu bar. It works once and expires in ten minutes.`
- Field label: `Code`
- Button: `Connect`
- Invalid, expired, already used, or revoked: `That code didn't work. Ask for a fresh one.`
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
> Three things leave this Mac: one word (free, on a call, or no signal), whether calls are okay right now, and the name you choose to show.
>
> `Open Accessibility settings`

Permission still missing after returning: `Still waiting on permission. Meeting Pulse can't tell whether you're on a call until you grant it, so the page will show "No signal".`

### Menu

`Set busy…` · `Set available…` · `Clear override` · `Calls are okay` · `Check and publish now` · `Display name…` · `Create pairing code…` · `Rotate codes` · `Disconnect viewer` · `Show recovery phrase…` · `Diagnostics…` · `Delete everything…` · `Quit Meeting Pulse`

Duration submenu: `15 minutes` · `30 minutes` · `45 minutes` · `1 hour` · `2 hours` · `4 hours` · `Until I clear it`

Status lines: `Busy for another 12 minutes` · `Watching automatically` · `Last published 30 seconds ago` · `Can't reach the server. Retrying.`

### Pairing window

> **Give her this code**
>
> It works once and expires in ten minutes. If she needs another one later, come back here and make a new one.
>
> `ABCDE-FGHJK`   `Copy`   `Expires in 9:42`

### Recovery phrase

> **Save this phrase**
>
> If this Mac is wiped or replaced, this phrase is the only way to keep your connection without asking her to pair again. Anyone who has it can take over publishing your status, so store it where you keep passwords.
>
> `I've saved it`

Superseded: `Another Mac took over publishing your status. This one has stopped. If that wasn't you, enter your recovery phrase here to take it back.`

### Delete everything

> **Delete everything?**
>
> This removes your status, your pairing codes, and her connection from the server. She'll see "Not connected" and will need a new code. This can't be undone.
>
> Type `delete` to confirm.

### Setup errors

Missing configuration: `Meeting Pulse isn't configured yet. {KEY} is missing from Config.xcconfig. Copy Config.xcconfig.example and fill it in, then reopen the app.`

Wrong install location: `Move Meeting Pulse to your Applications folder first. Running it from here breaks the login item and the permission you're about to grant.` Buttons: `Move and reopen` · `Not now`

---

## Words this product does not use

Not out of squeamishness. Each one either misleads her or makes the product sound like it was written by a machine.

**seamless, effortless, powerful, robust, leverage, utilize, delve, elevate, unlock.** Promotional filler that says nothing.

**Oops, Uh oh, Something went wrong, An error occurred.** Cheerful vagueness at the exact moment she needs a fact.

**Please note that, In order to, At this point in time.** Filler where a shorter phrase is clearer.

**Unavailable** as a headline. It is technically the state's name, but it reads like the product broke rather than like a deliberate signal. The board says `No signal` and explains what to assume.

**Online, Offline, Active, Idle, Status: Green.** Dashboard vocabulary. She is not monitoring a service, she is deciding whether to open a door.

**Em dashes.** Replaced with a period, a comma, or a colon everywhere, including in this list.
