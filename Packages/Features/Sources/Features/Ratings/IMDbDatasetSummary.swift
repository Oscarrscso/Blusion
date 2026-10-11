import Foundation
import StremioKit

/// The one line Settings shows for the IMDb data kept on the device.
enum IMDbDatasetSummary {
    static func text(_ status: IMDbDatasetStatus?) -> String {
        guard let status else { return "Downloading soon" }
        let count = status.titleCount.formatted(.number)
        guard let date = status.updatedAt ?? status.checkedAt else { return "\(count) titles" }
        return "\(count) titles · \(date.formatted(.dateTime.day().month(.abbreviated).year()))"
    }
}
