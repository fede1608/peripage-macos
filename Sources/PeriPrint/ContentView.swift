import PeriPageKit
import PeriRender
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @State private var showImporter = false

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(selection: Binding(get: { model.mode }, set: { if let m = $0 { model.mode = m } })) {
                ForEach(Mode.sections, id: \.title) { section in
                    Section(section.title) {
                        ForEach(section.modes) { mode in
                            Label(mode.title, systemImage: mode.icon).tag(mode)
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 210, ideal: 230)
            .safeAreaInset(edge: .bottom) { PrinterPanel().padding(10) }
        } detail: {
            HStack(spacing: 0) {
                EditorColumn(showImporter: $showImporter)
                    .frame(width: 370)
                Divider()
                PreviewPane(showImporter: $showImporter)
            }
        }
        .navigationTitle(model.mode.title)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { openWindow(id: "store") } label: { Label("Tienda", systemImage: "bag").labelStyle(.titleAndIcon) }
                    .help("Íconos, emojis, imágenes y fuentes gratis (⇧⌘T)")
                if model.mode.usesImage || model.mode == .label || model.mode == .collage {
                    Button { showImporter = true } label: { Label("Abrir imagen", systemImage: "photo.badge.plus") }
                        .help("Abrir imagen (⌘O)")
                }
                PrintButton()
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.image], allowsMultipleSelection: model.mode == .collage) { result in
            if case .success(let urls) = result {
                for url in urls {
                    let scoped = url.startAccessingSecurityScopedResource()
                    model.loadImage(from: url)
                    if scoped { url.stopAccessingSecurityScopedResource() }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openImage)) { _ in showImporter = true }
        .onReceive(NotificationCenter.default.publisher(for: .openStore)) { _ in openWindow(id: "store") }
        .task {
            #if DEBUG
            if DebugSnapshot.directory != nil { await DebugSnapshot.run(model: model); return }
            #endif
            await model.startBluetooth()
        }
        .alert("PeriPrint", isPresented: Binding(get: { model.lastMessage != nil }, set: { if !$0 { model.lastMessage = nil } })) {
            Button("OK") { model.lastMessage = nil }
        } message: {
            Text(model.lastMessage ?? "")
        }
    }
}

struct PrintButton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Button {
            Task { await model.print() }
        } label: {
            if model.isPrinting {
                HStack(spacing: 6) {
                    ProgressView(value: model.printProgress).progressViewStyle(.circular).controlSize(.small)
                    Text("Imprimiendo…")
                }
            } else {
                Label(model.mode == .history ? "Reimprimir" : "Imprimir", systemImage: "printer.fill").labelStyle(.titleAndIcon)
            }
        }
        .buttonStyle(.borderedProminent)
        .disabled(model.isPrinting || model.preview == nil)
        .help("Imprimir (⌘P)")
    }
}

struct EditorColumn: View {
    @Environment(AppModel.self) private var model
    @Binding var showImporter: Bool

    var body: some View {
        Form {
            if model.mode.hasPresets { PresetSection() }
            switch model.mode {
            case .photo: PhotoEditor(showImporter: $showImporter)
            case .collage: CollageEditor(showImporter: $showImporter)
            case .sticker: StickerEditor(showImporter: $showImporter)
            case .label: LabelEditor(showImporter: $showImporter)
            case .text: TextDocEditor()
            case .banner: BannerEditor()
            case .qr: QREditor()
            case .social: SocialModeEditor()
            case .games: GamesEditor()
            case .history: HistoryEditor()
            }
            if model.mode != .history { PrintSettingsSection() }
        }
        .formStyle(.grouped)
    }
}

struct PreviewPane: View {
    @Environment(AppModel.self) private var model
    @Binding var showImporter: Bool
    @State private var zoom: Double = 1
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Color(nsColor: .underPageBackgroundColor)
                if let preview = model.preview, preview.height > 0, let cg = preview.cgImage(paper: 255, ink: 28) {
                    GeometryReader { geo in
                        let m = model.model
                        let paperW = CGFloat(m.dots(forMM: 56))
                        let fit = min(2.5, max(0.25, (geo.size.width - 60) / paperW))
                        let scale = fit * zoom
                        let side: CGFloat = (paperW - CGFloat(preview.width)) * 0.5 * scale
                        let top = CGFloat(model.printsOnLabels ? 0 : m.dots(forMM: m.topMarginMM)) * scale
                        let bottom = CGFloat(model.printsOnLabels ? 0 : m.dots(forMM: model.settings.bottomMarginMM)) * scale
                        ScrollView([.vertical, .horizontal]) {
                            Image(decorative: cg, scale: 1)
                                .resizable()
                                .interpolation(.none)
                                .frame(width: CGFloat(preview.width) * scale, height: CGFloat(preview.height) * scale)
                                .overlay(alignment: .topLeading) {
                                    ForEach(Array(model.previewGaps.enumerated()), id: \.offset) { _, gap in
                                        Rectangle()
                                            .fill(Color(white: 0.86))
                                            .frame(width: paperW * scale, height: CGFloat(gap.count) * scale)
                                            .offset(x: -side, y: CGFloat(gap.lowerBound) * scale)
                                            .allowsHitTesting(false)
                                    }
                                }
                                .padding(.top, top)
                                .padding(.bottom, bottom)
                                .padding(.horizontal, side)
                                .background(Color.white)
                                .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
                                .padding(.vertical, 30)
                                .padding(.horizontal, 24)
                                .frame(minWidth: geo.size.width)
                        }
                    }
                } else {
                    EmptyPreview(showImporter: $showImporter)
                }
                if model.isRendering {
                    ProgressView().controlSize(.small).padding(10)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }
            }
            .overlay {
                if isTargeted {
                    RoundedRectangle(cornerRadius: 12).stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8]))
                        .padding(8)
                }
            }
            .onDrop(of: [.fileURL, .image], isTargeted: $isTargeted) { providers in handleDrop(providers) }
            Divider()
            HStack {
                if let p = model.preview, p.height > 0 {
                    let m = model.model
                    let paperMM = m.mm(forDots: p.height) + (model.printsOnLabels ? 0 : m.topMarginMM + model.settings.bottomMarginMM)
                    Text("\(Int(m.widthMM.rounded())) × \(String(format: "%.0f", m.mm(forDots: p.height))) mm")
                        .monospacedDigit()
                        .help("\(p.width)×\(p.height) px · \(m.family.rawValue)")
                    Text(model.printsOnLabels
                         ? "· \(model.mode == .label ? Renderer.labelEntries(model.label).count : 1) etiquetas"
                         : "· papel \(String(format: "%.0f", paperMM)) mm" + (model.settings.copies > 1 ? " · \(model.settings.copies) copias" : ""))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "minus.magnifyingglass").foregroundStyle(.secondary)
                Slider(value: $zoom, in: 0.5...4).frame(width: 120)
                Image(systemName: "plus.magnifyingglass").foregroundStyle(.secondary)
            }
            .font(.callout)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        if model.mode == .collage, providers.count > 1 {
            for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in model.loadImage(from: url) }
                }
            }
            return true
        }
        guard let provider = providers.first else { return false }
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in model.loadImage(from: url) }
            }
            return true
        }
        if provider.canLoadObject(ofClass: NSImage.self) {
            _ = provider.loadObject(ofClass: NSImage.self) { image, _ in
                guard let image = image as? NSImage else { return }
                Task { @MainActor in model.loadImage(image, name: "Imagen arrastrada") }
            }
            return true
        }
        return false
    }
}

struct EmptyPreview: View {
    @Environment(AppModel.self) private var model
    @Binding var showImporter: Bool

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: model.mode.usesImage ? "photo.on.rectangle.angled" : model.mode.icon)
                .font(.system(size: 46, weight: .light))
                .foregroundStyle(.secondary)
            switch model.mode {
            case .collage:
                Text("Arrastrá varias fotos acá").font(.title3)
                Text("Hasta \(AppModel.maxCollageImages), en el orden en que las agregues").foregroundStyle(.secondary)
                Button("Elegir fotos…") { showImporter = true }
            case .photo, .sticker:
                Text("Arrastrá una imagen acá").font(.title3)
                Text("o pegala con ⇧⌘V").foregroundStyle(.secondary)
                Button("Elegir imagen…") { showImporter = true }
            case .social:
                Text("Pegá el link de un post o capturá uno").font(.title3)
                Text("Públicos, o privados e historias con tu sesión iniciada").foregroundStyle(.secondary)
            case .history:
                Text("Elegí una impresión de la lista").foregroundStyle(.secondary)
            default:
                Text("Escribí algo para ver la vista previa").foregroundStyle(.secondary)
            }
        }
    }
}
