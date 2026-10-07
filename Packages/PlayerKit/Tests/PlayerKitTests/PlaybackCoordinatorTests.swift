import Foundation
import Testing
import StremioKit
import PlayerKitTestSupport
@testable import PlayerKit

@MainActor
@Suite struct PlaybackCoordinatorTests {
    private let request = StreamRequest(type: "movie", id: "tt1", title: "Movie")
    private let boom = PlaybackFailure(.network, "boom")

    private func candidate(_ name: String, route: Bool = true) -> PlaybackCandidate {
        let url = URL(string: "https://e.example.com/\(name).mp4")!
        return PlaybackCandidate(id: name, title: name, addonName: "A", route: route ? .native(url) : .external(url), headers: name == "protected" ? ["X-Token": "abc"] : [:])
    }

    private func plan(_ names: [String]) -> PlaybackPlan { PlaybackPlan(request: request, candidates: names.map { candidate($0) }) }

    /// Engines are created per candidate from `script`; the coordinator under test gets them through `makeEngine`.
    private final class Rig {
        var engines: [String: MockEngine] = [:]
        var script: [String: MockEngine.Outcome]
        init(_ script: [String: MockEngine.Outcome]) { self.script = script }
        @MainActor func make(_ candidate: PlaybackCandidate) -> (any PlaybackEngine)? {
            guard let outcome = script[candidate.id] else { return nil }
            let engine = MockEngine(outcome)
            engines[candidate.id] = engine
            return engine
        }
    }

    private func coordinator(_ names: [String], _ script: [String: MockEngine.Outcome], resume: TimeInterval = 0, timeout: Duration = .seconds(2),
                             progress: ProgressSession? = nil) -> (PlaybackCoordinator, Rig) {
        let rig = Rig(script)
        return (PlaybackCoordinator(plan: plan(names), resumeFrom: resume, startupTimeout: timeout, progress: progress, makeEngine: { rig.make($0) }), rig)
    }

    @Test func playsTheFirstCandidateWhenItWorks() async {
        let (coordinator, rig) = coordinator(["a", "b"], ["a": .plays(duration: 100), "b": .plays(duration: 100)])
        await coordinator.start()
        #expect(coordinator.phase == .playing)
        #expect(coordinator.current?.id == "a")
        #expect(coordinator.state.isPlaying)
        #expect(coordinator.failedAttempts.isEmpty && coordinator.notice == nil)
        #expect(rig.engines["b"] == nil, "later candidates are never created unless needed")
        #expect(rig.engines["a"]?.loadedItems.first?.url.lastPathComponent == "a.mp4")
        #expect(rig.engines["a"]?.playCalls == 1)
    }

    @Test func movesToTheNextCandidateWhenOneFailsToLoad() async {
        let (coordinator, rig) = coordinator(["a", "b", "c"], ["a": .failsToLoad(boom), "b": .plays(duration: 50), "c": .plays(duration: 50)])
        await coordinator.start()
        #expect(coordinator.phase == .playing)
        #expect(coordinator.current?.id == "b")
        #expect(coordinator.candidateIndex == 1)
        #expect(coordinator.failedAttempts.map(\.id) == ["a"])
        #expect(coordinator.failedAttempts.first?.failure == boom)
        #expect(coordinator.notice?.contains("“a” didn't work") == true && coordinator.notice?.contains("“b”") == true)
        #expect(rig.engines["a"]?.isStopped == true, "the failed engine is released")
        #expect(rig.engines["c"] == nil)
    }

    @Test func aStreamThatNeverStartsTimesOut() async {
        let (coordinator, _) = coordinator(["a", "b"], ["a": .hangs, "b": .plays(duration: 50)], timeout: .milliseconds(60))
        await coordinator.start()
        #expect(coordinator.phase == .playing && coordinator.current?.id == "b")
        #expect(coordinator.failedAttempts.map(\.failure.kind) == [.timeout])
    }

    @Test func candidatesWithoutAnEngineAreSkipped() async {
        let (coordinator, _) = coordinator(["a", "b"], ["b": .plays(duration: 10)])   // no script entry for "a" => makeEngine returns nil
        await coordinator.start()
        #expect(coordinator.current?.id == "b")
        #expect(coordinator.failedAttempts.map(\.failure.kind) == [.noEngine])
    }

    @Test func everyCandidateFailingEndsExhausted() async {
        let (coordinator, _) = coordinator(["a", "b"], ["a": .failsToLoad(boom), "b": .hangs], timeout: .milliseconds(40))
        await coordinator.start()
        #expect(coordinator.phase == .exhausted)
        #expect(coordinator.failedAttempts.map(\.id) == ["a", "b"])
        #expect(coordinator.notice == "None of the streams could be played.")
    }

    @Test func anEmptyPlanSaysSo() async {
        let (coordinator, _) = coordinator([], [:])
        await coordinator.start()
        #expect(coordinator.phase == .exhausted)
        #expect(coordinator.notice == "There is nothing to play.")
    }

    @Test func resumePositionReachesTheEngineAndSurvivesFailover() async {
        let (coordinator, rig) = coordinator(["a", "b"], ["a": .failsToLoad(boom), "b": .plays(duration: 100)], resume: 42)
        await coordinator.start()
        #expect(rig.engines["a"]?.loadedItems.first?.startPosition == 42)
        #expect(rig.engines["b"]?.loadedItems.first?.startPosition == 42)
    }

    @Test func headersTravelWithTheItem() async {
        let (coordinator, rig) = coordinator(["protected"], ["protected": .plays(duration: 10)])
        await coordinator.start()
        #expect(rig.engines["protected"]?.loadedItems.first?.headers == ["X-Token": "abc"])
    }

    @Test func aMidStreamFailureContinuesOnTheNextStreamFromTheSamePosition() async throws {
        let (coordinator, rig) = coordinator(["a", "b"], ["a": .plays(duration: 100), "b": .plays(duration: 100)])
        await coordinator.start()
        rig.engines["a"]?.simulate(position: 37)
        try await waitUntil { coordinator.state.position == 37 }
        rig.engines["a"]?.simulateFailure(PlaybackFailure(.network, "connection lost"))
        try await waitUntil { coordinator.current?.id == "b" && coordinator.phase == .playing }
        #expect(rig.engines["b"]?.loadedItems.first?.startPosition == 37)
        #expect(coordinator.failedAttempts.map(\.id) == ["a"])
    }

    @Test func aMidStreamFailureOnTheLastStreamIsFinal() async throws {
        let (coordinator, rig) = coordinator(["a"], ["a": .plays(duration: 100)])
        await coordinator.start()
        rig.engines["a"]?.simulateFailure(boom)
        try await waitUntil { coordinator.phase == .exhausted }
        #expect(coordinator.state.failure == boom)
    }

    @Test func manualNextStreamResumesAtTheCurrentPosition() async throws {
        let (coordinator, rig) = coordinator(["a", "b"], ["a": .plays(duration: 100), "b": .plays(duration: 100)])
        await coordinator.start()
        rig.engines["a"]?.simulate(position: 12)
        try await waitUntil { coordinator.state.position == 12 }
        await coordinator.advance()
        #expect(coordinator.current?.id == "b" && coordinator.phase == .playing)
        #expect(rig.engines["b"]?.loadedItems.first?.startPosition == 12)
        await coordinator.advance()
        #expect(coordinator.current?.id == "b" && coordinator.phase == .playing, "no further stream: keep playing")
        #expect(coordinator.notice == "There are no other streams to try.")
    }

    @Test func transportCommandsReachTheEngine() async throws {
        let (coordinator, rig) = coordinator(["a"], ["a": .plays(duration: 100)])
        await coordinator.start()
        let engine = try #require(rig.engines["a"])
        coordinator.pause()
        try await waitUntil { coordinator.state.status == .paused }
        coordinator.togglePlayPause()
        try await waitUntil { coordinator.state.isPlaying }
        await coordinator.seek(to: 30)
        await coordinator.seek(to: -5)
        #expect(engine.seeks == [30, 0], "negative seeks clamp to zero")
        engine.simulate(position: 50)
        try await waitUntil { coordinator.state.position == 50 }
        await coordinator.skip(by: 10)
        await coordinator.skip(by: -100)
        await coordinator.skip(by: 1000)
        #expect(engine.seeks.suffix(3) == [60, 0, 99], "skips stay inside the media")
        coordinator.setRate(1.5)
        coordinator.selectAudioTrack(id: "a2")
        coordinator.selectEmbeddedSubtitleTrack(id: "s1")
        #expect(engine.rates == [1.5] && engine.selectedAudio == ["a2"] && engine.selectedEmbeddedSubtitles == ["s1"])
    }

    @Test func tracksAreVisibleThroughTheCoordinatorState() async throws {
        let (coordinator, rig) = coordinator(["a"], ["a": .plays(duration: 100)])
        await coordinator.start()
        rig.engines["a"]?.simulate(tracks: [MediaTrack(id: "a1", title: "English", language: "eng", isDefault: true)], subtitles: [MediaTrack(id: "s1", title: "French", language: "fre")])
        try await waitUntil { !coordinator.state.audioTracks.isEmpty }
        #expect(coordinator.state.audioTracks.first?.language == "eng")
        #expect(coordinator.state.embeddedSubtitleTracks.map(\.id) == ["s1"])
    }

    @Test func reachingTheEndFinishesAndNotifies() async throws {
        let (coordinator, rig) = coordinator(["a"], ["a": .plays(duration: 100)])
        var ended = false
        coordinator.onEnded = { ended = true }
        await coordinator.start()
        rig.engines["a"]?.simulate(position: 100)
        rig.engines["a"]?.simulateEnd()
        try await waitUntil { ended }
        #expect(coordinator.phase == .finished)
    }

    @Test func stoppingReleasesTheEngineAndFinishes() async {
        let (coordinator, rig) = coordinator(["a"], ["a": .plays(duration: 100)])
        await coordinator.start()
        await coordinator.stop()
        #expect(rig.engines["a"]?.isStopped == true)
        #expect(coordinator.phase == .finished)
        await coordinator.start()   // restarting a stopped coordinator does nothing
        #expect(coordinator.phase == .finished)
    }

    @Test func stoppingDuringStartupDoesNotStartLaterCandidates() async throws {
        let (coordinator, rig) = coordinator(["a", "b"], ["a": .hangs, "b": .plays(duration: 10)], timeout: .seconds(5))
        let starting = Task { await coordinator.start() }
        try await Task.sleep(for: .milliseconds(50))
        await coordinator.stop()
        await starting.value
        #expect(rig.engines["b"] == nil)
        #expect(coordinator.phase == .finished)
    }

    @Test func progressIsRecordedWhilePlayingAndFlushedOnStop() async throws {
        let store = InMemoryProgressStore()
        let clock = ClockBox(Date(timeIntervalSince1970: 5_000))
        let session = ProgressSession(request: request, previous: nil, store: store, clock: { clock.now })
        let (coordinator, rig) = coordinator(["a"], ["a": .plays(duration: 200)], progress: session)
        await coordinator.start()
        rig.engines["a"]?.simulate(position: 20)
        try await waitUntil { coordinator.state.position == 20 }
        clock.now = clock.now.addingTimeInterval(12)
        rig.engines["a"]?.simulate(position: 33)
        try await waitUntil { coordinator.state.position == 33 }
        await coordinator.stop()
        let saved = await store.progress(for: "movie/tt1")
        #expect(saved?.position == 33 && saved?.duration == 200)
        #expect(saved?.isWatched == false)
    }
}

/// Polls `condition` on the main actor until it holds or the timeout passes.
@MainActor
func waitUntil(timeout: TimeInterval = 5, _ condition: @MainActor () -> Bool) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() {
        if Date() > deadline { throw WaitTimeout() }
        try await Task.sleep(for: .milliseconds(10))
    }
}

struct WaitTimeout: Error {}
