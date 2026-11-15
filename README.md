<h1><img src="docs/readme/logo.svg" width="56" height="56" alt="Blusion app icon"> Blusion <sup>v.1363</sup></h1>

<p><img src="docs/readme/platforms.svg" width="282" height="32" alt="iPhone, iPad and Mac"></p>

A native SwiftUI media browser and player for iPhone, iPad and Mac, built around Stremio addons and customisable Home widgets.

[Latest release](https://github.com/Oscarrscso/Blusion-public/releases/latest)

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

## Screenshots

<!-- All portrait screenshots use fastlane/frameit-frames, Apple iPhone 17 Black. -->

<table width="100%">
  <tr><th width="50%">Home</th><th width="50%">Widgets</th></tr>
  <tr>
    <td width="50%"><img src="docs/screenshots/home-iphone-17.png" width="100%" alt="Home"></td>
    <td width="50%"><img src="docs/screenshots/widgets-iphone-17.svg" width="100%" alt="Widgets"></td>
  </tr>
  <tr><th width="50%">Widget editor</th><th width="50%">Advanced stream selection<br><sup>optional</sup></th></tr>
  <tr>
    <td width="50%"><img src="docs/screenshots/widget-editor-iphone-17.svg" width="100%" alt="Widget editor"></td>
    <td width="50%"><img src="docs/screenshots/advanced-stream-selection-iphone-17.svg" width="100%" alt="Advanced stream selection"></td>
  </tr>
  <tr><th width="50%">Search</th><th width="50%">Series</th></tr>
  <tr>
    <td width="50%"><img src="docs/screenshots/search-iphone-17.png" width="100%" alt="Search"></td>
    <td width="50%"><img src="docs/screenshots/series-iphone-17.png" width="100%" alt="Series"></td>
  </tr>
  <tr><th width="50%">People</th><th width="50%">Ratings &amp; reviews</th></tr>
  <tr>
    <td width="50%"><img src="docs/screenshots/person-iphone-17.png" width="100%" alt="People"></td>
    <td width="50%"><img src="docs/screenshots/ratings-reviews-iphone-17.svg" width="100%" alt="Ratings &amp; reviews"></td>
  </tr>
  <tr><th colspan="2">Movie details</th></tr>
  <tr><td colspan="2"><img src="docs/screenshots/movie-landscape-iphone-17.png" width="100%" alt="Movie details in landscape"></td></tr>
  <tr><th colspan="2">Library</th></tr>
  <tr><td colspan="2"><img src="docs/screenshots/library-landscape-iphone-17.png" width="100%" alt="Library in landscape"></td></tr>
</table>
