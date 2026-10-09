import AppKit
import SwiftUI

/// "Tienda": browses free icons, emoji, images and fonts and hands the chosen one to the app.
/// Meant to be shown as a sheet or window of about 900×640.
public struct ResourceStoreView: View {
    /// StateObject's autoclosure builds the model once, not on every re-render of the parent.
    @StateObject private var holder: ModelHolder
    private let onUse: (CGImage, ResourceInfo, ResourceDestination) -> Void

    /// `onUse` receives a high-resolution image that keeps its transparency.
    public init(onUse: @escaping (CGImage, ResourceInfo, ResourceDestination) -> Void) {
        _holder = StateObject(wrappedValue: ModelHolder(StoreModel()))
        self.onUse = onUse
    }

    init(model: StoreModel, onUse: @escaping (CGImage, ResourceInfo, ResourceDestination) -> Void) {
        _holder = StateObject(wrappedValue: ModelHolder(model))
        self.onUse = onUse
    }

    public var body: some View {
        let model = holder.model
        VStack(spacing: 0) {
            StoreHeader(model: model)
            Divider()
            HStack(spacing: 0) {
                StoreContent(model: model)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                StoreDetail(model: model, onUse: onUse)
                    .frame(width: 300)
                    .frame(maxHeight: .infinity)
                    .background(Color(nsColor: .controlBackgroundColor))
            }
            Divider()
            StoreFooter(model: model)
        }
        .frame(minWidth: 820, idealWidth: 900, minHeight: 560, idealHeight: 640)
        .background(Color(nsColor: .windowBackgroundColor))
        .task(id: model.tab) { model.start(model.tab) }
    }
}

@MainActor
final class ModelHolder: ObservableObject {
    let model: StoreModel
    init(_ model: StoreModel) { self.model = model }
}

// MARK: Header

struct StoreHeader: View {
    @Bindable var model: StoreModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 12) {
            // Equal flexible sides keep the section picker centered in the window.
            HStack(spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "bag.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.accentColor.gradient))
                    ViewThatFits(in: .horizontal) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Tienda").font(.headline)
                            Text("Recursos libres para imprimir").font(.caption).foregroundStyle(.secondary)
                        }
                        .fixedSize()
                        Text("Tienda").font(.headline)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Picker("Sección", selection: $model.tab) {
                    ForEach(StoreTab.allCases) { tab in Text(tab.title).tag(tab) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Button("Listo") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            HStack(spacing: 10) {
                SearchField(text: $model.query, prompt: model.tab.searchPrompt)
                    .frame(minWidth: 180, idealWidth: 320, maxWidth: 320)
                    .id(model.tab)
                StoreFilters(model: model)
                Spacer(minLength: 0)
                Toggle("Vista térmica", isOn: $model.thermal)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .fixedSize()
                    .help("Mostrá cada recurso como sale impreso: 1 bit, 203 dpi")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(.bar)
    }
}

struct StoreFilters: View {
    @Bindable var model: StoreModel

    var body: some View {
        switch model.tab {
        case .icons: IconFilters(icons: model.icons)
        case .emoji:
            @Bindable var emoji = model.emoji
            Picker("Categoría", selection: $emoji.group) {
                Text("Todas las categorías").tag(String?.none)
                Divider()
                ForEach(OpenMoji.groups, id: \.id) { group in Text(group.title).tag(Optional(group.id)) }
            }
            .labelsHidden()
            .fixedSize()
            Picker("Estilo", selection: $emoji.colorful) {
                Text("Contorno").tag(false)
                Text("Color").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help("El contorno negro es lo que mejor se imprime en papel térmico")
        case .images:
            @Bindable var images = model.images
            Picker("Tipo", selection: $images.category) {
                ForEach(Openverse.Category.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        case .fonts:
            @Bindable var fonts = model.fonts
            Picker("Estilo", selection: $fonts.category) {
                ForEach(GoogleFonts.Category.allCases) { Text($0.title).tag($0) }
            }
            .labelsHidden()
            .fixedSize()
            Picker("Mostrar", selection: $fonts.showInstalled) {
                Text("Catálogo").tag(false)
                Text(fonts.installed.isEmpty ? "Instaladas" : "Instaladas (\(fonts.installed.count))").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        case .library:
            @Bindable var saved = model.saved
            Picker("Tipo", selection: $saved.kind) {
                Text("Todo").tag(ResourceKind?.none)
                ForEach(ResourceKind.allCases, id: \.self) { Text($0.title).tag(Optional($0)) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
    }
}

struct IconFilters: View {
    @Bindable var icons: IconsModel

    var body: some View {
        Menu {
            Button { icons.prefix = nil } label: { checkLabel("Todas las colecciones", selected: icons.prefix == nil) }
            let recommended = icons.recommendedCollections
            if !recommended.isEmpty {
                Section(icons.colorful ? "Colecciones a color" : "Recomendadas para imprimir") {
                    ForEach(recommended, id: \.prefix) { set in
                        Button { icons.prefix = set.prefix } label: {
                            checkLabel("\(set.info.name)  ·  \(set.info.total ?? 0)", selected: icons.prefix == set.prefix)
                        }
                    }
                }
            }
            let others = icons.otherCollections
            if !others.isEmpty {
                Menu("Más colecciones") {
                    ForEach(others, id: \.category) { group in
                        Menu(Self.categoryTitle(group.category)) {
                            ForEach(group.sets, id: \.prefix) { set in
                                Button { icons.prefix = set.prefix } label: {
                                    checkLabel("\(set.info.name)  ·  \(set.info.total ?? 0)", selected: icons.prefix == set.prefix)
                                }
                            }
                        }
                    }
                }
            }
        } label: {
            Label(icons.prefix.map { icons.collections[$0]?.name ?? $0 } ?? "Todas las colecciones", systemImage: "square.stack.3d.up")
        }
        .fixedSize()
        .help("Filtrá por colección de íconos")

        Picker("Estilo", selection: $icons.colorful) {
            Text("Monocromo").tag(false)
            Text("Color").tag(true)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .help("Los íconos monocromos son los que mejor se imprimen")
    }

    @ViewBuilder
    private func checkLabel(_ title: String, selected: Bool) -> some View {
        if selected { Label(title, systemImage: "checkmark") } else { Text(title) }
    }

    static func categoryTitle(_ category: String) -> String {
        let titles = ["UI 24px": "Interfaz 24 px", "UI 16px / 32px": "Interfaz 16 / 32 px",
                      "UI Other / Mixed Grid": "Interfaz (otras)", "UI Multicolor": "Interfaz multicolor",
                      "Material": "Material", "Logos": "Logos", "Emoji": "Emoji", "Flags / Maps": "Banderas y mapas",
                      "Thematic": "Temáticas", "Programming": "Programación",
                      "Archive / Unmaintained": "Archivo (sin mantenimiento)", "Otros": "Otras"]
        return titles[category] ?? category
    }
}

// MARK: Content

struct StoreContent: View {
    @Bindable var model: StoreModel

    var body: some View {
        switch model.tab {
        case .icons:
            @Bindable var icons = model.icons
            ResourceGridArea(model: model, heading: icons.heading, count: countText(icons.items.count, total: icons.total, noun: "íconos"),
                             items: icons.items, phase: icons.phase, selection: $icons.selection,
                             retry: { icons.refresh() }, canLoadMore: icons.canLoadMore, loadingMore: icons.loadingMore,
                             loadMore: { icons.loadMore() })
        case .emoji:
            @Bindable var emoji = model.emoji
            ResourceGridArea(model: model, heading: emoji.heading, count: countText(emoji.items.count, total: nil, noun: "emojis"),
                             items: emoji.items, phase: emoji.phase, selection: $emoji.selection,
                             retry: { Task { await emoji.loadCatalog() } })
        case .images:
            @Bindable var images = model.images
            ResourceGridArea(model: model, heading: images.heading,
                             count: countText(images.items.count, total: images.resultCount, noun: "imágenes"),
                             items: images.items, phase: images.phase, selection: $images.selection,
                             retry: { images.refresh() }, canLoadMore: images.canLoadMore, loadingMore: images.loadingMore,
                             loadMore: { images.loadMore() }) {
                ImageSearchWelcome(images: images)
            }
        case .fonts:
            FontList(fonts: model.fonts)
        case .library:
            @Bindable var saved = model.saved
            let items = saved.items
            ResourceGridArea(model: model, heading: saved.kind.map { "Guardados · \($0.title)" } ?? "Guardados",
                             count: countText(items.count, total: nil, noun: items.count == 1 ? "recurso" : "recursos"),
                             items: items, phase: .loaded, selection: $saved.selection, retry: {}) {
                EmptyView()
            } noResults: {
                if model.library.resources.isEmpty {
                    ContentUnavailableView {
                        Label("Todavía no guardaste recursos", systemImage: "heart")
                    } description: {
                        Text("Tocá ♡ en cualquier ícono, emoji o imagen para guardarlo acá. Vas a poder usarlo también sin conexión.")
                    }
                } else {
                    ContentUnavailableView.search(text: saved.query)
                }
            }
        }
    }

    private func countText(_ shown: Int, total: Int?, noun: String) -> String? {
        guard shown > 0 else { return nil }
        if let total, total > shown { return "\(shown.formatted()) de \(total.formatted()) \(noun)" }
        return "\(shown.formatted()) \(noun)"
    }
}

// MARK: Detail

struct StoreDetail: View {
    @Bindable var model: StoreModel
    let onUse: (CGImage, ResourceInfo, ResourceDestination) -> Void

    var body: some View {
        switch model.tab {
        case .icons: itemDetail(model.icons.selection)
        case .emoji: itemDetail(model.emoji.selection)
        case .images: itemDetail(model.images.selection)
        case .library: itemDetail(model.saved.selection)
        case .fonts:
            if let family = model.fonts.selection {
                FontDetail(family: family, fonts: model.fonts, thermal: model.thermal).id(family.id)
            } else {
                DetailPlaceholder(icon: "textformat",
                                  title: "Elegí una fuente",
                                  message: "Instalala para usarla en textos, notas, etiquetas y banners. Las fuentes de Google Fonts son libres.")
            }
        }
    }

    @ViewBuilder
    private func itemDetail(_ item: ResourceItem?) -> some View {
        if let item {
            ResourceDetail(item: item, model: model, onUse: onUse).id(item.id)
        } else {
            DetailPlaceholder(icon: "hand.tap",
                              title: "Elegí un recurso",
                              message: "Vas a ver su licencia y las opciones para usarlo en una foto, un sticker o una etiqueta.")
        }
    }
}

struct DetailPlaceholder: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.tertiary)
            Text(title).font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: Footer

struct StoreFooter: View {
    let model: StoreModel

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: sourceIcon).foregroundStyle(.secondary)
            Text(sourceText)
            Spacer()
            Text("Revisá la licencia de cada recurso antes de compartir lo que imprimas.")
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .lineLimit(1)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private var sourceIcon: String {
        model.tab == .library ? "internaldrive" : "globe"
    }

    private var sourceText: String {
        switch model.tab {
        case .icons: "Íconos de Iconify (api.iconify.design), cada colección con su licencia"
        case .emoji: "Emojis de OpenMoji · CC BY-SA 4.0"
        case .images: "Imágenes de Openverse con licencias Creative Commons"
        case .fonts: "Fuentes de Google Fonts · licencias libres"
        case .library: "Guardados en tu Mac, disponibles sin conexión"
        }
    }
}
