# Auto Pick and Best Match

Auto Pick, Play Best, Best Match, retries, "Try the next stream", episode switching and downloads share `AutoStreamRanking` and the same candidate pool. Native, fallback-engine and configured external-player routes compete. Unsupported routes and HTTP links marked as downloading stay out. An uncached torrent is eligible only when routing already has a playable streaming-server URL.

Order: a release that plays now beats one that must download first; an explicit resolution preference then keeps the releases nearest that resolution; the weighted score decides. A source preference, and continuing a binge from the previous episode's addon, each add `preferenceBonus` (4). That is less than one resolution step (6), so they only break near-ties. Resuming a saved session keeps its own file and is not a quality comparison.

The score is additive and bounded. Size counts only as bitrate against runtime, with codec efficiency and a cap. Audio can outweigh a resolution step; native routes score only codecs AVPlayer can decode. Unknown cache state and unknown seeders are neutral. Zero seeders is a heavy penalty. Contradictory metadata drops the bonus it contradicts. Provider and release-group bonuses are small. Filename language is not quality.

Data Saver forces 1080p or the preferred quality when that is lower, penalises a REMUX, and caps lossless audio at Dolby Digital. Ultra goes to 720p or below and tighter bitrate and audio caps. Holding Play, an episode card or a Continue Watching card can force Highest Quality, Data Saver or Ultra Saver for that play. Both savers play a downloaded copy as it is, start at once, and skip the saved session's file. Stream Selector still shows the list.

Best Match, Play Best and Auto Pick agree on a finished list. While results are loading, the current best uses the same scorer and the Best Match badge waits. By default Auto Pick waits for every addon, subject to the client's timeouts. Fastest or a named addon waits `AddonSpeedChoice.settleWindow` (3 seconds) after that addon's first playable stream. A caller deadline can end the wait sooner.

`AutoStreamRanking.explain` is for the `auto-pick` debug log. Nothing from it is shown on screen. Weights live in `AutoStreamRanking`; change them there. The player stream chooser is one sheet on iPhone and Mac, independent of the controls' idle timeout.
