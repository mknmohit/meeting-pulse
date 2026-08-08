# Meeting Pulse acceptance matrix

This document is the release record for the real-device matrix in
`docs/03-implementation-plan.md`. A scenario is `PASS` only after it has been
run on the release build and the observed result is written down. Unperformed
scenarios remain `NOT RUN`; they are never inferred from unit tests.

| # | Scenario | Status | Evidence |
|---:|---|---|---|
| 1 | Scheduled Meet in Chrome | LOCAL PASS | Installed unsigned app reported `meet=active` and reducer `busy`; viewer publish not verified |
| 2 | Impromptu Meet link | NOT RUN | Requires a real meeting |
| 3 | Joining someone else's link | NOT RUN | Requires a real meeting |
| 4 | Leaving Meet normally | NOT RUN | Requires a real meeting |
| 5 | Closing Meet or Chrome unexpectedly | NOT RUN | Requires a real meeting |
| 6 | Slack Huddle start | LOCAL PASS | Installed unsigned app reported `slack=active` and reducer `busy`; viewer publish not verified |
| 7 | Slack Huddle end | NOT RUN | Requires a real Huddle |
| 8 | Huddle while Slack is unfocused | NOT RUN | Requires a real Huddle |
| 9 | Switching Chrome tabs during Meet | SPIKE PASS | `docs/decisions/0001-meet-detection-strategy.md` |
| 9b | Switching to another app during Meet | SPIKE PASS | Gate G1 evidence |
| 9c | Two Meet calls, close one | SPIKE PASS | Gate G1 evidence |
| 10 | Manual Busy with no meeting | NOT RUN | Requires the finished owner app |
| 11 | Manual Available during a meeting | NOT RUN | Requires the finished owner app |
| 12 | Calls okay while Busy | NOT RUN | Requires the finished owner app and viewer |
| 13 | Restart and launch at login | NOT RUN | Requires install and login-item approval |
| 13b | Restart during a backgrounded Meet | NOT RUN | Requires a real meeting |
| 14 | Sleep and wake | NOT RUN | Requires the owner's Mac |
| 15 | Network loss and recovery | NOT RUN | Requires a real deployment |
| 16 | Remove and restore Accessibility | SPIKE PARTIAL | Permission denial is fail-closed; release recovery not run |
| 17 | Viewer page closed and reopened | AUTOMATED PARTIAL | Viewer poller and freshness tests |
| 18 | Pairing revoke and rotation | DATABASE PASS | pgTAP RPC and RLS coverage |
| 19 | Viewer Check again | AUTOMATED PARTIAL | Viewer poller tests |
| 20 | Hidden/unfocused polling pause | AUTOMATED PARTIAL | Viewer poller tests |
| 21 | Recovery rebind after local storage loss | NOT RUN | Requires two real Macs or a cleared local secrets file |
| 22 | Phone clock six hours wrong | AUTOMATED PARTIAL | Server-time freshness tests |
| 23 | Override expiry during sleep | UNIT PASS | Monotonic override expiry tests |
| 24 | Graceful Quit | NOT RUN | Requires the finished owner app |
| 25 | Clearing Safari site data | NOT RUN | Requires a real iPhone/Safari run |
| 26 | Same-signature in-place upgrade | NOT RUN | Requires signed release builds |
| 27 | Four-hour background interval measurement | NOT RUN | Requires a release build |
| 28 | Rebinding on a second Mac | NOT RUN | Requires two real Macs |
| 29 | Meet in a second Chrome profile | NOT RUN | Requires a real Chrome profile |
| 30 | Wall clock moved back six hours | UNIT PASS | Monotonic override tests |

The release cannot be called accepted while any required real-device row is
`NOT RUN`.

Latest automation note: the owner performance script reached the memory
measurement but macOS refused `footprint` without root privileges. The
performance row remains `NOT RUN` until that measurement is run with the
required privilege. The unsigned Release build completed, and the remote
Supabase migration list includes the persistent-pairing migration.
