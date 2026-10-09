import Foundation
import Observation
import StremioKit

/// Settings › Widgets: the widgets that make up Home, edited in place, plus Fusion-compatible import and export.
@MainActor
@Observable
public final class WidgetsManagerViewModel {
    /// A catalog the user can pick as a row's source.
    public struct CatalogChoice: Identifiable, Hashable, Sendable {
        /// Without a genre.
        public let reference: AddonCatalogReference
        /// "Popular Movies" (`DefaultWidgets.rowTitle`).
        public let title: String
        public let addonName: String
        /// The catalog's genre options.
        public let genres: [String]

        /// `<manifestID>/<type>/<catalogID>`.
        public var id: String { "\(reference.manifestID ?? "")/\(reference.catalogType)/\(reference.catalogID)" }
    }

    public enum ImportMode: Sendable, Hashable { case append, replace }

    /// Why a Trakt list link could not be added. `message` is one plain sentence for the user.
    public enum TraktLinkError: Error, Equatable, Sendable {
        case notAListLink
        case failed(String)

        public var message: String {
            switch self {
            case .notAListLink: return "That isn't a Trakt list link. Paste an address like trakt.tv/users/name/lists/list-name."
            case .failed(let reason): return "Trakt couldn't read this list (\(reason))."
            }
        }
    }

    /// An import that refers to addons which are not installed, waiting for the user's decision.
    public struct PendingImport: Equatable, Sendable {
        public let widgetCount: Int
        public let missingAddonHosts: [String]
    }

    public private(set) var widgets: [HomeWidget] = []
    public private(set) var isCustomised = false
    public private(set) var catalogChoices: [CatalogChoice] = []
    public private(set) var pendingImport: PendingImport?
    public private(set) var isWorking = false
    /// One sentence about the last action ("Imported 8 widgets.", "That isn't a widget export.") or nil.
    public private(set) var message: String?
    public private(set) var messageIsError = false

    /// The same limit `FusionWidgetCodec` enforces, applied to the download as well.
    private static let maxImportBytes = 2 * 1024 * 1024

    private let services: AppServices
    /// The installed addons as of the last read. `describe` cannot await, so it works from this.
    private var installedAddons: [InstalledAddon] = []
    /// An import waiting for addons. Kept in memory only: its text holds addon links, which are secrets.
    private var pendingData: Data?
    private var pendingMode: ImportMode?
    private var pendingLinks: [String] = []

    public init(services: AppServices) {
        self.services = services
    }

    // MARK: Loading and editing

    /// The saved widgets, or the automatic layout when none are saved.
    public func load() async {
        let saved = await services.widgets.load()
        let addons = await readAddons()
        widgets = saved ?? DefaultWidgets.make(for: addons)
        isCustomised = saved != nil
    }

    /// Appended at the end. A widget whose id the list already uses gets a new one.
    public func add(_ widget: HomeWidget) async {
        let current = widgets
        await commit(current + WidgetsManagerViewModel.withFreshIDs([widget], existing: current))
    }

    /// Replaces the widget with the same id. An unknown id changes nothing.
    public func update(_ widget: HomeWidget) async {
        guard let index = widgets.firstIndex(where: { $0.id == widget.id }) else { return }
        var list = widgets
        list[index] = widget
        await commit(list)
    }

    public func remove(id: String) async {
        guard widgets.contains(where: { $0.id == id }) else { return }
        await commit(widgets.filter { $0.id != id })
    }

    public func remove(atOffsets offsets: IndexSet) async {
        let kept = widgets.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
        guard kept.count < widgets.count else { return }
        await commit(kept)
    }

    /// SwiftUI `onMove` shape: the widgets at `offsets` end up before `destination`, an index into the list as it is now.
    public func move(fromOffsets offsets: IndexSet, toOffset destination: Int) async {
        let moved = offsets.filter { widgets.indices.contains($0) }
        guard !moved.isEmpty else { return }
        let moving = moved.map { widgets[$0] }
        var list = widgets.enumerated().filter { !moved.contains($0.offset) }.map(\.element)
        let insertion = destination - moved.filter { $0 < destination }.count
        list.insert(contentsOf: moving, at: min(max(insertion, 0), list.count))
        await commit(list)
    }

    /// Forgets the saved list: Home goes back to the automatic layout for the installed addons.
    public func resetToAutomatic() async {
        let addons = await readAddons()
        widgets = DefaultWidgets.make(for: addons)
        isCustomised = false
        clearMessage()
        await services.widgets.save(nil)
        await services.widgetContent.invalidate()
    }

    /// The public Trakt list a pasted link names, read from Trakt so the row gets its real name.
    public func traktList(fromLink text: String) async throws -> TraktListReference {
        guard let parts = TraktClient.listReference(fromLink: text) else { throw TraktLinkError.notAListLink }
        let clientID = await TraktClient.clientID(in: services.settings)
        do {
            let info = try await services.trakt.listInfo(username: parts.username, listSlug: parts.listSlug, clientID: clientID)
            return TraktListReference(username: parts.username, listSlug: parts.listSlug, listName: info.name, traktID: info.traktID)
        } catch {
            throw TraktLinkError.failed(AddonError.from(error).shortDescription.lowercased())
        }
    }

    // MARK: Import and export

    /// Reads Fusion's widget JSON. `.replace` swaps the whole list; `.append` adds to its end.
    public func importJSON(_ text: String, mode: ImportMode) async {
        await importData(Data(text.utf8), mode: mode)
    }

    /// Downloads a widget file from an http(s) link, then imports it like `importJSON`.
    public func importFromURL(_ text: String, mode: ImportMode) async {
        let link = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: link), let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              url.host?.isEmpty == false else {
            report("That isn't a web link. Paste an address that starts with https://.", isError: true)
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let result = try await services.client.get(url, limits: FetchLimits(maxBytes: WidgetsManagerViewModel.maxImportBytes))
            await importData(result.data, mode: mode)
        } catch {
            report("Couldn't download the widget file (\(AddonError.from(error).shortDescription.lowercased())).", isError: true)
        }
    }

    /// Installs the addons a pending import needs, then saves the import now that its links resolve.
    public func installMissingAddonsAndFinishImport() async {
        guard let data = pendingData, let mode = pendingMode else { return }
        let links = pendingLinks
        isWorking = true
        var installed = 0
        var failed = 0
        for link in links {
            do {
                try await services.registry.install(from: link)
                installed += 1
            } catch RegistryError.alreadyInstalled {
                continue
            } catch {
                failed += 1
            }
        }
        isWorking = false
        await finishImport(data, mode: mode, installed: installed, failed: failed)
    }

    /// Saves the pending import as it is. Widgets whose addon is missing say so on Home.
    public func finishImportWithoutAddons() async {
        guard let data = pendingData, let mode = pendingMode else { return }
        await finishImport(data, mode: mode, installed: 0, failed: 0)
    }

    public func cancelImport() {
        clearPending()
    }

    /// The current widgets as Fusion-compatible JSON text (pretty printed), or nil if encoding fails.
    public func exportJSON() -> String? {
        guard let data = try? FusionWidgetCodec.encode(widgets) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Decodes an import off the main actor. Addons it needs that are not installed hold it until the user decides; otherwise it is saved.
    private func importData(_ data: Data, mode: ImportMode) async {
        clearPending()
        let addons = await readAddons()
        let result: FusionWidgetCodec.ImportResult
        do {
            result = try await Task.detached { try FusionWidgetCodec.decode(data, installed: addons) }.value
        } catch {
            report(WidgetsManagerViewModel.refusal(error), isError: true)
            return
        }
        guard result.missingAddonLinks.isEmpty else {
            // The links are secrets: they stay in memory, and only their hosts are shown.
            pendingData = data
            pendingMode = mode
            pendingLinks = result.missingAddonLinks
            pendingImport = PendingImport(widgetCount: result.widgets.count, missingAddonHosts: result.missingAddonHosts)
            clearMessage()
            return
        }
        let added = await store(result, mode: mode)
        report(WidgetsManagerViewModel.importSummary(count: added, skipped: result.skipped), isError: false)
    }

    /// Decodes a pending import again, now that its addons may be installed, and saves it.
    private func finishImport(_ data: Data, mode: ImportMode, installed: Int, failed: Int) async {
        clearPending()
        let addons = await readAddons()
        do {
            let result = try await Task.detached { try FusionWidgetCodec.decode(data, installed: addons) }.value
            let added = await store(result, mode: mode)
            report(WidgetsManagerViewModel.importSummary(count: added, skipped: result.skipped, installed: installed, failed: failed), isError: false)
        } catch {
            report(WidgetsManagerViewModel.refusal(error), isError: true)
        }
    }

    /// Saves what an import read, and returns how many widgets it brought in.
    private func store(_ result: FusionWidgetCodec.ImportResult, mode: ImportMode) async -> Int {
        let imported = WidgetsManagerViewModel.withFreshIDs(result.widgets, existing: mode == .append ? widgets : [])
        await commit(mode == .append ? widgets + imported : imported)
        return imported.count
    }

    // MARK: Describing sources and widgets

    /// "Popular Movies · Cinemeta", "Trakt list · Daily Picks by tvgeniekodi", "Not supported (anilistCatalog)",
    /// "Catalog from example.com (addon not installed)".
    public func describe(_ source: WidgetSource) -> String {
        switch source {
        case .addonCatalog(let reference):
            guard let match = reference.resolve(in: installedAddons) else {
                guard let host = reference.host else { return "Catalog (addon not installed)" }
                return "Catalog from \(host) (addon not installed)"
            }
            var parts = [DefaultWidgets.rowTitle(catalogName: match.catalog.name, type: match.catalog.type)]
            if let genre = reference.genre, !genre.isEmpty { parts.append(genre) }
            parts.append(match.addon.name)
            return parts.joined(separator: " · ")
        case .traktList(let list):
            let sort = list.sort.map { " · \($0.title)" } ?? ""
            return "Trakt list · \(list.listName) by \(list.username)\(sort)"
        case .traktFeed(let feed):
            return "Trakt · \(feed.title)"
        case .unsupported(let kind):
            return "Not supported (\(kind))"
        }
    }

    /// A short summary for a widget's row in the manager list: "Row · Popular Movies · Cinemeta", "Collection · 12 tiles", and so on.
    public func summary(of widget: HomeWidget) -> String {
        switch widget.content {
        case .row(let row): return "Row · \(describe(row.source))"
        case .hero(let row): return "Spotlight · \(describe(row.source))"
        case .banner(let row): return "Banner · \(describe(row.source))"
        case .collection(let tiles): return "Collection · \(WidgetsManagerViewModel.plural(tiles.count, "tile"))"
        case .continueWatching: return "Continue"
        case .unsupported(let type): return "Can't show yet · \(type)"
        }
    }

    /// The name a source gives a widget unless the user types another: the genre or catalog title, the Trakt list or feed name.
    public func autoTitle(for source: WidgetSource) -> String {
        switch source {
        case .addonCatalog(let reference):
            if let genre = reference.genre, !genre.isEmpty { return genre }
            guard let match = reference.resolve(in: installedAddons) else { return "" }
            return DefaultWidgets.rowTitle(catalogName: match.catalog.name, type: match.catalog.type)
        case .traktList, .traktFeed:
            return WidgetsManagerViewModel.traktTitle(source)
        case .unsupported:
            return ""
        }
    }

    /// The genres a catalog offers as a filter; empty when it has none or its addon is not installed.
    public func genres(for source: WidgetSource) -> [String] {
        guard case .addonCatalog(let reference) = source, let match = reference.resolve(in: installedAddons) else { return [] }
        return match.catalog.genreOptions
    }

    // MARK: Making widgets

    /// A row of one catalog, optionally filtered to a genre. Gets a new id.
    public static func makeRow(title: String, choice: CatalogChoice, genre: String? = nil, presentation: WidgetPresentation = WidgetPresentation(),
                               limit: Int = 20) -> HomeWidget {
        let row = RowConfiguration(source: .addonCatalog(catalogReference(choice, genre: genre)), presentation: presentation, limit: limit)
        return HomeWidget(title: title, content: .row(row))
    }

    /// A row of a Trakt list or feed, titled as the list or feed is named.
    public static func makeTraktRow(_ source: WidgetSource) -> HomeWidget {
        HomeWidget(title: traktTitle(source), content: .row(RowConfiguration(source: source)))
    }

    /// The large paging spotlight of a Trakt list or feed.
    public static func makeTraktSpotlight(_ source: WidgetSource) -> HomeWidget {
        HomeWidget(title: traktTitle(source), hideTitle: true, content: .hero(RowConfiguration(source: source, limit: 8)))
    }

    /// The featured banner of a Trakt list: its first title large, the rest in a row below.
    public static func makeTraktBanner(_ source: WidgetSource) -> HomeWidget {
        HomeWidget(title: traktTitle(source), content: .banner(RowConfiguration(source: source, limit: 20)))
    }

    /// The name a Trakt list or feed is shown under, or "Trakt" for any other source.
    public static func traktTitle(_ source: WidgetSource) -> String {
        switch source {
        case .traktList(let list): return list.listName
        case .traktFeed(let feed): return feed.title
        case .addonCatalog, .unsupported: return "Trakt"
        }
    }

    /// The large paging spotlight of one catalog, as the automatic layout makes it.
    public static func makeHero(choice: CatalogChoice, genre: String? = nil) -> HomeWidget {
        let row = RowConfiguration(source: .addonCatalog(catalogReference(choice, genre: genre)), limit: 8)
        return HomeWidget(title: choice.title, hideTitle: true, content: .hero(row))
    }

    /// The featured banner of one catalog, as the add sheet makes it.
    public static func makeBanner(choice: CatalogChoice, genre: String? = nil) -> HomeWidget {
        let row = RowConfiguration(source: .addonCatalog(catalogReference(choice, genre: genre)), limit: 20)
        return HomeWidget(title: choice.title, content: .banner(row))
    }

    /// A collection with one tile per genre of the catalog. Each tile opens that genre's grid.
    public static func makeGenreCollection(title: String, choice: CatalogChoice) -> HomeWidget {
        var seen = Set<String>()
        let tiles = choice.genres.filter { seen.insert($0).inserted }.map { genre in
            CollectionItem(id: "\(choice.id)/\(genre)", title: genre, imageAspect: .wide, sources: [.addonCatalog(catalogReference(choice, genre: genre))])
        }
        return HomeWidget(title: title, content: .collection(tiles))
    }

    // MARK: Helpers

    private static func catalogReference(_ choice: CatalogChoice, genre: String?) -> AddonCatalogReference {
        var reference = choice.reference
        if let genre, !genre.isEmpty { reference.genre = genre }
        return reference
    }

    /// Every browsable catalog of the enabled addons, in the user's addon order. Addons that share a manifest id offer each catalog once.
    private static func choices(in addons: [InstalledAddon]) -> [CatalogChoice] {
        var seen = Set<String>()
        var choices: [CatalogChoice] = []
        for addon in addons where addon.isEnabled {
            for catalog in addon.manifest.browsableCatalogs() {
                let reference = AddonCatalogReference(manifestID: addon.manifest.id, host: addon.displayHost, catalogType: catalog.type,
                                                      catalogID: catalog.id)
                let choice = CatalogChoice(reference: reference, title: DefaultWidgets.rowTitle(catalogName: catalog.name, type: catalog.type),
                                           addonName: addon.name, genres: catalog.genreOptions)
                if seen.insert(choice.id).inserted { choices.append(choice) }
            }
        }
        return choices
    }

    /// The widgets with ids unused in `existing` and in the list itself. A repeated id gets a new one.
    private static func withFreshIDs(_ list: [HomeWidget], existing: [HomeWidget]) -> [HomeWidget] {
        var taken = Set(existing.map(\.id))
        return list.map { widget in
            var fresh = widget
            if !taken.insert(widget.id).inserted { fresh.id = UUID().uuidString }
            return fresh
        }
    }

    /// "Imported 8 widgets, skipped 2." After an install: "Imported 8 widgets and installed 1 addon. 1 addon couldn't be installed."
    private static func importSummary(count: Int, skipped: Int, installed: Int = 0, failed: Int = 0) -> String {
        var text = "Imported \(plural(count, "widget"))"
        if installed > 0 { text += " and installed \(plural(installed, "addon"))" }
        if skipped > 0 { text += ", skipped \(skipped)" }
        text += "."
        if failed > 0 { text += " \(plural(failed, "addon")) couldn't be installed." }
        return text
    }

    private static func refusal(_ error: Error) -> String {
        (error as? WidgetImportError)?.message ?? "That isn't a widget export."
    }

    private static func plural(_ count: Int, _ noun: String) -> String {
        "\(count) \(count == 1 ? noun : noun + "s")"
    }

    /// Shows and saves a new list. The first change to the automatic layout saves the whole layout with the change.
    private func commit(_ list: [HomeWidget]) async {
        widgets = list
        isCustomised = true
        clearMessage()
        await services.widgets.save(list)
        await services.widgetContent.invalidate()
    }

    /// Reads the installed addons, and the catalog choices they offer. Called wherever an install or import may have changed them.
    private func readAddons() async -> [InstalledAddon] {
        let addons = await services.registry.addons
        installedAddons = addons
        catalogChoices = WidgetsManagerViewModel.choices(in: addons)
        return addons
    }

    private func report(_ text: String, isError: Bool) {
        message = text
        messageIsError = isError
    }

    private func clearMessage() {
        message = nil
        messageIsError = false
    }

    private func clearPending() {
        pendingImport = nil
        pendingData = nil
        pendingMode = nil
        pendingLinks = []
    }
}
