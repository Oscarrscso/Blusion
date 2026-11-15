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
        if isDefault(.text) { return "Default" }
        var parts: [String] = []
        if textSize != .system { parts.append(textSize.label) }
        if font != .standard { parts.append(font.label) }
        if reading.weight != .regular { parts.append(reading.weight.label) }
        if font == .standard, fontWidth != .standard { parts.append(fontWidth.label) }
        if italicText { parts.append("Italic") }
        if reading.capitals { parts.append("Caps") }
        if reading.colour != .primary { parts.append(reading.colour.label) }
        if !interface.followsReading { parts.append("Custom interface") }
        if headings != TextStyle.headings() { parts.append("Custom headings") }
        return parts.isEmpty ? "System size" : parts.joined(separator: " · ")
    }

    /// What a kind of text is set to, on its row of the Text page.
    func textRoleSummary(_ role: TextRole) -> String {
        switch role {
        case .reading:
            let style = resolvedText(for: .reading)
            var parts = [style.font.label]
            if style.scale != .standard { parts.append(style.scale.label) }
            if style.weight != .regular { parts.append(style.weight.label) }
            if style.font == .standard, style.width != .standard { parts.append(style.width.label) }
            if style.letterSpacing != .standard { parts.append("\(style.letterSpacing.label) letters") }
            if style.lineSpacing != .standard { parts.append("\(style.lineSpacing.label) lines") }
            if style.italic { parts.append("Italic") }
            if style.capitals { parts.append("Caps") }
            if style.colour != .primary { parts.append(style.colour.label) }
            return parts.joined(separator: " · ")
        case .interface:
            if interface.followsReading, interface.colour == .primary, !interface.capitals {
                return "Same as body text"
            }
            let style = resolvedText(for: .interface)
            var parts = [style.font.label]
            if !interface.followsTextSize { parts.append(interface.textSize.label) }
            if !interface.followsScale, interface.scale != .standard || reading.scale != .standard {
                parts.append(interface.scale == .standard ? "Standard size" : interface.scale.label)
            }
            if !interface.followsWeight { parts.append(interface.weight.label) }
            if style.font == .standard, !interface.followsWidth, interface.width != .standard || reading.width != .standard {
                parts.append(interface.width == .standard ? "Standard width" : interface.width.label)
            }
            if !interface.followsLetterSpacing, interface.letterSpacing != .standard || reading.letterSpacing != .standard {
                parts.append("\(interface.letterSpacing.label) letters")
            }
            if !interface.followsLineSpacing, interface.lineSpacing != .standard || reading.lineSpacing != .standard {
                parts.append("\(interface.lineSpacing.label) lines")
            }
            if !interface.followsItalic, interface.italic || reading.italic {
                parts.append(interface.italic ? "Italic" : "Not italic")
            }
            if interface.capitals { parts.append("Caps") }
            if interface.colour != .primary { parts.append(interface.colour.label) }
            return parts.joined(separator: " · ")
        case .display:
            let defaults = TextStyle.headings()
            if headings == defaults { return "Default" }
            let style = resolvedText(for: .display)
            var parts = [style.font.label]
            if !headings.followsTextSize { parts.append(headings.textSize.label) }
            if style.scale != defaults.scale {
                parts.append(style.scale == .standard ? "Standard size" : style.scale.label)
            }
            if style.weight != defaults.weight { parts.append(style.weight.label) }
            if style.font == .standard, !headings.followsWidth, headings.width != .standard || reading.width != .standard {
                parts.append(headings.width == .standard ? "Standard width" : headings.width.label)
            }
            if !headings.followsLetterSpacing, headings.letterSpacing != .standard || reading.letterSpacing != .standard {
                parts.append("\(headings.letterSpacing.label) letters")
            }
            if !headings.followsLineSpacing, headings.lineSpacing != .standard || reading.lineSpacing != .standard {
                parts.append("\(headings.lineSpacing.label) lines")
            }
            if !headings.followsItalic, headings.italic || reading.italic {
                parts.append(headings.italic ? "Italic" : "Not italic")
            }
            if headings.capitals { parts.append("Caps") }
            if headings.colour != .primary { parts.append(headings.colour.label) }
            return parts.joined(separator: " · ")
        }
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
