#if canImport(UIKit)
import StremioKit
import Testing
@testable import Features

@Suite struct StreamProviderMarkTests {
    @Test func everyServiceHasALogoOrInitials() {
        for provider in StreamProvider.allCases {
            let hasLogo = provider.logoName?.isEmpty == false
            let hasInitials = provider.markText?.isEmpty == false
            #expect(hasLogo != hasInitials, "\(provider.name) needs exactly one of a logo or initials")
        }
    }

    @Test func logoNamesAreUnique() {
        let names = StreamProvider.allCases.compactMap(\.logoName)
        #expect(Set(names).count == names.count)
    }

    @Test func disneyHuluAndPeacockKeepInitialsUntilTheirLogosArrive() {
        #expect(StreamProvider.disneyPlus.logoName == nil)
        #expect(StreamProvider.hulu.logoName == nil)
        #expect(StreamProvider.peacock.logoName == nil)
    }
}
#endif
