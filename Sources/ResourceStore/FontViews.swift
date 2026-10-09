import AppKit
import CoreText
import PeriPageKit
import PeriRender
import SwiftUI

struct FontList: View {
    @Bindable var fonts: FontsModel

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            if fonts.showInstalled && fonts.installed.isEmpty {
                ContentUnavailableView {
                    Label("Todavía no instalaste fuentes", systemImage: "textformat")
                } description: {
                    Text("Elegí una del catálogo y tocá “Instalar fuente”. Va a aparecer en todos los editores de texto de PeriPrint.")
                } actions: {
                    Button("Ver catálogo") { fonts.showInstalled = false }
                }
            } else if !fonts.showInstalled, case .failed(let message) = fonts.phase {
                ContentUnavailableView {
                    Label("No se pudo cargar el catálogo", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(message)
                } actions: {
                    Button("Reintentar") { Task { await fonts.loadMetadata() } }
                }
            } else if !fonts.showInstalled, fonts.families.isEmpty {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Cargando catálogo de Google Fonts…").foregroundStyle(.secondary)
                }
            } else if fonts.rows.isEmpty {
                NoResultsView()
            } else {
                list
            }
        }
    }

    private var list: some View {
        let selection = Binding<String?>(
            get: { fonts.selection?.id },
            set: { id in fonts.selection = fonts.rows.first { $0.id == id } }
        )
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(fonts.showInstalled ? "Fuentes instaladas" : "Más populares primero").font(.headline)
                Spacer()
                Text("\(fonts.rows.count.formatted()) fuentes").font(.callout).foregroundStyle(.secondary).monospacedDigit()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)
            List(fonts.rows, selection: selection) { family in
                FontRow(family: family, installed: fonts.installed.first { $0.folderName == family.family })
                    .tag(family.id)
                    .listRowSeparator(.hidden)
            }
            .listStyle(.inset(alternatesRowBackgrounds: false))
            .scrollContentBackground(.hidden)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5))
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
    }
}

struct FontRow: View {
    let family: GoogleFontFamily
    let installed: FontLibrary.Installed?

    @State private var font: NSFont?

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(family.family)
                    .font(font.map { Font($0) } ?? .system(size: 21, weight: .light))
                    .foregroundStyle(font == nil ? .tertiary : .primary)
                    .lineLimit(1)
                    .frame(height: 30, alignment: .leading)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if installed != nil {
                Label("Instalada", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
        .padding(.vertical, 4)
        .task(id: family.family) { await loadFont() }
    }

    private var subtitle: String {
        var parts = [family.categoryTitle].filter { !$0.isEmpty }
        if let designer = family.designers.first { parts.append(family.designers.count > 1 ? "\(designer) y otros" : designer) }
        let count = family.styles.count
        if count > 0 { parts.append(count == 1 ? "1 estilo" : "\(count) estilos") }
        return parts.joined(separator: " · ")
    }

    private func loadFont() async {
        if let installed, let registered = NSFontManager.shared.font(withFamily: installed.family, traits: [], weight: 5, size: 22) {
            font = registered
            return
        }
        if let descriptor = try? await FontPreviewLoader.shared.subset(family, text: family.family) {
            font = FontPreviewLoader.font(descriptor, size: 22)
        }
    }
}

struct FontDetail: View {
    let family: GoogleFontFamily
    let fonts: FontsModel
    let thermal: Bool

    @State private var descriptor: CTFontDescriptor?
    @State private var failure: String?
    @State private var thermalSample: CGImage?

    static let headline = "¡Hola, PeriPrint!"
    static let sample = "Ñandú, pingüino y cigüeña\nAa Bb Cc Dd 0123456789"

    private struct SampleKey: Hashable {
        let thermal: Bool
        let loaded: Bool
    }

    var body: some View {
        let installed = fonts.isInstalled(family)
        let installing = fonts.installing.contains(family.family)
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    previewCard
                    VStack(alignment: .leading, spacing: 3) {
                        Text(family.family).font(.title3.weight(.semibold)).textSelection(.enabled)
                        Text("Google Fonts · \(family.categoryTitle)").foregroundStyle(.secondary)
                    }
                    Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 6) {
                        if !family.designers.isEmpty {
                            GridRow {
                                Text("Diseño").foregroundStyle(.secondary)
                                Text(family.designers.joined(separator: ", ")).lineLimit(3)
                            }
                        }
                        GridRow {
                            Text("Se instala").foregroundStyle(.secondary)
                            Text(family.boldWeight != nil ? "Regular y negrita" : "Regular")
                        }
                        GridRow {
                            Text("Licencia").foregroundStyle(.secondary)
                            Text(GoogleFonts.license)
                        }
                    }
                    .font(.callout)
                    if installed {
                        Label("Instalada. Ya la podés elegir en Texto, Etiqueta y Banner.", systemImage: "checkmark.circle.fill")
                            .font(.callout)
                            .foregroundStyle(.green)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(16)
            }
            Divider()
            VStack(spacing: 8) {
                if installed {
                    Button(role: .destructive) {
                        fonts.remove(family)
                    } label: {
                        Label("Quitar fuente", systemImage: "trash").frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                } else {
                    Button {
                        Task { await fonts.install(family) }
                    } label: {
                        HStack(spacing: 7) {
                            if installing { ProgressView().controlSize(.small) } else { Image(systemName: "arrow.down.circle") }
                            Text(installing ? "Instalando…" : "Instalar fuente")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(installing)
                }
                if let error = fonts.errorMessage {
                    Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
        }
        .task { await loadDescriptor() }
        .task(id: SampleKey(thermal: thermal, loaded: descriptor != nil)) { await renderThermal() }
    }

    private var previewCard: some View {
        Color.white
            .frame(height: 250)
            .overlay {
                if thermal, let thermalSample {
                    Image(decorative: thermalSample, scale: 1)
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                        .padding(12)
                } else if let descriptor {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Aa").font(Font(FontPreviewLoader.font(descriptor, size: 64)))
                        Text(Self.headline).font(Font(FontPreviewLoader.font(descriptor, size: 22)))
                        Text(Self.sample).font(Font(FontPreviewLoader.font(descriptor, size: 15)))
                    }
                    .foregroundStyle(.black)
                    .lineLimit(2)
                    .minimumScaleFactor(0.5)
                    .padding(16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                } else if let failure {
                    Text(failure).font(.caption).foregroundStyle(Color.black.opacity(0.5)).multilineTextAlignment(.center).padding()
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if thermal, thermalSample != nil {
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

    private func loadDescriptor() async {
        if let installed = fonts.installed.first(where: { $0.folderName == family.family }),
           let font = NSFontManager.shared.font(withFamily: installed.family, traits: [], weight: 5, size: 20) {
            descriptor = font.fontDescriptor as CTFontDescriptor
            return
        }
        do {
            descriptor = try await FontPreviewLoader.shared.regular(family)
        } catch is CancellationError {
        } catch {
            failure = StoreError.message(for: error)
        }
    }

    private func renderThermal() async {
        guard thermal, let descriptor else { thermalSample = nil; return }
        let headline = Self.headline, sample = Self.sample
        thermalSample = await Task.detached(priority: .userInitiated) { () -> CGImage? in
            let width = 384
            let big = TextRenderer.render(headline, font: FontPreviewLoader.font(descriptor, size: 46), align: .center, width: width)
            let small = TextRenderer.render(sample, font: FontPreviewLoader.font(descriptor, size: 26), align: .center, width: width)
            return MonoBitmap.stack([big, small], width: width, spacing: 14).padded(top: 12, bottom: 12).cgImage(paper: 255, ink: 28)
        }.value
    }
}
