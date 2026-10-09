import AppKit
import SwiftUI

/// Lazy grid of white tiles with loading, error and empty states.
struct ResourceGridArea<Idle: View, NoResults: View>: View {
    let model: StoreModel
    let heading: String
    let count: String?
    let items: [ResourceItem]
    let phase: LoadPhase
    @Binding var selection: ResourceItem?
    let retry: () -> Void
    var canLoadMore = false
    var loadingMore = false
    var loadMore: () -> Void = {}
    @ViewBuilder var idle: () -> Idle
    @ViewBuilder var noResults: () -> NoResults

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            switch phase {
            case .idle:
                idle()
            case .failed(let message):
                ContentUnavailableView {
                    Label("No se pudo cargar", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(message)
                } actions: {
                    Button("Reintentar", action: retry)
                }
            case .loading where items.isEmpty:
                VStack(spacing: 10) {
                    ProgressView().controlSize(.regular)
                    Text("Buscando…").foregroundStyle(.secondary)
                }
            case .loaded where items.isEmpty:
                noResults()
            default:
                grid
            }
        }
    }

    private var grid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(heading).font(.headline).lineLimit(1)
                    if phase == .loading { ProgressView().controlSize(.mini) }
                    Spacer()
                    if let count { Text(count).font(.callout).foregroundStyle(.secondary).monospacedDigit() }
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96, maximum: 128), spacing: 12)], spacing: 12) {
                    ForEach(items) { item in
                        ResourceTile(item: item, thermal: model.thermal, selected: selection?.id == item.id,
                                     favorite: !item.source.isFile && model.library.contains(item.favoriteKey),
                                     loader: model.loader)
                            .onTapGesture { selection = item }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("\(item.title), \(item.info.source)")
                            .accessibilityAddTraits(selection?.id == item.id ? [.isButton, .isSelected] : .isButton)
                            .accessibilityAction { selection = item }
                    }
                }
                if canLoadMore || loadingMore {
                    HStack {
                        Spacer()
                        if loadingMore {
                            ProgressView().controlSize(.small)
                        } else {
                            Button("Mostrar más", action: loadMore)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
            }
            .padding(16)
            .opacity(phase == .loading ? 0.55 : 1)
        }
    }
}

extension ResourceGridArea where NoResults == NoResultsView {
    init(model: StoreModel, heading: String, count: String?, items: [ResourceItem], phase: LoadPhase,
         selection: Binding<ResourceItem?>, retry: @escaping () -> Void, canLoadMore: Bool = false,
         loadingMore: Bool = false, loadMore: @escaping () -> Void = {}, @ViewBuilder idle: @escaping () -> Idle) {
        self.init(model: model, heading: heading, count: count, items: items, phase: phase, selection: selection,
                  retry: retry, canLoadMore: canLoadMore, loadingMore: loadingMore, loadMore: loadMore,
                  idle: idle, noResults: { NoResultsView() })
    }
}

extension ResourceGridArea where Idle == EmptyView, NoResults == NoResultsView {
    init(model: StoreModel, heading: String, count: String?, items: [ResourceItem], phase: LoadPhase,
         selection: Binding<ResourceItem?>, retry: @escaping () -> Void, canLoadMore: Bool = false,
         loadingMore: Bool = false, loadMore: @escaping () -> Void = {}) {
        self.init(model: model, heading: heading, count: count, items: items, phase: phase, selection: selection,
                  retry: retry, canLoadMore: canLoadMore, loadingMore: loadingMore, loadMore: loadMore,
                  idle: { EmptyView() }, noResults: { NoResultsView() })
    }
}

struct NoResultsView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Sin resultados", systemImage: "magnifyingglass")
        } description: {
            Text("Probá con otra palabra, en español o en inglés.")
        }
    }
}

struct ResourceTile: View {
    let item: ResourceItem
    let thermal: Bool
    let selected: Bool
    let favorite: Bool
    let loader: ImageLoader

    @State private var image: CGImage?
    @State private var failed = false

    private struct LoadKey: Hashable {
        let id: String
        let thermal: Bool
    }

    var body: some View {
        VStack(spacing: 6) {
            Color.white
                .aspectRatio(1, contentMode: .fit)
                .overlay { artwork }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(selected ? Color.accentColor : Color.black.opacity(0.1), lineWidth: selected ? 3 : 0.5)
                }
                .overlay(alignment: .topTrailing) {
                    if favorite {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(4)
                            .background(Circle().fill(Color.pink))
                            .padding(6)
                    }
                }
                .shadow(color: .black.opacity(selected ? 0.18 : 0.08), radius: selected ? 5 : 2, y: 1)
            Text(item.title)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(selected ? .primary : .secondary)
                .frame(maxWidth: .infinity)
        }
        .contentShape(Rectangle())
        .help("\(item.title) · \(item.info.source)")
        .task(id: LoadKey(id: item.id, thermal: thermal)) { await load() }
    }

    @ViewBuilder
    private var artwork: some View {
        if let image {
            if item.kind == .image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(thermal ? .none : .high)
                    .scaledToFill()
            } else {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(thermal ? .none : .high)
                    .scaledToFit()
                    .padding(14)
            }
        } else if failed {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(Color.black.opacity(0.35))
        } else {
            ProgressView().controlSize(.small)
        }
    }

    private func load() async {
        failed = false
        do {
            let thumb = try await loader.thumbnail(item, maxPixel: item.kind == .image ? 360 : 256)
            if thermal {
                // About the size it would print as a small sticker.
                image = await loader.thermal(item, from: thumb, width: item.kind == .image ? 240 : 160) ?? thumb
            } else {
                image = thumb
            }
        } catch is CancellationError {
        } catch {
            if !Task.isCancelled { failed = true }
        }
    }
}

/// Native NSSearchField (magnifier, clear button) bound to a string.
struct SearchField: NSViewRepresentable {
    @Binding var text: String
    var prompt: String

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = prompt
        field.delegate = context.coordinator
        field.target = context.coordinator
        field.action = #selector(Coordinator.changed(_:))
        field.sendsWholeSearchString = false
        field.sendsSearchStringImmediately = true
        field.controlSize = .large
        field.font = .systemFont(ofSize: NSFont.systemFontSize(for: .large))
        field.stringValue = text
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
        if field.placeholderString != prompt { field.placeholderString = prompt }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: SearchField

        init(parent: SearchField) { self.parent = parent }

        @objc func changed(_ sender: NSSearchField) {
            if parent.text != sender.stringValue { parent.text = sender.stringValue }
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            changed(field)
        }
    }
}

/// Wrapping row layout for suggestion chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let width = rows.map { $0.width }.max() ?? 0
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX + (bounds.width - row.width) / 2
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [(indices: [Int], width: CGFloat, height: CGFloat)] {
        var rows: [(indices: [Int], width: CGFloat, height: CGFloat)] = []
        var current: (indices: [Int], width: CGFloat, height: CGFloat) = ([], 0, 0)
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.indices.isEmpty {
                rows.append(current)
                current = ([index], size.width, size.height)
            } else {
                current = (current.indices + [index], needed, max(current.height, size.height))
            }
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}

struct ImageSearchWelcome: View {
    let images: ImagesModel

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
            Text("Fotos e ilustraciones libres").font(.title3.weight(.semibold))
            Text("Buscá entre millones de imágenes con licencia Creative Commons de Openverse.\nPodés escribir en español o en inglés.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            FlowLayout(spacing: 8) {
                ForEach(ImagesModel.suggestions, id: \.self) { word in
                    Button(word) { images.search(word) }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                }
            }
            .frame(maxWidth: 420)
            .padding(.top, 4)
        }
        .padding(30)
    }
}
