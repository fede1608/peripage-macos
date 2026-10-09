import AppKit
import PeriPageKit
import SwiftUI

/// Right-hand panel: large preview, license and attribution, favorite and the "Usar en…" buttons.
struct ResourceDetail: View {
    let item: ResourceItem
    let model: StoreModel
    let onUse: (CGImage, ResourceInfo, ResourceDestination) -> Void

    @State private var preview: CGImage?
    @State private var full: CGImage?
    @State private var thermalImage: CGImage?
    @State private var transparent = false
    @State private var loadingFull = true
    @State private var copied = false

    /// Printable width of the A6 in dots.
    private static let printWidth = 384

    private struct ThermalKey: Hashable {
        let thermal: Bool
        let fullLoaded: Bool
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    previewBox
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.title3.weight(.semibold))
                                .lineLimit(3)
                                .textSelection(.enabled)
                            Text(item.info.source)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 4)
                        favoriteButton
                    }
                    facts
                    if let attribution = item.info.attribution { attributionBox(attribution) }
                }
                .padding(16)
            }
            Divider()
            useButtons
        }
        .task {
            model.actionError = nil
            // Thumbnail first (instant from cache), then the full image.
            if preview == nil { preview = try? await model.loader.thumbnail(item, maxPixel: item.kind == .image ? 360 : 512) }
            do {
                let image = try await model.loader.full(item)
                full = image
                preview = image
                transparent = await Task.detached { ImageDecoder.hasTransparency(image) }.value
            } catch {}
            loadingFull = false
        }
        .task(id: ThermalKey(thermal: model.thermal, fullLoaded: full != nil)) {
            guard model.thermal, let source = full ?? preview else { thermalImage = nil; return }
            thermalImage = await model.loader.thermal(item, from: source, width: Self.printWidth)
        }
    }

    // MARK: Preview

    private var previewBox: some View {
        let shown = model.thermal ? thermalImage : preview
        return Color.white
            .frame(height: previewHeight)
            .overlay {
                if let shown {
                    Image(decorative: shown, scale: 1)
                        .resizable()
                        .interpolation(model.thermal ? .none : .high)
                        .scaledToFit()
                        .padding(item.kind == .image ? 10 : 24)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if model.thermal, thermalImage != nil {
                    Text("Vista térmica · 48 mm de ancho")
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.black.opacity(0.75)))
                        .foregroundStyle(.white)
                        .padding(8)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.black.opacity(0.1), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.1), radius: 4, y: 1)
    }

    /// Wide images get a shorter card so the license and attribution stay visible.
    private var previewHeight: CGFloat {
        let size = (preview ?? full).map { CGSize(width: $0.width, height: $0.height) } ?? item.pixelSize
        guard let size, size.width > 0, size.height > 0 else { return 210 }
        let aspect = size.width / size.height
        return min(210, max(140, 248 / aspect + 20))
    }

    // MARK: Facts

    private var facts: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 6) {
            GridRow {
                Text("Licencia").foregroundStyle(.secondary)
                if let url = item.licenseURL {
                    Link(item.info.license, destination: url).lineLimit(2)
                } else {
                    Text(item.info.license).lineLimit(2)
                }
            }
            GridRow {
                Text("Imagen").foregroundStyle(.secondary)
                if let full {
                    Text("\(full.width) × \(full.height) px · \(transparent ? "fondo transparente" : "fondo opaco")")
                        .monospacedDigit()
                        .help(transparent ? "Ideal para stickers con contorno" : "")
                } else if loadingFull {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text(item.kind == .image ? "Descargando original…" : "Preparando…").foregroundStyle(.secondary)
                    }
                } else {
                    Text("Solo vista previa").foregroundStyle(.secondary)
                }
            }
            if let page = item.pageURL {
                GridRow {
                    Text("Origen").foregroundStyle(.secondary)
                    Link("Ver en el sitio original", destination: page)
                }
            }
        }
        .font(.callout)
    }

    private func attributionBox(_ attribution: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Atribución requerida", systemImage: "quote.bubble").font(.caption.weight(.semibold))
                    .help("La licencia pide mencionar al autor si compartís lo que imprimas")
                Spacer()
                Button(copied ? "Copiada" : "Copiar") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(attribution, forType: .string)
                    copied = true
                }
                .buttonStyle(.link)
                .font(.caption)
            }
            Text(attribution)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.05)))
    }

    private var favoriteButton: some View {
        let isFavorite = model.library.contains(item.favoriteKey)
        let saving = model.isBusy(item, "favorite")
        return Button {
            Task { await model.toggleFavorite(item) }
        } label: {
            ZStack {
                Circle().fill(isFavorite ? Color.pink.opacity(0.14) : Color.primary.opacity(0.06))
                if saving {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(isFavorite ? Color.pink : Color.secondary)
                }
            }
            .frame(width: 32, height: 32)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(saving)
        .help(isFavorite ? "Quitar de Mis recursos" : "Guardar en Mis recursos para usarlo sin conexión")
        .accessibilityLabel(isFavorite ? "Quitar de Mis recursos" : "Guardar en Mis recursos")
    }

    // MARK: Use

    private var recommended: ResourceDestination { item.kind == .image ? .photo : .sticker }

    private var useButtons: some View {
        VStack(spacing: 7) {
            ForEach(ResourceDestination.allCases, id: \.self) { destination in
                let busy = model.isBusy(item, destination.rawValue)
                let button = Button {
                    Task { await model.use(item, as: destination, onUse: onUse) }
                } label: {
                    HStack(spacing: 7) {
                        if busy {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: destination.icon)
                        }
                        Text(destination.buttonTitle)
                    }
                    .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .disabled(busy)
                if destination == recommended {
                    button.buttonStyle(.borderedProminent)
                } else {
                    button.buttonStyle(.bordered)
                }
            }
            if let error = model.actionError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
    }
}

extension ResourceItem.Source {
    var isFile: Bool {
        if case .file = self { return true }
        return false
    }
}
