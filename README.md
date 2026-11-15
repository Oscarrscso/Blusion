# Blusion <sup>v.1363</sup>

A native SwiftUI media browser and player for iPhone, iPad and Mac, built around Stremio addons and customisable Home widgets.

## Screenshots

<!-- Device frame: fastlane/frameit-frames, latest/Apple iPhone 17 Black.png -->

<p align="center">
  <img src="docs/screenshots/home-iphone-17.png" width="24%" alt="Home with Cover Flow and film collections">
  <img src="docs/screenshots/search-iphone-17.png" width="24%" alt="Search and streaming service discovery">
  <img src="docs/screenshots/series-iphone-17.png" width="24%" alt="Cosmos series details and episode cards">
  <img src="docs/screenshots/person-iphone-17.png" width="24%" alt="Al Pacino biography and filmography">
</p>
<p align="center">
  <img src="docs/screenshots/movie-landscape-iphone-17.png" width="49%" alt="A Bug's Life details, ratings and reviews in landscape">
  <img src="docs/screenshots/library-landscape-iphone-17.png" width="49%" alt="Library filters and artwork grid in landscape">
</p>

## Features

- Customisable widgets, shelves and layouts.
- Movie, series and people search.
- Ratings, reviews and cast filmographies.
- Stremio addons, built-in playback and Trakt sync.

## Build

Requires a Mac, Xcode with the iOS 26 SDK or newer, and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
./scripts/enable-fallback.sh
open Blusion.xcodeproj
```

Select your development team in Xcode's Signing & Capabilities, choose a device or simulator, then run. The script generates the project with the MPVKit playback engine enabled.

*In active development.*
