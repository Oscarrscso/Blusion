<div align="center">
  <br />
  <img src="docs/readme/logo.svg" width="88" height="88" alt="Blusion app icon" />
  <h1>Blusion<sup>v.1363</sup></h1>
  <p>
    Media browser and player for iPhone, iPad and Mac,<br />
    built around Stremio addons and customisable Home widgets.
  </p>
  <p>
    <img src="docs/readme/platforms.svg" width="282" height="32" alt="iPhone, iPad and Mac" />
  </p>
  <p>
    <a href="https://github.com/Oscarrscso/Blusion/releases/latest"><strong>Latest release</strong></a>
    &nbsp;&nbsp;·&nbsp;&nbsp;
    <a href="#features">Features</a>
    &nbsp;&nbsp;·&nbsp;&nbsp;
    <a href="#more-screenshots">Screenshots</a>
    &nbsp;&nbsp;·&nbsp;
    <a href="#build">Build</a>
  </p>
</div>

<br />


<p align="center">
  <img src="docs/screenshots/movie-landscape-iphone-17.png" width="100%" alt="Movie details in landscape" />
</p>

<p align="center">
  <img src="docs/screenshots/home-iphone-17.png" width="24%" alt="Home" />
  <img src="docs/screenshots/widgets-iphone-17.svg" width="24%" alt="Widgets" />
  <img src="docs/screenshots/search-iphone-17.png" width="24%" alt="Search" />
  <img src="docs/screenshots/series-iphone-17.png" width="24%" alt="Series" />
</p>

## Features

- **Browse** — Movie, series and people search, with ratings, reviews and cast filmographies.
- **Watch** — Stremio addons, built-in playback, of literally any file or format, as well as Trakt sync.
- **Personalise** — Customisable Home widgets, shelves and layouts.

## More screenshots

<p align="center">
  <img src="docs/screenshots/library-landscape-iphone-17.png" width="100%" alt="Library in landscape" />
</p>

<p align="center">
  <img src="docs/screenshots/widget-editor-iphone-17.svg" width="24%" alt="Widget editor" />
  <img src="docs/screenshots/advanced-stream-selection-iphone-17.svg" width="24%" alt="Advanced stream selection (optional)" />
  <img src="docs/screenshots/person-iphone-17.png" width="24%" alt="People" />
  <img src="docs/screenshots/ratings-reviews-iphone-17.svg" width="24%" alt="Ratings and reviews" />
</p>

## Build

Requires a Mac, Xcode with the iOS 26 SDK or newer, and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
./scripts/generate-project.sh
open Blusion.xcodeproj
