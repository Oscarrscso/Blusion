# Blusion

A native SwiftUI media browser and player for iPhone, iPad and Mac, built around Stremio addons and customisable Home widgets.

## Screenshots

<p align="center">
  <img src="docs/screenshots/home.jpeg" width="24%" alt="Home with Cover Flow and film collections">
  <img src="docs/screenshots/search.jpeg" width="24%" alt="Search and streaming service discovery">
  <img src="docs/screenshots/series.jpeg" width="24%" alt="Cosmos series details and episode cards">
  <img src="docs/screenshots/person.jpeg" width="24%" alt="Al Pacino biography and filmography">
</p>
<p align="center">
  <img src="docs/screenshots/movie-landscape.jpeg" width="49%" alt="A Bug's Life details, ratings and reviews in landscape">
  <img src="docs/screenshots/library-landscape.jpeg" width="49%" alt="Library filters and artwork grid in landscape">
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
