import Testing
import UIKit
@testable import Features

@MainActor
@Suite struct FontAvailabilityTests {
    @Test func offeredFamiliesAreInstalled() {
        for face in AppearancePreferences.FontStyle.allCases {
            guard let family = face.familyName else { continue }
            let names = UIFont.fontNames(forFamilyName: family)
            #expect(!names.isEmpty || UIFont(name: family, size: 17) != nil, "Unavailable font: \(family)")
            #expect(AppearancePreferences.font(face: face, style: .body).familyName == family)
        }
    }
}
