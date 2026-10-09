import AppKit
import Observation

enum StoreTab: String, CaseIterable, Identifiable {
    case icons, emoji, images, fonts, library

    var id: String { rawValue }

    var title: String {
        switch self {
        case .icons: "Íconos"
        case .emoji: "Emojis"
        case .images: "Imágenes"
        case .fonts: "Fuentes"
        case .library: "Mis recursos"
        }
    }

    var searchPrompt: String {
        switch self {
        case .icons: "Buscá íconos: gato, estrella, café…"
        case .emoji: "Buscá emojis: corazón, fiesta, perro…"
        case .images: "Buscá imágenes libres: flores, montaña…"
        case .fonts: "Buscá fuentes por nombre"
        case .library: "Buscá en tus recursos guardados"
        }
    }
}

// MARK: Root

@Observable
@MainActor
final class StoreModel {
    var tab: StoreTab = .icons
    var thermal: Bool { didSet { UserDefaults.standard.set(thermal, forKey: Self.thermalKey) } }

    let icons: IconsModel
    let emoji: EmojiModel
    let images: ImagesModel
    let fonts: FontsModel
    let saved: SavedModel
    let library: ResourceLibrary
    let loader: ImageLoader

    /// Item ids with a "Usar en…" or favorite action in progress.
    private(set) var busy: [String: String] = [:]
    var actionError: String?

    private static let thermalKey = "ResourceStore.thermalPreview"

    init(http: StoreHTTP = .shared, loader: ImageLoader = .shared, library: ResourceLibrary? = nil) {
        thermal = UserDefaults.standard.bool(forKey: Self.thermalKey)
        let library = library ?? ResourceLibrary()
        self.library = library
        self.loader = loader
        icons = IconsModel(http: http)
        emoji = EmojiModel(http: http)
        images = ImagesModel(http: http)
        fonts = FontsModel(http: http)
        saved = SavedModel(library: library)
    }

    var query: String {
        get {
            switch tab {
            case .icons: icons.query
            case .emoji: emoji.query
            case .images: images.query
            case .fonts: fonts.query
            case .library: saved.query
            }
        }
        set {
            switch tab {
            case .icons: icons.query = newValue; icons.queryChanged()
            case .emoji: emoji.query = newValue; emoji.queryChanged()
            case .images: images.query = newValue; images.queryChanged()
            case .fonts: fonts.query = newValue; fonts.refilter()
            case .library: saved.query = newValue
            }
        }
    }

    func start(_ tab: StoreTab) {
        switch tab {
        case .icons: icons.start()
        case .emoji: emoji.start()
        case .images: break
        case .fonts: fonts.start()
        case .library: library.reload()
        }
    }

    func isBusy(_ item: ResourceItem, _ action: String) -> Bool { busy[item.id] == action }

    func use(_ item: ResourceItem, as destination: ResourceDestination,
             onUse: (CGImage, ResourceInfo, ResourceDestination) -> Void) async {
        guard busy[item.id] == nil else { return }
        busy[item.id] = destination.rawValue
        defer { busy[item.id] = nil }
        do {
            let image = try await loader.full(item)
            actionError = nil
            onUse(image, item.info, destination)
        } catch is CancellationError {
        } catch {
            actionError = StoreError.message(for: error)
        }
    }

    func toggleFavorite(_ item: ResourceItem) async {
        if library.contains(item.favoriteKey) {
            library.remove(favoriteKey: item.favoriteKey)
            if case .file = item.source { saved.selection = nil }
            return
        }
        guard busy[item.id] == nil else { return }
        busy[item.id] = "favorite"
        defer { busy[item.id] = nil }
        do {
            let image = try await loader.full(item)
            try library.save(image, for: item)
            actionError = nil
        } catch is CancellationError {
        } catch {
            actionError = StoreError.message(for: error)
        }
    }
}

// MARK: Íconos

@Observable
@MainActor
final class IconsModel {
    var query = ""
    var prefix: String? { didSet { if prefix != oldValue { refresh() } } }
    var colorful = false {
        didSet {
            guard colorful != oldValue else { return }
            if let prefix, collections[prefix]?.isMonochrome == colorful { self.prefix = nil } else { refresh() }
        }
    }
    var selection: ResourceItem?

    private(set) var items: [ResourceItem] = []
    private(set) var phase: LoadPhase = .idle
    private(set) var total = 0
    private(set) var englishQuery: String?
    private(set) var collections: [String: IconifyCollection] = [:]
    private(set) var loadingMore = false

    private var limit = 240
    private var task: Task<Void, Never>?
    private let http: StoreHTTP

    /// Color counterparts of `Iconify.featured`.
    static let featuredColor = ["red-heart", "star", "cat-face", "dog-face", "paw-prints", "cherry-blossom",
                                "four-leaf-clover", "sun", "crescent-moon", "cloud", "umbrella", "hot-beverage",
                                "birthday-cake", "wrapped-gift", "party-popper", "balloon", "musical-note", "camera",
                                "house", "bicycle", "automobile", "airplane", "rocket", "open-book", "pencil",
                                "scissors", "light-bulb", "key", "locked", "envelope", "mobile-phone", "alarm-clock",
                                "calendar", "round-pushpin", "crown", "gem-stone", "trophy", "pizza", "soft-ice-cream",
                                "cactus", "evergreen-tree", "mushroom", "ghost", "skull", "fire", "high-voltage",
                                "anchor", "grinning-face", "honeybee", "butterfly", "rabbit-face", "owl", "teddy-bear",
                                "rainbow"].map { "fluent-emoji-flat:\($0)" }

    init(http: StoreHTTP) { self.http = http }

    var heading: String {
        let q = query.trimmed
        if !q.isEmpty {
            return englishQuery.map { "Resultados para “\(q)” (buscando “\($0)”)" } ?? "Resultados para “\(q)”"
        }
        if let prefix { return collections[prefix]?.name ?? prefix }
        return "Destacados"
    }

    var canLoadMore: Bool { phase == .loaded && items.count < total && limit < 999 && !loadingMore }

    /// Sets offered in the collection menu: recommended first, then the rest grouped by category.
    var recommendedCollections: [(prefix: String, info: IconifyCollection)] {
        Iconify.recommended.compactMap { p in
            guard let info = collections[p], info.hidden != true, info.isMonochrome != colorful else { return nil }
            return (p, info)
        }
    }

    var otherCollections: [(category: String, sets: [(prefix: String, info: IconifyCollection)])] {
        let recommended = Set(Iconify.recommended)
        let pool = collections.filter { !recommended.contains($0.key) && $0.value.hidden != true && $0.value.isMonochrome != colorful }
        let grouped = Dictionary(grouping: pool) { $0.value.category ?? "Otros" }
        return grouped.keys.sorted().map { category in
            (category, grouped[category]!.map { ($0.key, $0.value) }
                .sorted { $0.info.name.localizedCaseInsensitiveCompare($1.info.name) == .orderedAscending })
        }
    }

    func start() {
        if phase == .idle { refresh() }
    }

    func queryChanged() { refresh(debounce: true) }

    func refresh(debounce: Bool = false) {
        task?.cancel()
        limit = 240
        loadingMore = false
        task = Task { [weak self] in
            if debounce { try? await Task.sleep(for: .milliseconds(350)) }
            guard !Task.isCancelled else { return }
            await self?.load()
        }
    }

    func loadMore() {
        task?.cancel()
        limit = 999
        loadingMore = true
        task = Task { [weak self] in
            await self?.load(keepItems: true)
            self?.loadingMore = false
        }
    }

    private func ensureCollections() async {
        guard collections.isEmpty else { return }
        if let data = try? await http.data(from: Iconify.collectionsURL), let parsed = try? Iconify.parseCollections(data) {
            collections = parsed
        }
    }

    private func load(keepItems: Bool = false) async {
        if !keepItems { phase = .loading }
        await ensureCollections()
        do {
            let q = query.trimmed
            var newItems: [ResourceItem]
            var newTotal: Int
            var english: String?
            if q.isEmpty, let prefix {
                let data = try await http.data(from: Iconify.collectionURL(prefix: prefix))
                let names = try Iconify.parseListing(data).allIcons
                newTotal = names.count
                newItems = names.prefix(limit).compactMap { Iconify.item(id: "\(prefix):\($0)", collection: collections[prefix]) }
            } else if q.isEmpty {
                let ids = colorful ? Self.featuredColor : Iconify.featured
                newItems = ids.compactMap { id in Iconify.item(id: id, collection: Iconify.split(id).flatMap { collections[$0.prefix] }) }
                newTotal = newItems.count
            } else {
                english = SpanishKeywords.englishQuery(for: q)
                let url = Iconify.searchURL(query: english ?? q, limit: limit, prefix: prefix, colorful: colorful)
                let result = try Iconify.parseSearch(try await http.data(from: url))
                for (key, value) in result.collections where collections[key] == nil { collections[key] = value }
                newItems = result.icons.compactMap { id in
                    Iconify.item(id: id, collection: Iconify.split(id).flatMap { result.collections[$0.prefix] ?? collections[$0.prefix] })
                }
                newTotal = result.total
            }
            try Task.checkCancellation()
            items = newItems
            total = max(newTotal, newItems.count)
            englishQuery = english
            phase = .loaded
            if let selection, !newItems.contains(selection) { self.selection = nil }
        } catch is CancellationError {
        } catch {
            guard !Task.isCancelled else { return }
            phase = .failed(StoreError.message(for: error))
        }
    }
}

// MARK: Emojis

@Observable
@MainActor
final class EmojiModel {
    var query = ""
    var group: String? { didSet { if group != oldValue { refilter() } } }
    var colorful = false { didSet { if colorful != oldValue { refilter() } } }
    var selection: ResourceItem?

    private(set) var entries: [OpenMojiEntry] = []
    private(set) var items: [ResourceItem] = []
    private(set) var phase: LoadPhase = .idle
    private(set) var englishQuery: String?

    private var task: Task<Void, Never>?
    private let http: StoreHTTP

    init(http: StoreHTTP) { self.http = http }

    var heading: String {
        let q = query.trimmed
        if !q.isEmpty {
            return englishQuery.map { "Resultados para “\(q)” (buscando “\($0)”)" } ?? "Resultados para “\(q)”"
        }
        return group.flatMap { g in OpenMoji.groups.first { $0.id == g }?.title } ?? "Todos los emojis"
    }

    func start() {
        guard entries.isEmpty, phase != .loading else { return }
        Task { await loadCatalog() }
    }

    func loadCatalog() async {
        phase = .loading
        do {
            let data = try await http.data(from: OpenMoji.catalogURL, policy: .returnCacheDataElseLoad, timeout: 60)
            entries = try await Task.detached(priority: .userInitiated) { try OpenMoji.parseCatalog(data) }.value
            refilter()
            phase = .loaded
        } catch {
            phase = .failed(StoreError.message(for: error))
        }
    }

    func queryChanged() {
        task?.cancel()
        task = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            self?.refilter()
        }
    }

    func refilter() {
        guard !entries.isEmpty else { return }
        englishQuery = SpanishKeywords.englishQuery(for: query)
        let results = OpenMoji.search(entries, query: query, group: group)
        items = results.map { OpenMoji.item($0, color: colorful) }
        if let selection {
            // Keep the same emoji selected when switching outline/color.
            let hex = selection.id.split(separator: ":").dropFirst().first.map(String.init)
            self.selection = items.first { $0.id.split(separator: ":").dropFirst().first.map(String.init) == hex }
        }
    }
}

// MARK: Imágenes

@Observable
@MainActor
final class ImagesModel {
    var query = ""
    var category: Openverse.Category = .all { didSet { if category != oldValue { refresh() } } }
    var selection: ResourceItem?

    private(set) var items: [ResourceItem] = []
    private(set) var phase: LoadPhase = .idle
    private(set) var resultCount = 0
    private(set) var englishQuery: String?
    private(set) var loadingMore = false
    private var page = 1
    private var pageCount = 0
    private var task: Task<Void, Never>?
    private let http: StoreHTTP

    static let suggestions = ["flores", "gato", "montaña", "mariposa", "café", "bicicleta", "playa", "dinosaurio"]

    init(http: StoreHTTP) { self.http = http }

    var heading: String {
        let q = query.trimmed
        return englishQuery.map { "Resultados para “\(q)” (buscando “\($0)”)" } ?? "Resultados para “\(q)”"
    }

    var canLoadMore: Bool { phase == .loaded && page < pageCount && !loadingMore }

    func queryChanged() { refresh(debounce: true) }

    func search(_ text: String) {
        query = text
        refresh()
    }

    func refresh(debounce: Bool = false) {
        task?.cancel()
        loadingMore = false
        task = Task { [weak self] in
            // Openverse allows few anonymous searches per minute: wait until typing stops.
            if debounce { try? await Task.sleep(for: .milliseconds(600)) }
            guard !Task.isCancelled else { return }
            await self?.load(page: 1)
        }
    }

    func loadMore() {
        guard canLoadMore else { return }
        loadingMore = true
        let next = page + 1
        task = Task { [weak self] in await self?.load(page: next) }
    }

    private func load(page: Int) async {
        let q = query.trimmed
        guard !q.isEmpty else {
            items = []
            phase = .idle
            englishQuery = nil
            return
        }
        if page == 1 { phase = .loading }
        defer { loadingMore = false }
        do {
            let english = SpanishKeywords.englishQuery(for: q)
            let data = try await http.data(from: Openverse.searchURL(query: english ?? q, page: page, category: category))
            let result = try Openverse.parse(data)
            try Task.checkCancellation()
            let newItems = result.results.compactMap(Openverse.item)
            if page == 1 {
                items = newItems
            } else {
                let known = Set(items.map(\.id))
                items += newItems.filter { !known.contains($0.id) }
            }
            self.page = page
            pageCount = result.pageCount
            resultCount = result.resultCount
            englishQuery = english
            phase = .loaded
            if page == 1, let selection, !items.contains(selection) { self.selection = nil }
        } catch is CancellationError {
        } catch {
            guard !Task.isCancelled else { return }
            if page == 1 { phase = .failed(StoreError.message(for: error)) }
        }
    }
}

// MARK: Fuentes

@Observable
@MainActor
final class FontsModel {
    var query = ""
    var category: GoogleFonts.Category = .all { didSet { refilter() } }
    var showInstalled = false { didSet { refilter() } }
    var selection: GoogleFontFamily?

    private(set) var families: [GoogleFontFamily] = []
    private(set) var rows: [GoogleFontFamily] = []
    private(set) var installed: [FontLibrary.Installed] = []
    private(set) var phase: LoadPhase = .idle
    private(set) var installing: Set<String> = []
    var errorMessage: String?

    private let http: StoreHTTP
    private var observer: NSObjectProtocol?

    /// The metadata is served with no-store, so it is kept on disk here and refreshed weekly.
    static var metadataFile: URL { StorePaths.caches.appendingPathComponent("google-fonts-metadata.json") }

    init(http: StoreHTTP) {
        self.http = http
        installed = FontLibrary.installed()
        observer = NotificationCenter.default.addObserver(forName: FontLibrary.didChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reloadInstalled() }
        }
    }

    func start() {
        reloadInstalled()
        guard families.isEmpty, phase != .loading else { return }
        Task { await loadMetadata() }
    }

    func isInstalled(_ family: GoogleFontFamily) -> Bool { installed.contains { $0.folderName == family.family } }

    func reloadInstalled() {
        installed = FontLibrary.installed()
        refilter()
    }

    func loadMetadata() async {
        phase = .loading
        let file = Self.metadataFile
        let attributes = try? FileManager.default.attributesOfItem(atPath: file.path)
        let age = (attributes?[.modificationDate] as? Date).map { -$0.timeIntervalSinceNow } ?? .infinity
        do {
            var data: Data
            if age < 7 * 86400, let cached = try? Data(contentsOf: file) {
                data = cached
            } else {
                do {
                    data = try await http.data(from: GoogleFonts.metadataURL, timeout: 60)
                    try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try? data.write(to: file, options: .atomic)
                } catch {
                    guard let stale = try? Data(contentsOf: file) else { throw error }
                    data = stale
                }
            }
            families = try await Task.detached(priority: .userInitiated) { try GoogleFonts.parseMetadata(data) }.value
            refilter()
            phase = .loaded
        } catch {
            phase = .failed(StoreError.message(for: error))
        }
    }

    func refilter() {
        let q = query.trimmed.folded
        var pool: [GoogleFontFamily]
        if showInstalled {
            let byName = Dictionary(families.map { ($0.family, $0) }, uniquingKeysWith: { a, _ in a })
            pool = installed.map { byName[$0.folderName] ?? GoogleFontFamily(family: $0.folderName, category: "") }
        } else {
            pool = families
        }
        if category != .all { pool = pool.filter { $0.category == category.rawValue } }
        if !q.isEmpty { pool = pool.filter { $0.family.folded.contains(q) } }
        rows = pool
    }

    func install(_ family: GoogleFontFamily) async {
        guard !installing.contains(family.family) else { return }
        installing.insert(family.family)
        defer { installing.remove(family.family) }
        do {
            try await FontLibrary.install(family, http: http)
            errorMessage = nil
        } catch is CancellationError {
        } catch {
            errorMessage = StoreError.message(for: error)
        }
        reloadInstalled()
    }

    func remove(_ family: GoogleFontFamily) {
        do {
            try FontLibrary.remove(family.family)
            errorMessage = nil
        } catch {
            errorMessage = "No se pudo quitar la fuente: \(error.localizedDescription)"
        }
        reloadInstalled()
    }
}

// MARK: Mis recursos

@Observable
@MainActor
final class SavedModel {
    var query = ""
    var kind: ResourceKind?
    var selection: ResourceItem?
    let library: ResourceLibrary

    init(library: ResourceLibrary) { self.library = library }

    var items: [ResourceItem] {
        let q = query.trimmed.folded
        return library.resources
            .filter { kind == nil || $0.kind == kind }
            .filter { q.isEmpty || $0.info.name.folded.contains(q) || $0.info.source.folded.contains(q) }
            .map(library.item)
    }
}
