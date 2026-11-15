<h1><img src="App/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png" width="48" height="48" alt="Blusion app icon"> Blusion <sup>v.1363</sup></h1>

<p>
  <img src="https://img.shields.io/badge/iPhone-007AFF?style=flat-square" alt="iPhone">
  <img src="https://img.shields.io/badge/iPad-007AFF?style=flat-square" alt="iPad">
  <img src="https://img.shields.io/badge/Mac-007AFF?style=flat-square" alt="Mac">
</p>

A native SwiftUI media browser and player for iPhone, iPad and Mac, built around Stremio addons and customisable Home widgets.

<p align="center">
  <img src="docs/screenshots/movie-landscape-iphone-17.png" width="100%" alt="A Bug's Life details, ratings and reviews in landscape">
</p>

## Screenshots

<!-- Device frame: fastlane/frameit-frames, latest/Apple iPhone 17 Black.png -->

<p align="center">
  <img src="docs/screenshots/home-iphone-17.png" width="24%" alt="Home with Cover Flow and film collections">
  <img src="docs/screenshots/search-iphone-17.png" width="24%" alt="Search and streaming service discovery">
  <img src="docs/screenshots/series-iphone-17.png" width="24%" alt="Cosmos series details and episode cards">
  <img src="docs/screenshots/person-iphone-17.png" width="24%" alt="Al Pacino biography and filmography">
</p>
<p align="center">
  <img src="docs/screenshots/library-landscape-iphone-17.png" width="75%" alt="Library filters and artwork grid in landscape">
</p>

## Features

### Browse

- Movie, series and people search.
- Ratings, reviews and cast filmographies.

### Watch

- Stremio addons and built-in playback.
- Trakt sync.

### Personalise

- Customisable Home widgets, shelves and layouts.

## Build

Requires a Mac, Xcode with the iOS 26 SDK or newer, and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
./scripts/enable-fallback.sh
open Blusion.xcodeproj
```

Select your development team in Xcode's Signing & Capabilities, choose a device or simulator, then run. The script generates the project with the MPVKit playback engine enabled.

*In active development.*
