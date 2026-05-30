# Yomink iOS App

Yomink is a native iOS TXT reader targeting iOS 15.5 and later. The app is designed as a local-only, lightweight reader with SwiftUI for product screens, UIKit for the high-performance reading surface, GRDB for SQLite storage, and the iOS file system for book content.

## Phase 0

The repository currently contains the initial iOS project scaffold:

- `Yomink.xcodeproj`
- SwiftUI app entry point
- UIKit reader host placeholder
- GRDB database bootstrap and first migration
- App sandbox file-store bootstrap
- GitHub Actions workflow for producing an unsigned IPA

## Build On GitHub Actions

Use the `Build Unsigned IPA` workflow from the Actions tab. It resolves Swift packages, builds the Debug simulator target, runs unit tests, archives the Release app without code signing, and uploads `Yomink-unsigned.ipa` as an artifact.

The resulting IPA is unsigned. It is suitable as a CI build artifact and must be signed before installation on a physical device.

## Local Verification

Local Windows machines cannot build this project because iOS builds require Xcode on macOS.

On macOS, run the same core checks before opening a PR:

```sh
xcodebuild -resolvePackageDependencies -project Yomink.xcodeproj -scheme Yomink
xcodebuild build -project Yomink.xcodeproj -scheme Yomink -configuration Debug -destination "generic/platform=iOS Simulator" CODE_SIGNING_ALLOWED=NO
xcodebuild test -project Yomink.xcodeproj -scheme Yomink -configuration Debug -destination "platform=iOS Simulator,name=iPhone 16" CODE_SIGNING_ALLOWED=NO
```
