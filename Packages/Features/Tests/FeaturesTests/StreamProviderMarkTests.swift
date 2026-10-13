#if canImport(UIKit)
import StremioKit
import Testing
@testable import Features

@Suite struct StreamProviderMarkTests {
    @Test func everyServiceButAppleHasInitialsForItsMark() {
        for provider in StreamProvider.allCases where provider != .appleTV {
            #expect(provider.markText?.isEmpty == false, "\(provider.name) needs initials on its mark")
        }
        #expect(StreamProvider.appleTV.markText == nil, "Apple TV+ draws Apple's logo instead of initials")
    }
}
#endif
