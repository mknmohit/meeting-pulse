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

## Local unsigned and ad-hoc builds

Contributors without an Apple Developer Program account can build locally with
`make mac-local-build`. These artifacts are not notarized, are not trusted
release packages, and must not be uploaded or redistributed. macOS may require
a new Accessibility grant after every unsigned or ad-hoc rebuild. Keep the
bundle identifier unchanged so a future Developer ID release has one stable
identity and an explicit permission migration story.

The app stores the Supabase session token and local device secrets in
`~/Library/Application Support/MeetingPulse/secrets.plist`. The app creates the
containing directory with owner-only permissions and writes the file with
owner-only read/write permissions. These values are not encrypted and are not
stored in Keychain or synchronized through iCloud.
