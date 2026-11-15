<h1><img src="docs/readme/logo.svg" width="56" height="56" alt="Blusion app icon"> Blusion <sup>v.1363</sup></h1>

<p><img src="docs/readme/platforms.svg" width="282" height="32" alt="iPhone, iPad and Mac"></p>

A native SwiftUI media browser and player for iPhone, iPad and Mac, built around Stremio addons and customisable Home widgets.

## Screenshots

<!-- All portrait screenshots use fastlane/frameit-frames, Apple iPhone 17 Black. -->

<table>
  <tr>
    <th width="25%">Home</th>
    <th width="25%" colspan="2">Widgets</th>
    <th width="25%">Advanced stream selection<br><sup>optional</sup></th>
  </tr>
  <tr>
    <td width="25%"><img src="docs/screenshots/home-iphone-17.png" width="210" alt="Home with Cover Flow and film collections"></td>
    <td width="25%"><img src="docs/screenshots/widgets-iphone-17.svg" width="210" alt="Widget collection with different shelf styles"></td>
    <td width="25%"><img src="docs/screenshots/widget-editor-iphone-17.svg" width="210" alt="Widget editor with list, genre and date options"></td>
    <td width="25%"><img src="docs/screenshots/advanced-stream-selection-iphone-17.svg" width="210" alt="Advanced stream selection with Auto Pick and quality filters"></td>
  </tr>
</table>

<table>
  <tr>
    <th width="25%">Search</th>
    <th width="25%">Series</th>
    <th width="25%">People</th>
    <th width="25%">Ratings &amp; reviews</th>
  </tr>
  <tr>
    <td width="25%"><img src="docs/screenshots/search-iphone-17.png" width="210" alt="Search and streaming service discovery"></td>
    <td width="25%"><img src="docs/screenshots/series-iphone-17.png" width="210" alt="Series details and episode cards"></td>
    <td width="25%"><img src="docs/screenshots/person-iphone-17.png" width="210" alt="Biography and filmography"></td>
    <td width="25%"><img src="docs/screenshots/ratings-reviews-iphone-17.svg" width="210" alt="Film ratings, Letterboxd reviews and TMDb reviews"></td>
  </tr>
</table>

<table>
  <tr><th width="50%">Movie details</th><th width="50%">Library</th></tr>
  <tr>
    <td width="50%"><img src="docs/screenshots/movie-landscape-iphone-17.png" width="440" alt="Movie details in landscape"></td>
    <td width="50%"><img src="docs/screenshots/library-landscape-iphone-17.png" width="440" alt="Library filters and artwork grid in landscape"></td>
  </tr>
</table>

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
