import Foundation
import Observation
import PlayerKit
import StremioKit

/// Library membership and watched marks for any title, kept current so menus and badges can read them without waiting.
@MainActor
@Observable
public final class TitleActions {
    /// `type/id` of every saved title.
    public private(set) var savedIdentities: Set<String> = []
    /// `type/id` of every watched movie. Series are never marked watched from here.
    public private(set) var watchedIdentities: Set<String> = []

    private let services: AppServices

    public init(services: AppServices) {
        self.services = services
    }

    /// Reads the library and the watch history again. Call when a screen appears, since other screens change them too.
    public func refresh() async {
        savedIdentities = Set(await services.library.all().map(\.id))
        watchedIdentities = Set(await services.progress.all().filter { $0.isWatched && $0.type == "movie" }.map(\.id))
    }

    public func isSaved(_ item: MetaPreview) -> Bool {
        savedIdentities.contains(Self.identity(of: item))
    }

    public func isWatched(_ item: MetaPreview) -> Bool {
        watchedIdentities.contains(Self.identity(of: item))
    }

    /// Saves the title, or removes it. Decides from the store rather than the cached set, so a stale menu cannot save twice.
    public func toggleSaved(_ item: MetaPreview) async {
        let identity = Self.identity(of: item)
        if await services.library.contains(identity) {
            await services.library.remove(identity)
        } else {
            await services.library.add(LibraryItem(preview: item, addedAt: Date()))
        }
        await refresh()
    }

    /// Movies only: marks watched or removes the mark, as Detail does. Does nothing for other types.
    public func setWatched(_ watched: Bool, for item: MetaPreview) async {
        guard Self.itemType(of: item) == "movie" else { return }
        let identity = Self.identity(of: item)
        if watched {
            await services.progress.save(WatchProgress(id: identity, type: "movie", contentID: item.id, title: item.name, poster: item.poster,
                                                       position: 0, duration: 0, isWatched: true, updatedAt: Date()))
        } else {
            await services.progress.remove(identity)
        }
        await refresh()
    }

    /// A title with no type is a movie, as in `LibraryItem` and `StreamRequest`, so it is keyed the same way everywhere.
    private static func itemType(of item: MetaPreview) -> String {
        item.type.isEmpty ? "movie" : item.type
    }

    private static func identity(of item: MetaPreview) -> String {
        LibraryItem.identity(type: itemType(of: item), contentID: item.id)
    }
}
