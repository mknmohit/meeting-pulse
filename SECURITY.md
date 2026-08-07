# Security policy

## Reporting a vulnerability

Please report security issues privately to the repository maintainers. Do not
open a public issue for a vulnerability.

## Signing identity and Accessibility permission

Meeting Pulse's Accessibility permission is bound by macOS to the application's
code-signing identity and bundle identifier. Changing the signing certificate
or the bundle identifier silently revokes the grant on every existing
installation. The app will look broken and the user will have no idea why.
The signing identity and the bundle identifier do not change between releases
without a documented migration notice.

The release bundle identifier is `com.techdevix.meetingpulse`. Development
builds and release builds use different signatures, so each requires its own
Accessibility grant while working on the app.
