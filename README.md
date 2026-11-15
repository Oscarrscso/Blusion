<h1><img src="docs/readme/logo.svg" width="56" height="56" alt="Blusion app icon"> Blusion <sup>v.1363</sup></h1>

<p><img src="docs/readme/platforms.svg" width="282" height="32" alt="iPhone, iPad and Mac"></p>

A native SwiftUI media browser and player for iPhone, iPad and Mac, built around Stremio addons and customisable Home widgets.

<p align="center">
  <img src="docs/screenshots/movie-landscape-iphone-17.png" width="100%" alt="A Bug's Life details, ratings and reviews in landscape">
</p>

## Screenshots

### Home

<p align="center">
  <img src="docs/screenshots/home-iphone-17.png" width="32%" alt="Home with Cover Flow and film collections">
</p>

### Widgets

<p align="center">
  <img src="docs/screenshots/widgets.png" width="34%" alt="Widget collection with different shelf styles">
  <img src="docs/screenshots/widget-editor.png" width="34%" alt="Widget editor with list, genre and date options">
</p>

### Advanced stream selection <sup>optional</sup>

<p align="center">
  <img src="docs/screenshots/advanced-stream-selection.png" width="34%" alt="Advanced stream selection with Auto Pick, quality filters and technical details">
</p>

### Ratings &amp; reviews

<p align="center">
  <img src="docs/screenshots/ratings-reviews.png" width="34%" alt="Film ratings, Letterboxd reviews and TMDb reviews">
</p>

### Search &amp; discovery

<p align="center">
  <img src="docs/screenshots/search-iphone-17.png" width="32%" alt="Search and streaming service discovery">
  <img src="docs/screenshots/series-iphone-17.png" width="32%" alt="Cosmos series details and episode cards">
  <img src="docs/screenshots/person-iphone-17.png" width="32%" alt="Al Pacino biography and filmography">
</p>

### Library

<p align="center">
  <img src="docs/screenshots/library-landscape-iphone-17.png" width="100%" alt="Library filters and artwork grid in landscape">
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
