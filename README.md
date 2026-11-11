# EhGaro

An unofficial iPhone and iPad app for browsing and reading E-Hentai galleries.

This is a ground-up rebuild in SwiftUI, designed for iOS 26 with a native fallback for iOS 18. Its first aim is speed: smooth lists, a reader that opens at once, and nothing heavy on the main thread.

## What it does

- Browse the front page, the popular, watched and top lists, and your history.
- Search by tag with suggestions, and keep quick searches.
- Keep favourites in the site's ten folders.
- Read full screen, paged in either direction or as one long scroll.
- Choose between three interface designs, as a whole or page by page (in progress).

## Requirements

- iOS or iPadOS 18 or later.
- Xcode 26 to build.

## Building

```sh
swift test --package-path Packages/EhKit
xcodebuild build -project EhGaro.xcodeproj -scheme EhGaro \
  -destination 'platform=iOS Simulator,name=iPhone 17' -skipMacroValidation
```

## Content

The app shows content from a third-party site and is not affiliated with it. That content is for adults.
