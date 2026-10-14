#if canImport(JavaScriptCore)
import Foundation
import JavaScriptCore
import Testing

/// The script that says a reviews page is ready (`ReviewPageRules.paintedScript`), run in JavaScriptCore against a stand-in page with a
/// clock the test moves. It is read from the Swift source, as the WebKit build is not compiled on the host.
@Suite struct ReviewReadyScriptTests {
    private static func paintedScript() throws -> String {
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Features/Views/Detail/DetailReviewsPanel.swift")
        let text = try String(contentsOf: source, encoding: .utf8)
        let start = try #require(text.range(of: "static let paintedScript = #\"\"\"\n"))
        let end = try #require(text.range(of: "\"\"\"#", range: start.upperBound..<text.endIndex))
        return String(text[start.upperBound..<end.lowerBound])
    }

    /// A page with a clock: `cards` review cards (IMDb's, each with a date), a "User reviews" heading that is hidden as IMDb's is by the
    /// content rules, and `readyState`. `run(ms)` moves the clock in 10 ms steps, firing intervals and frames.
    private static let harness = #"""
    var now = 1000; Date.now = function () { return now; };
    var intervals = []; var frames = []; var posted = null; var drawsFrames = true;
    function setInterval(fn, ms) { intervals.push({ fn: fn, ms: ms, next: now + ms, repeats: true }); return intervals.length; }
    function setTimeout(fn, ms) { intervals.push({ fn: fn, ms: ms, next: now + ms, repeats: false }); return intervals.length; }
    function clearInterval(id) { if (id) intervals[id - 1] = null; }
    function requestAnimationFrame(fn) { frames.push(fn); }
    var window = { innerHeight: 800, scrollY: 0, webkit: { messageHandlers: { painted: { postMessage: function (m) { posted = m; } } } } };
    var page = { cards: 0, readyState: 'interactive' };
    var location = { hostname: 'm.imdb.com' };
    function element(text, laidOut) {
      return { textContent: text, nextElementSibling: null, parentElement: null,
               getClientRects: function () { return laidOut ? [1] : []; },
               getBoundingClientRect: function () { return { top: 40, height: laidOut ? 180 : 0 }; },
               closest: function () { return null; } };
    }
    var hiddenHeading = element('User reviews', false);
    var document = {
      get readyState() { return page.readyState; },
      querySelector: function (selector) {
        if (selector !== '.review-date' || page.cards === 0) return null;
        var card = element('Shinra788 · Jun 6, 2005 · The Batman film I have been waiting for, and it was worth every minute of it.', true);
        var date = element('Jun 6, 2005', true);
        date.closest = function () { return card; };
        return date;
      },
      querySelectorAll: function () { return [hiddenHeading]; }
    };
    function run(ms) {
      var end = now + ms;
      while (now < end) {
        now += 10;
        for (var i = 0; i < intervals.length; i++) {
          var t = intervals[i];
          if (t && now >= t.next) { if (t.repeats) { t.next += t.ms; } else { intervals[i] = null; } t.fn(); }
        }
        if (drawsFrames && now % 20 === 0) { var due = frames; frames = []; for (var j = 0; j < due.length; j++) due[j](); }
      }
    }
    """#

    private func page(cards: Int, readyState: String = "interactive", host: String = "m.imdb.com") throws -> JSContext {
        let context = try #require(JSContext())
        context.evaluateScript(Self.harness)
        context.evaluateScript("page.cards = \(cards); page.readyState = '\(readyState)'; location.hostname = '\(host)';")
        context.evaluateScript(try Self.paintedScript())
        return context
    }

    private func posted(_ context: JSContext) -> (reason: String, readyMs: Int)? {
        guard let value = context.evaluateScript("posted"), !value.isNull, !value.isUndefined else { return nil }
        return (value.forProperty("reason").toString(), Int(value.forProperty("readyMs").toInt32()))
    }

    /// IMDb's header holds its "User reviews" heading and is hidden, so the heading is never seen. The page used to wait out six seconds
    /// every time; it is ready once its first review card is laid out and two frames are drawn.
    @Test func imdbIsReadyOnItsFirstReviewCardDespiteItsHiddenHeading() throws {
        let context = try page(cards: 1)
        context.evaluateScript("run(200)")
        let ready = try #require(posted(context))
        #expect(ready.reason == "card")
        #expect(ready.readyMs < 100, "within a few frames, not the six-second limit")
    }

    @Test func aPageThatDrawsNoFramesStillOpens() throws {
        let context = try page(cards: 1)
        context.evaluateScript("drawsFrames = false; run(400)")
        let ready = try #require(posted(context))
        #expect(ready.reason == "card")
        #expect(ready.readyMs >= 250 && ready.readyMs < 300)
    }

    @Test func anotherSiteIsNotReadyOnACardThatLooksLikeIMDbs() throws {
        let context = try page(cards: 1, host: "www.rottentomatoes.com")
        context.evaluateScript("run(1000)")
        #expect(posted(context) == nil, "it waits for its own heading")
    }

    @Test func aCardThatArrivesLaterIsReadyWhenItArrives() throws {
        let context = try page(cards: 0)
        context.evaluateScript("run(700)")
        #expect(posted(context) == nil)
        context.evaluateScript("page.cards = 1; run(200)")
        let ready = try #require(posted(context))
        #expect(ready.reason == "card")
        #expect(ready.readyMs >= 700 && ready.readyMs < 900)
    }

    @Test func aLoadedPageWithNothingToWaitForOpensAfterTwoAndAHalfSeconds() throws {
        let context = try page(cards: 0, readyState: "complete")
        context.evaluateScript("run(2400)")
        #expect(posted(context) == nil)
        context.evaluateScript("run(200)")
        let ready = try #require(posted(context))
        #expect(ready.reason == "no-heading")
        #expect(ready.readyMs >= 2500 && ready.readyMs < 2600)
    }

    @Test func aPageStillLoadingWaitsUpToSixSeconds() throws {
        let context = try page(cards: 0, readyState: "interactive")
        context.evaluateScript("run(5900)")
        #expect(posted(context) == nil)
        context.evaluateScript("run(200)")
        #expect(posted(context)?.reason == "no-heading")
    }
}
#endif
