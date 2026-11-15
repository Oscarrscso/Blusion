#if canImport(UIKit)
import SwiftUI
import StremioKit
import UIKit

// MARK: - Summaries

/// What each part of Appearance is set to, for its row on the Appearance page.
extension AppearancePreferences {
    var colourSummary: String {
        var parts = [accent.label, background.label]
        if playStyle != .artwork { parts.append("\(playStyle.label) Play") }
        if buttonFinish != .glass { parts.append("\(buttonFinish.label) buttons") }
        return parts.joined(separator: " · ")
    }

    var textSummary: String {
        var parts = [textSize == .system ? "System size" : textSize.label, font.label]
        if reading.weight != .regular { parts.append(reading.weight.label) }
        if font == .standard, fontWidth != .standard { parts.append(fontWidth.label) }
        if italicText { parts.append("Italic") }
        if reading.capitals { parts.append("Caps") }
        if !interface.followsReading { parts.append("Custom interface") }
        if headings != TextStyle.headings() { parts.append("Custom headings") }
        return parts.joined(separator: " · ")
    }

    /// What a kind of text is set to, on its row of the Text page.
    func textRoleSummary(_ role: TextRole) -> String {
        if role == .interface, interface.followsReading, reading.colour == .primary, !reading.capitals {
            return "Same as body text"
        }
        let style = resolvedText(for: role)
        var parts = [style.font.label]
        if role != .reading, !style.followsTextSize { parts.append(style.textSize.label) }
        if style.scale != .standard { parts.append(style.scale.label) }
        if style.weight != .regular { parts.append(style.weight.label) }
        if style.font == .standard, style.width != .standard { parts.append(style.width.label) }
        if style.letterSpacing != .standard { parts.append("\(style.letterSpacing.label) letters") }
        if style.lineSpacing != .standard { parts.append("\(style.lineSpacing.label) lines") }
        if style.italic { parts.append("Italic") }
        if style.capitals { parts.append("Caps") }
        if style.colour != .primary { parts.append(style.colour.label) }
        return parts.joined(separator: " · ")
    }

    var cardsSummary: String {
        "Size \(percent(cardScale)) · Spacing \(percent(spacingScale))"
    }

    var homeSummary: String {
        heroAutoAdvance > 0 ? "Showcase every \(heroAutoAdvance) s" : "Showcase stays put"
    }

    var titlePagesSummary: String {
        let sections = [showsReviews, showsCast, showsInformation, showsFranchise, showsRelated]
        let shown = sections.filter { $0 }.count + (showsWatchAnywhere ? 1 : 0)
        let total = sections.count + (showsWatchAnywhere ? 1 : 0)
        var parts = [shown == total ? "All sections" : "\(shown) of \(total) sections"]
        if titleSectionOrder.isEmpty {
            if sectionOrder == .castFirst { parts.append("Cast first") }
        } else if orderedTitleSections != AppearancePreferences().orderedTitleSections {
            parts.append("Custom order")
        }
        if hidesSpoilers { parts.append("No spoilers") }
        if blursBackground { parts.append("Poster background") }
        if showsTitlePageTabBar { parts.append("Tab bar") }
        return parts.joined(separator: " · ")
    }

    var motionSummary: String {
        let speed = switch animationSpeed {
        case .standard: "Standard speed"
        case .off: "No animation"
        default: "\(animationSpeed.label) animation"
        }
        return "Opens on \(startTab.label) · \(speed)"
    }

    var hoverSummary: String {
        guard hover.isEnabled else { return "Off" }
        var parts = [hover == Hover() ? "Default" : "Custom"]
        if hover.speed != .standard { parts.append(hover.speed.label) }
        return parts.joined(separator: " · ")
    }
}
#endif
