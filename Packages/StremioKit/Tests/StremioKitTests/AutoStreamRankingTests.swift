import Foundation
import Testing
@testable import StremioKit
import StremioKitTestSupport

@Suite struct AutoStreamRankingTests {
    /// Two hours: the runtime that size is read against when a release states no bitrate.
    private let runtime: TimeInterval = 7_200

    private func release(_ id: String, _ text: String) -> RankedStream {
        let stream = S.direct(text, "https://e.example.com/\(id).mkv")
        return RankedStream(id: id, stream: stream, addon: S.addon("A"), alsoProvidedBy: [], quality: StreamQuality.parse(stream),
                            container: nil, route: .native(URL(string: "https://e.example.com/\(id).mkv")!), addonIndex: 0, indexInAddon: 0)
    }

    private func score(_ text: String) -> Double {
        AutoStreamRanking.assess(release("score", text), duration: runtime).qualityScore
    }

    private func best(_ items: [RankedStream], duration: TimeInterval?) -> String? {
        AutoStreamRanking.best(from: items, duration: duration)?.item.id
    }

    @Test func aBluRayWithDTSHDBeatsAREMUXWithAACAtTheSameResolution() {
        // The reported case: 44.66 GB against 29.71 GB, both 2160p. The lossless track outweighs the REMUX tag.
        let bluRay = release("bluray", "Movie.2160p.BluRay.x265.HDR.DTS-HD.MA.5.1-GRP 44.66 GB")
        let remux = release("remux", "Movie.2160p.REMUX.HEVC.AAC-GRP 29.71 GB")
        #expect(best([remux, bluRay], duration: runtime) == "bluray")
        #expect(best([bluRay, remux], duration: runtime) == "bluray", "list order does not decide it")
    }

    @Test func aClearlySuperiorSourceOutranksAREMUX() {
        let uhd = release("uhd", "Movie.2160p.BluRay.x265.10bit.HDR.DTS-HD.MA.7.1-GRP 40 GB")
        let remux = release("remux", "Movie.1080p.REMUX.AAC-GRP 25 GB")
        #expect(best([remux, uhd], duration: runtime) == "uhd", "a 4K HDR disc beats a 1080p REMUX, whatever the tag")
    }

    @Test func aREMUXOnlyBreaksATieWithAnEquallyGoodRelease() {
        let bluRay = release("bluray", "Movie.2160p.BluRay.x265.HDR.DTS-HD.MA.5.1-GRP 30 GB")
        let remux = release("remux", "Movie.2160p.REMUX.x265.HDR.DTS-HD.MA.5.1-GRP 30 GB")
        #expect(best([bluRay, remux], duration: runtime) == "remux")
        let nudge = AutoStreamRanking.assess(remux, duration: runtime).qualityScore - AutoStreamRanking.assess(bluRay, duration: runtime).qualityScore
        #expect(abs(nudge - 4) < 0.000_001, "the REMUX tag is worth a small, fixed indicator")
    }

    @Test func losslessAudioBeatsLossyAtTheSameVideo() {
        let flac = release("flac", "Movie.1080p.BluRay.x264.FLAC 15 GB")
        let aac = release("aac", "Movie.1080p.BluRay.x264.AAC 15 GB")
        #expect(best([aac, flac], duration: runtime) == "flac")
    }

    @Test func aFileGainsNothingOnceItsBitrateIsFarAboveTheReference() {
        // Size counts relative to runtime, and the gain stops at a cap: 60 GB and 120 GB over two hours are both far above a 1080p reference.
        #expect(score("Movie.1080p.WEB-DL.x264 60 GB") == score("Movie.1080p.WEB-DL.x264 120 GB"))
        #expect(score("Movie.1080p.WEB-DL.x264 20 GB") > score("Movie.1080p.WEB-DL.x264 2 GB"), "a starved encode still loses")
    }

    @Test func missingMetadataScoresNeutrallyAndNeverBreaksTheRanking() {
        let bare = release("bare", "Movie")
        let hd = release("hd", "Movie 720p")
        #expect(best([bare, hd], duration: nil) == "hd", "a known resolution beats no information")
        #expect(best([bare], duration: nil) == "bare", "a release with no facts is still a candidate")
        #expect(AutoStreamRanking.assess(bare, duration: nil).bitrateMbps == nil)
    }

    @Test func aResolutionTheTextContradictsEarnsNothing() {
        #expect(StreamQuality.parse(from: ["Movie 1080p 2160p WEB-DL"]).hasConflictingResolution)
        let both = release("both", "Movie 1080p 2160p WEB-DL")
        let one = release("one", "Movie 1080p WEB-DL")
        #expect(best([both, one], duration: runtime) == "one")
    }

    @Test func aSourceTheTextContradictsEarnsNothing() {
        // A REMUX that also names a WEB-DL is a contradiction: it scores as if it named neither source nor REMUX.
        #expect(StreamQuality.parse(from: ["Movie 2160p WEB-DL REMUX"]).hasConflictingSource)
        let contradicted = AutoStreamRanking.assess(release("contradicted", "Movie 2160p WEB-DL REMUX DTS-HD 40 GB"), duration: runtime)
        let plain = AutoStreamRanking.assess(release("plain", "Movie 2160p DTS-HD 40 GB"), duration: runtime)
        #expect(contradicted.qualityScore == plain.qualityScore)
    }

    @Test func aCodecTheTextContradictsIsNotTrusted() {
        // An x264 transcoded from HEVC names two codecs. Its codec is not ranked on, so its bitrate is read at H.264's rate, as an x264 is.
        #expect(StreamQuality.parse(from: ["Movie 1080p x264 HEVC 10 GB"]).hasConflictingVideoCodec)
        let mixed = AutoStreamRanking.assess(release("mixed", "Movie 1080p x264 HEVC 10 GB"), duration: runtime)
        let h264 = AutoStreamRanking.assess(release("h264", "Movie 1080p x264 10 GB"), duration: runtime)
        #expect(mixed.qualityScore == h264.qualityScore)
    }

    @Test func aBareSDDoesNotContradictA1080p() {
        // "SD" in a release name is common, and it sets the resolution only when nothing else does.
        let quality = StreamQuality.parse(from: ["Movie.1080p.BluRay.x264-SD"])
        #expect(!quality.hasConflictingResolution)
        #expect(quality.resolution == 1080)
        #expect(StreamQuality.parse(from: ["Movie SD"]).resolution == 480)
    }

    @Test func aDimensionThatContradictsTheHeightIsAConflict() {
        #expect(StreamQuality.parse(from: ["Movie 1920x1080 2160p WEB-DL"]).hasConflictingResolution)
        #expect(!StreamQuality.parse(from: ["Movie 1920x1080 WEB-DL"]).hasConflictingResolution)
    }

    @Test func aDeclaredBitrateThatContradictsTheSizeIsNotTrusted() {
        let contradicted = AutoStreamRanking.assess(release("c", "Movie 1080p 2 Mbps 40 GB"), duration: runtime)
        #expect(contradicted.bitrateMbps == nil, "2 Mbps against 40 GB over two hours is not one release")
        let agreeing = AutoStreamRanking.assess(release("a", "Movie 1080p 40 Mbps 40 GB"), duration: runtime)
        #expect(agreeing.bitrateMbps == 40, "a stated rate near the size over runtime is used as stated")
    }

    @Test func anAtmosLabelBesideAACEarnsNoAtmosCredit() {
        #expect(score("Movie 1080p AAC Atmos") == score("Movie 1080p AAC"))
        #expect(score("Movie 1080p TrueHD Atmos") > score("Movie 1080p TrueHD"), "Atmos with a codec that carries it counts")
    }

    @Test func aDeadTorrentLosesToAnAvailableOne() {
        let dead = release("dead", "Movie 2160p BluRay 👤 0")
        let alive = release("alive", "Movie 1080p BluRay 👤 40")
        #expect(best([dead, alive], duration: runtime) == "alive")
    }

    @Test func partsOfTheTextAreReadOncePerRelease() {
        #expect(StreamQuality.parse(from: ["2160p x265 10bit"]).bitDepth == 10)
        #expect(StreamQuality.parse(from: ["Hi10P 1080p"]).bitDepth == 10)
        #expect(StreamQuality.parse(from: ["DTS-HD.MA.7.1 DDP5.1"]).audioChannels == 8, "the most channels named")
        #expect(StreamQuality.parse(from: ["DDP5.1"]).audioChannels == 6)
        #expect(StreamQuality.parse(from: ["Movie 5.1 GB"]).audioChannels == nil, "a size is not a channel layout")
        #expect(StreamQuality.parse(from: ["Movie 12.5 Mbps"]).declaredBitrateMbps == 12.5)
        #expect(StreamQuality.parse(from: ["2160p REMUX"]).isRemux)
        #expect(!StreamQuality.parse(from: ["2160p WEB-DL"]).isRemux)
    }

    @Test func seedersReadInTheWordedForms() {
        #expect(StreamQuality.parse(from: ["Movie 1080p 12 seeders"]).seeders == 12)
        #expect(StreamQuality.parse(from: ["Movie 1080p seeders: 7"]).seeders == 7)
        #expect(StreamQuality.parse(from: ["Movie 1080p 🌱 9"]).seeders == 9)
        #expect(StreamQuality.parse(from: ["Movie 1080p 12 seeders 44.66 GB"]).seeders == 12, "the size's number is not the seeder count")
        #expect(StreamQuality.parse(from: ["Movie 1080p seeders 12 44.66 GB"]).seeders == 12)
    }
}
