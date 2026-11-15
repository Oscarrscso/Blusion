# Player

Playback rules. Engine behaviour that is not a product rule lives in `AVEngine`, `AetherSession` and `MPVBackend`.

## Routing

`PlaybackPolicy` chooses the engine from the container: sniffed bytes, then Content-Type, then the extension. MP4, MOV, M4V and HLS stay on AVPlayer. Anything else goes to the fallback engine when it is linked and enabled in Settings. `behaviorHints.notWebReady` does not force the fallback engine. It only breaks a tie when the container is unknown and the URL has no extension. Audio AVPlayer cannot decode (DTS, TrueHD) still uses the fallback engine. AV1 uses the fallback engine only where VideoToolbox cannot decode it; on A17 Pro, M3 and later, AVPlayer keeps AV1.

If AVPlayer fails before the first frame with a format error, the coordinator plays that stream once in the fallback engine at the same position, only when the engine is linked and enabled. Network and timeout failures are not retried that way. A dropped connection mid-stream reloads the same stream once where it stopped. A buffer that is still filling is not a stall.

`infoHash` streams play only when the user has set a streaming-server URL: `<base>/<infoHash lowercased>/<fileIdx>`, or `-1` when the addon omits the index. No torrent engine is embedded. The URL can carry credentials, so it is a secret. A torrent that has been turned into an HTTP URL by that server is still ineligible for native download.

Streams with `behaviorHints.proxyHeaders.request` load through `HeaderResourceLoader` on a custom scheme. The undocumented `AVURLAssetHTTPHeaderFieldsKey` path exists only behind `BLUSION_UNDOCUMENTED_AV_HEADERS`, which release builds leave off. Do not set `NSAllowsArbitraryLoads`. `NSAllowsArbitraryLoadsForMedia` exempts only loads AVFoundation performs itself. Header-loader and download `URLSession` requests still follow ATS, so plain HTTP to a non-local host fails and the coordinator moves on.

Picture in Picture starts only from a user action. mpv has no PiP and no video AirPlay. AetherEngine's PiP uses AVKit on the layer it draws.

## Engines

`scripts/generate-project.sh` generates the project; both fallback engines are always linked. Both apps pin the LGPL MPVKit build. `Packages/AetherPlayer` is its own dynamic framework so its FFmpeg binds to `AetherLib*`, not to MPVKit's static FFmpeg. Link the LGPL MPVKit product only.

AetherEngine is the default for streams AVPlayer cannot open (Settings → Fallback player → Engine). mpv is the other choice, and the one used for full ASS styling, an external audio file, deinterlacing and a tone-mapping choice. A stream AetherEngine cannot start is tried once in mpv at the same position.

| | AVPlayer | AetherEngine | mpv |
|---|---|---|---|
| Where | both | both; Mac slices are arm64, made by `scripts/aether-catalyst-slices.py` from the macOS binaries (platform tag only) | both, LGPL MPVKit |
| Role | native containers | default fallback; demuxes with its FFmpeg and hands AVPlayer what it can play | backup, and full subtitle styling |
| HDR | system HDR10, HLG, Dolby Vision | system HDR10, HDR10+, HLG, Dolby Vision. Profile 7 FEL can be composed in Metal (Settings, on by default); otherwise the base layer | HDR10, HLG, DV 5 and 8 via libplacebo. DV 7 enhancement layer is not decoded. HDR10+ metadata is unused |
| Atmos | E-AC-3 objects pass through where the route supports them | TrueHD Atmos and DTS:X render to a 7.1.4 spatial bed (Settings, on by default). E-AC-3 objects pass through on the native route. An FEL title's E-AC-3 plays as its channel bed; turn FEL composition off to get the native route back | channel bed only |
| Subtitles | embedded text; files drawn by the app (ASS styling simplified) | embedded text, PGS, VobSub, DVB with the app's style. "Show Full Styling" moves the stream to mpv | libass, full ASS, PGS, VobSub, DVB |
| Not on this engine | external audio, deinterlace, tone-mapping choice | external audio, deinterlace, tone-mapping choice, upscaling, Ambient Mode | PiP, video AirPlay, Ambient Mode |

AVPlayer upscaling is VideoToolbox super resolution for SDR below the screen's resolution. It steps aside for HDR, unsupported chips, embedded subtitles, or when it cannot keep up. mpv's "High quality" scale is EWA Lanczos (Spline36 in Low Power Mode). mpv has no AI scaler; its AI mode uses the same scale and says so.

On Mac, embedded E-AC-3 at normal speed is sent as encoded packets through an AVPlayer resource-loader asset so the system decoder receives the JOC extension. mpv keeps the picture and a null audio output. Other speeds and a native failure return to mpv's PCM path. Other Mac audio prefers mpv's AVFoundation sample-buffer output, with AudioUnit as the initialization fallback.

Chapters, Skip Intro/Recap/Credits from chapter names, speed, tracks (language and name), delays, picture settings and engine-loaded files carry across an engine change.

## Opening and gestures

Until the first frame is on screen (`PlayerContent.isVideoReady`; AirPlay counts), the player shows a spinner on black and Close: no poster, play button, skip buttons, subtitles or scrubber. The next stream waits the same way. After that the spinner is only for a stall, with the controls hidden. Video views lay out with Core Animation actions off, so a new size or scaling mode does not slide the picture. A rotation applies its safe-area inset at once.

A stream Blusion plays opens only once `PlayerViewModel.prepare` has it ready: muted, paused on the first frame, not recording progress. The first listed stream starts readying when it arrives. Tapping another replaces it; tapping the spinning one cancels it; leaving the picker closes it. A muted start still takes the audio session. The picture can be drawn only once the player screen is up, so the spinner continues from the button until the first frame.

A single tap shows or hides controls immediately, with no haptic and no fade-in wait. A second tap skips or plays and pauses as configured.

Holding the picture for 0.1 s plays at 2× (`SpeedHoldRules`, `PictureHoldGesture`). Dragging up adds 1× per 40 points and never steps down. Dragging down 40 points from that step locks the speed after the finger lifts; the same drag unlocks it. While a drag moves toward a lock change, the badge shows the lock that change would leave and how far the drag has gone. The ceiling is the engine's: mpv 4×; AVPlayer 4× when `canPlayFastForward` allows it, otherwise 2×; AetherEngine video 2×; AetherEngine audio-only 3×. During the hold there is no seek, brightness, volume, dismissal, controls or pinch. Lifting returns the previous speed, except a locked hold, which survives until one of those endings or an unlock drag. The UIKit delegate allows the SwiftUI swipe to track at the same time; ownership stays latched through release so the end of a hold cannot become a swipe or tap. iPhone and Mac share this.

On iPhone and iPad a sideways swipe seeks live (`SwipeSeek`): five minutes across the width at the top of the picture, five seconds at the bottom, capped at the duration. Vertical movement alone does not jump the target. Once seeking starts it continues until release. Vertical swipes that start at the sides still control brightness (left) and system volume (right, through a mounted `MPVolumeView`, with no extra attenuation). A vertical swipe that starts upward in the centre can turn into a seek. A pinch stops further seeks at the last live position. The target time is a top glass pill. Picture dragging is off on Mac. Mac seeks with the timeline and with ← → (Settings → Player skip distance), sets volume with ↑ ↓ and M, and mutes per player. An app cannot set a Mac display's brightness. Pinch zoom is iPhone/iPad only; both platforms have Zoom in the Picture tab.

The Picture tab is Fit / Fill / Stretch, Zoom, Aspect Ratio and Crop. mpv applies aspect and crop itself. AVPlayer and AetherEngine use `VideoGeometry`. Fit is remembered. Zoom, aspect and crop are per video. Dolby Vision off (Picture tab and Settings → Player → Picture) plays the HDR10/HLG base layer. It is shown only for Dolby Vision streams that have a base layer, on AetherEngine and mpv. AVPlayer always shows Dolby Vision.

HDR brightness (same places; off by default) asks Core Animation for the display's whole HDR range (`preferredDynamicRange = .high`) on AVPlayer, AetherEngine and mpv. AVPlayer and AetherEngine show a switch. mpv also lifts HDR mid-tones with `gamma` (0 to +30), so it shows a slider; dragging applies live and saves on release. Settings uses a switch, where on means 100%.

## Subtitles and controls

Settings → Player: language, Always / Forced only / Off, prefer SDH. Embedded tracks win over files. A file picked first gives way to an embedded track that appears later. Forced-only follows the audio language when no subtitle language is set. Sources are the stream, addons (re-queried when the stream's hash and file name change), local SRT, VTT, ASS/SSA and SUP, and OpenSubtitles.com with the user's own key. A VobSub file on AVPlayer, or "Show Full Styling" for a styled ASS file, switches to the fallback engine at the same position.

Settings → Player → Controls, on both platforms: skip distance (transport buttons, double tap or double click on the side thirds, Mac arrow keys, lock screen and Control Center), whether a double tap skips at all, how long controls stay while playing, and the speed a video starts at. The coordinator keeps that speed for each engine it makes.

The options bar opens one glass panel (side on a wide screen, bottom on a tall one) with Subtitles, Audio, Picture, Speed and Chapters. Choosing a track or a chapter closes it. A tap outside or Escape closes it too.

## Buffering

Startup hold is `StartCushion.standard`: 5 seconds of media, or 2 seconds when fill since the hold began is at least 2.5× playback. The hold waits at most 8 seconds, and 50 seconds including loading. The coordinator keeps its own startup timeout and retry. mpv reads ahead 120 seconds, with a 2 GiB demuxer cache ceiling and 64 MiB back cache; after starvation it waits for 10 seconds before resuming. Those limits are ceilings. AVPlayer keeps the system's buffering. Fully downloaded remaining media and a buffer that cannot be measured start without a hold.

`PlaybackState.preparation` is the engine's stages. The selected card follows the candidate the coordinator moves to. Its buffer bar is buffered seconds over the startup target, never over the duration. Cancelling a selection clears the card and lets a muted preload finish. Leaving the picker or backgrounding the app cancels pending selection and preload work. Card errors never include engine messages, stream URLs, credentials or headers.

AetherEngine prewarms the first stream when the player is created (`AetherEngine.prewarm`, 4 MB). `AetherSession.load` waits up to 4 seconds for a finished warm. AVPlayer and mpv are not warmed. Waiting on that prewarm is cancellable.

## Downloaded playback

Library → Downloads plays the local file through the same engines, without converting the container. The session stores a download UUID; watch progress keeps the movie or episode identity. Saved subtitle files and embedded tracks work offline. The offline player does not list addons or subtitles, call OpenSubtitles, preload streams, or offer online episode selection. A missing file fails locally.
