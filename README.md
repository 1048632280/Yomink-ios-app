# Yomink iOS App

Yomink is a native iOS TXT reader targeting iOS 15.5 and later. The app is designed as a local-only, lightweight reader with SwiftUI for product screens, UIKit for the high-performance reading surface, GRDB for SQLite storage, and the iOS file system for book content.

## Current Status

The app currently includes the core local reader workflow:

- TXT import with UTF-8/GBK/GB2312 decoding and local file storage.
- Library list/grid views, grouping, sorting, multi-select move/delete/export, and global title search.
- UIKit reader surface with paged/scroll modes, progress, bookmarks, catalog, content search, filters, reading settings, and auto-read controls.
- Storage management, reading history, random picker, and app bootstrap retry handling.
- GRDB-backed local persistence and XCTest coverage for the highest-risk import, reader, database, and storage paths.
- GitHub Actions workflow for Debug simulator build/test and unsigned Release IPA archive.

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
