import Foundation
import Testing
import StremioKit
import StremioKitTestSupport
@testable import Features

@MainActor
@Suite struct StreamPickerViewModelTests {
    private let request = StreamRequest(type: "movie", id: "tt1", title: "Test Movie")

    /// Addon `stubN` answers with `bodies[N]` after `delays[N]`.
    private func services(bodies: [String], delays: [Duration] = [], failing: Set<Int> = [], sniffer: [String: MediaContainer] = [:],
                          settings: PlaybackSettings = PlaybackSettings(), fallbackLinked: Bool = false) async throws -> AppServices {
        let transport = StubTransport { request, _ in
            let index = Int(request.url?.host?.dropFirst(4).prefix(while: \.isNumber) ?? "0") ?? 0
            if index < delays.count { try await Task.sleep(for: delays[index]) }
            if failing.contains(index) { return StubTransport.response(Data(), status: 500, for: request) }
            return StubTransport.response(Data(bodies[index].utf8), for: request)
        }
        let (registry, client) = try await makeStubbedRegistry(manifests: bodies.indices.map { streamManifest("addon\($0)") }, transport: transport)
        return AppServices(registry: registry, client: client,
                           streams: StreamService(registry: registry, client: client, sniffer: StubSniffer(sniffer)),
                           settings: InMemorySettingsStore(settings), fallbackEngineLinked: fallbackLinked)
    }

    private func body(_ streams: [String]) -> String { #"{"streams":[\#(streams.joined(separator: ","))]}"# }
    private func direct(_ name: String, _ url: String, _ description: String = "") -> String {
        #"{"name":"\#(name)","description":"\#(description)","url":"\#(url)"}"#
    }

    @Test func loadsGroupsAndRanksAcrossAddons() async throws {
        let services = try await services(bodies: [
            body([direct("A 720", "https://a.example.com/1.mp4", "720p"), direct("A 1080", "https://a.example.com/2.mp4", "1080p")]),
            body([direct("B 2160 mkv", "https://b.example.com/1.mkv", "2160p"), direct("B 1080", "https://b.example.com/3.mp4", "1080p")]),
        ])
        let model = StreamPickerViewModel(request: request, services: services)
        #expect(model.isLoading)
        await model.load()
        #expect(!model.isLoading)
        #expect(model.listing.groups.map(\.addon.name) == ["addon0", "addon1"])
        #expect(model.listing.groups[0].streams.map(\.title) == ["A 1080", "A 720"])
        #expect(model.listing.items.map(\.title) == ["A 1080", "B 1080", "A 720", "B 2160 mkv"])
        #expect(model.listing.items.last?.route == .unsupported(.matroska), "no fallback engine linked yet")
    }

    @Test func resultsAppearBeforeTheSlowestAddonAnswers() async throws {
        let services = try await services(bodies: [body([direct("slow", "https://a.example.com/1.mp4")]), body([direct("fast", "https://b.example.com/1.mp4")])],
                                          delays: [.milliseconds(400), .milliseconds(0)])
        let model = StreamPickerViewModel(request: request, services: services)
        let loading = Task { await model.load() }
        try await waitUntil { !model.listing.isEmpty }
        #expect(model.listing.items.map(\.title) == ["fast"])
        #expect(model.listing.isLoading, "the slow addon is still pending")
        #expect(model.isLoading)
        await loading.value
        #expect(Set(model.listing.items.map(\.title)) == ["fast", "slow"])
        #expect(!model.isLoading)
    }

    @Test func ambiguousURLsAreSniffedInTheBackground() async throws {
        let services = try await services(bodies: [body([direct("blob", "https://a.example.com/blob", "1080p")])], sniffer: ["blob": .matroska])
        let model = StreamPickerViewModel(request: request, services: services)
        await model.load()
        #expect(model.listing.items.first?.container == .matroska)
        #expect(model.listing.items.first?.route == .unsupported(.matroska))
    }

    @Test func aFailingAddonBecomesAFailureEntry() async throws {
        let services = try await services(bodies: [body([]), body([direct("ok", "https://b.example.com/1.mp4")])], failing: [0])
        let model = StreamPickerViewModel(request: request, services: services)
        await model.load()
        #expect(model.listing.failures.map(\.error) == [.http(status: 500)])
        #expect(model.listing.items.count == 1)
        #expect(!model.showsNothingFound)
    }

    @Test func emptyAnswersMeanNothingFoundNotNobodyCanAnswer() async throws {
        let services = try await services(bodies: [body([])])
        let model = StreamPickerViewModel(request: request, services: services)
        await model.load()
        #expect(model.showsNothingFound)
        #expect(!model.nobodyCanAnswer)
    }

    @Test func noInstalledStreamAddonMeansNobodyCanAnswer() async throws {
        let client = makeClient(StubTransport(data: Data()))
        let registry = AddonRegistry(store: InMemoryAddonStore(), secrets: InMemorySecretStore(), client: client)
        let model = StreamPickerViewModel(request: request, services: AppServices(registry: registry, client: client))
        await model.load()
        #expect(model.nobodyCanAnswer)
        #expect(!model.showsNothingFound)
        #expect(!model.isLoading)
    }

    // MARK: choosing

    @Test func choosingAPlayableStreamBuildsAPlanWithAlternativesInRankOrder() async throws {
        let services = try await services(bodies: [body([direct("720", "https://a.example.com/1.mp4", "720p"), direct("1080", "https://a.example.com/2.mp4", "1080p"),
                                                         direct("mkv", "https://a.example.com/3.mkv", "2160p")])])
        let model = StreamPickerViewModel(request: request, services: services)
        await model.load()
        let chosen = try #require(model.listing.items.first { $0.title == "720" })
        guard case .play(let plan)? = model.choose(chosen) else { Issue.record("expected a plan"); return }
        #expect(plan.request == request)
        #expect(plan.candidates.map(\.title) == ["720", "1080"], "the choice first, then the other playable streams; the unsupported one is not offered")
        #expect(plan.candidates.allSatisfy { $0.route.isPlayable })
        guard case .play(let best)? = model.playBest() else { Issue.record("expected a plan"); return }
        #expect(best.candidates.first?.title == "1080")
    }

    @Test func unsupportedStreamsOfferTheNextPlayableOne() async throws {
        let services = try await services(bodies: [body([direct("mkv", "https://a.example.com/1.mkv", "2160p"), direct("mp4", "https://a.example.com/2.mp4", "1080p")])])
        let model = StreamPickerViewModel(request: request, services: services)
        await model.load()
        let unsupported = try #require(model.listing.items.first { $0.title == "mkv" })
        guard case .unsupported(let next)? = model.choose(unsupported) else { Issue.record("expected unsupported"); return }
        #expect(next?.title == "mp4")
    }

    @Test func withTheFallbackEngineLinkedMKVIsPlayable() async throws {
        let services = try await services(bodies: [body([direct("mkv", "https://a.example.com/1.mkv", "2160p")])], fallbackLinked: true)
        let model = StreamPickerViewModel(request: request, services: services)
        await model.load()
        guard case .play(let plan)? = model.choose(model.listing.items[0]) else { Issue.record("expected a plan"); return }
        #expect(plan.candidates.first?.route == .fallback(URL(string: "https://a.example.com/1.mkv")!, .container(.matroska)))
    }

    @Test func settingsCanDisableTheFallbackEngine() async throws {
        let services = try await services(bodies: [body([direct("mkv", "https://a.example.com/1.mkv")])], settings: PlaybackSettings(fallbackEngineEnabled: false), fallbackLinked: true)
        let model = StreamPickerViewModel(request: request, services: services)
        await model.load()
        #expect(model.listing.items.first?.route == .unsupported(.matroska))
    }

    @Test func externalLinksOpenOutsideTheApp() async throws {
        let services = try await services(bodies: [body([#"{"name":"YT","ytId":"abc123"}"#, #"{"name":"Site","externalUrl":"https://example.com/w"}"#])])
        let model = StreamPickerViewModel(request: request, services: services)
        await model.load()
        let urls: [URL] = model.listing.items.compactMap(model.choose).compactMap { choice in
            if case .openExternal(let url) = choice { return url }
            return nil
        }
        #expect(Set(urls) == [URL(string: "https://www.youtube.com/watch?v=abc123")!, URL(string: "https://example.com/w")!])
    }

    @Test func torrentsShowUpOnceAStreamingServerIsConfigured() async throws {
        let torrent = #"{"name":"T","infoHash":"0123456789abcdef0123456789abcdef01234567","fileIdx":2}"#
        let without = try await services(bodies: [body([torrent])])
        let hidden = StreamPickerViewModel(request: request, services: without)
        await hidden.load()
        #expect(hidden.listing.items.isEmpty && hidden.listing.hidden.first?.reason == .needsStreamingServer)
        #expect(hidden.showsNothingFound)

        let with = try await services(bodies: [body([torrent])], settings: PlaybackSettings(streamingServerURL: "http://192.168.1.9:11470"))
        let shown = StreamPickerViewModel(request: request, services: with)
        await shown.load()
        #expect(shown.listing.best?.route.playableURL?.absoluteString == "http://192.168.1.9:11470/0123456789abcdef0123456789abcdef01234567/2")
    }

    @Test func preferredResolutionFromSettingsReRanks() async throws {
        let streams = [direct("uhd", "https://a.example.com/1.mp4", "2160p"), direct("hd", "https://a.example.com/2.mp4", "720p")]
        let services = try await services(bodies: [body(streams)], settings: PlaybackSettings(preferredResolution: 720))
        let model = StreamPickerViewModel(request: request, services: services)
        await model.load()
        #expect(model.listing.items.map(\.title) == ["hd", "uhd"])
    }

    @Test func bingeGroupContinuityPicksTheMatchingStream() async throws {
        let withGroup = { (name: String, url: String, group: String) in #"{"name":"\#(name)","url":"\#(url)","behaviorHints":{"bingeGroup":"\#(group)"}}"# }
        let services = try await services(bodies: [body([withGroup("other", "https://a.example.com/1.mp4", "g-other"), withGroup("match", "https://a.example.com/2.mp4", "g-1080")])])
        let model = StreamPickerViewModel(request: request, services: services)
        await model.load()
        guard case .play(let plan)? = model.bingeChoice(continuing: BingeContext(bingeGroup: "g-1080")) else { Issue.record("expected a plan"); return }
        #expect(plan.candidates.first?.title == "match")
        #expect(plan.candidates.first?.bingeContext?.bingeGroup == "g-1080")
        #expect(model.bingeChoice(continuing: BingeContext(bingeGroup: "nope")) == nil)
        #expect(model.bingeChoice(continuing: nil) == nil)
    }

    @Test func candidatesCarryHeadersSubtitlesAndHashes() async throws {
        let stream = #"{"name":"P","url":"https://a.example.com/p.mp4","subtitles":[{"id":"s","url":"https://a.example.com/s.srt","lang":"eng"}],"behaviorHints":{"proxyHeaders":{"request":{"Referer":"https://r.example.com"}},"videoHash":"abc","videoSize":12345,"filename":"p.mp4"}}"#
        let services = try await services(bodies: [body([stream])])
        let model = StreamPickerViewModel(request: request, services: services)
        await model.load()
        guard case .play(let plan)? = model.playBest() else { Issue.record("expected a plan"); return }
        let candidate = try #require(plan.candidates.first)
        #expect(candidate.headers == ["Referer": "https://r.example.com"])
        #expect(candidate.subtitles.map(\.lang) == ["eng"])
        #expect(candidate.videoHash == "abc" && candidate.videoSize == 12345 && candidate.filename == "p.mp4")
        #expect(candidate.addonName == "addon0")
    }

    @Test func retryReloads() async throws {
        let services = try await services(bodies: [body([direct("x", "https://a.example.com/1.mp4")])])
        let model = StreamPickerViewModel(request: request, services: services)
        await model.load()
        await model.retry()
        #expect(model.listing.items.count == 1)
    }
}
