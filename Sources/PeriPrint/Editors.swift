import AppKit
import PeriPageKit
import PeriRender
import PuzzleKit
import ResourceStore
import SocialKit
import SwiftUI

// MARK: Presets

struct PresetSection: View {
    @Environment(AppModel.self) private var model
    @State private var naming = false
    @State private var newName = ""

    var body: some View {
        Section {
            HStack {
                Menu {
                    let builtIns = model.presetsForMode.filter(\.builtIn)
                    let mine = model.presetsForMode.filter { !$0.builtIn }
                    Section("Incluidos") {
                        ForEach(builtIns) { p in Button(p.name) { model.apply(p) } }
                    }
                    if !mine.isEmpty {
                        Section("Mis presets") {
                            ForEach(mine) { p in Button(p.name) { model.apply(p) } }
                        }
                    }
                } label: {
                    Label(currentName, systemImage: "slider.horizontal.3")
                }
                .menuStyle(.borderlessButton)

                Spacer()
                Button { newName = ""; naming = true } label: { Image(systemName: "plus") }
                    .help("Guardar la configuración actual como preset")
                if let p = selectedUserPreset {
                    Button(role: .destructive) { model.deletePreset(p) } label: { Image(systemName: "trash") }
                        .help("Borrar “\(p.name)”")
                }
            }
        } header: {
            Text("Preset")
        }
        .alert("Guardar preset", isPresented: $naming) {
            TextField("Nombre", text: $newName)
            Button("Guardar") {
                let name = newName.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { model.saveCurrentAsPreset(named: name) }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Guarda los ajustes de \(model.mode.title.lowercased()) y de impresión.")
        }
    }

    private var currentName: String {
        model.presetsForMode.first { $0.id == model.selectedPresetID }?.name ?? "Elegir preset…"
    }

    private var selectedUserPreset: Preset? {
        model.userPresets.first { $0.id == model.selectedPresetID && $0.mode == model.mode }
    }
}

// MARK: Shared pieces

struct ImageSourceSection: View {
    @Environment(AppModel.self) private var model
    @Binding var showImporter: Bool

    var body: some View {
        Section("Imagen") {
            HStack {
                if let image = model.image {
                    Image(decorative: image, scale: 1).resizable().scaledToFit()
                        .frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 6))
                    Text(model.imageName ?? "Imagen").lineLimit(1).truncationMode(.middle)
                } else {
                    Text("Ninguna").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Elegir…") { showImporter = true }
                Button { _ = model.pasteImage() } label: { Image(systemName: "doc.on.clipboard") }
                    .help("Pegar imagen del portapapeles (⇧⌘V)")
            }
        }
    }
}

struct TransformControls: View {
    @Binding var transform: ImageTransform

    var body: some View {
        HStack {
            Text("Orientación")
            Spacer()
            Button { transform.rotation = transform.rotation.rotatedClockwise() } label: {
                Image(systemName: "rotate.right")
            }
            .help("Rotar 90°")
            Toggle(isOn: $transform.mirrored) { Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right") }
                .toggleStyle(.button)
                .help("Espejar (para sticker transparente pegado del lado de adentro de un vidrio)")
        }
    }
}

struct AdjustmentsSection: View {
    @Binding var pipeline: ImagePipeline

    var body: some View {
        Section("Tono") {
            Picker("Trama", selection: $pipeline.algorithm) {
                ForEach(DitherAlgorithm.allCases) { Text($0.label).tag($0) }
            }
            if pipeline.algorithm == .threshold {
                LabeledSlider("Umbral", value: $pipeline.adjustments.threshold, in: 0.1...0.9, format: "%.2f")
            }
            LabeledSlider("Brillo", value: $pipeline.adjustments.brightness, in: -0.5...0.5, format: "%+.2f")
            LabeledSlider("Contraste", value: $pipeline.adjustments.contrast, in: 0.5...2, format: "%.2f")
            LabeledSlider("Gamma", value: $pipeline.adjustments.gamma, in: 0.5...2.2, format: "%.2f")
                .help("Valores > 1 aclaran los medios tonos (el papel térmico tiende a oscurecer)")
            LabeledSlider("Nitidez", value: $pipeline.adjustments.sharpen, in: 0...2, format: "%.1f")
            Toggle("Niveles automáticos", isOn: $pipeline.adjustments.autoLevels)
            Toggle("Invertir", isOn: $pipeline.adjustments.invert)
            Button("Restablecer tono") {
                pipeline.adjustments = .recommendedPhoto
            }
        }
    }
}

struct LabeledSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: String
    var step: Double?

    init(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>, format: String, step: Double? = nil) {
        self.title = title
        self._value = value
        self.range = range
        self.format = format
        self.step = step
    }

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                Group {
                    if let step {
                        Slider(value: $value, in: range, step: step)
                    } else {
                        Slider(value: $value, in: range)
                    }
                }
                .labelsHidden()
                .frame(minWidth: 130, maxWidth: .infinity)
                Text(String(format: format, value)).monospacedDigit().foregroundStyle(.secondary)
                    .frame(width: 56, alignment: .trailing)
            }
        }
    }
}

struct FontPicker: View {
    @Binding var family: String
    @State private var families: [String] = NSFontManager.shared.availableFontFamilies.sorted()
    static let favorites = ["Helvetica Neue", "Avenir Next", "Futura", "Georgia", "Menlo", "American Typewriter",
                            "Chalkboard SE", "Marker Felt", "Noteworthy", "Snell Roundhand", "Impact", "Rockwell"]

    var body: some View {
        Picker("Fuente", selection: $family) {
            Section("Favoritas") {
                ForEach(Self.favorites.filter(families.contains), id: \.self) { Text($0).font(.custom($0, size: 13)).tag($0) }
            }
            if !FontLibrary.installedFamilies.isEmpty {
                Section("Descargadas") {
                    ForEach(FontLibrary.installedFamilies.filter(families.contains), id: \.self) { Text($0).tag($0) }
                }
            }
            Section("Todas") {
                ForEach(families, id: \.self) { Text($0).tag($0) }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: FontLibrary.didChange)) { _ in
            families = NSFontManager.shared.availableFontFamilies.sorted()
        }
    }
}

// MARK: Photo

struct PhotoEditor: View {
    @Environment(AppModel.self) private var model
    @Binding var showImporter: Bool

    var body: some View {
        @Bindable var model = model
        ImageSourceSection(showImporter: $showImporter)
        Section("Encuadre") {
            Picker("Recorte", selection: $model.photo.crop) {
                ForEach(CropAspect.allCases) { Text($0.label).tag($0) }
            }
            LabeledSlider("Ancho", value: $model.photo.widthPercent, in: 30...100, format: "%.0f%%", step: 5)
            TransformControls(transform: $model.photo.pipeline.transform)
            FramePicker(selection: $model.photo.frame, frames: DecorativeFrame.allCases)
        }
        AdjustmentsSection(pipeline: $model.photo.pipeline)
        Section("Texto") {
            TextField("Epígrafe", text: $model.photo.caption, prompt: Text("Opcional"), axis: .vertical).lineLimit(1...3)
            if !model.photo.caption.isEmpty {
                LabeledSlider("Tamaño", value: $model.photo.captionSize, in: 14...48, format: "%.0f pt", step: 1)
            }
            Toggle("Fecha y hora", isOn: $model.photo.dateStamp)
        }
    }
}

// MARK: Stickers

struct StickerEditor: View {
    @Environment(AppModel.self) private var model
    @Binding var showImporter: Bool

    var body: some View {
        @Bindable var model = model
        let maxMM = model.model.widthMM.rounded(.down)
        ImageSourceSection(showImporter: $showImporter)
        Section("Stickers") {
            LabeledSlider("Ancho", value: $model.sticker.widthMM, in: 10...maxMM, format: "%.0f mm", step: 1)
            Stepper("Columnas: \(model.sticker.columns)", value: $model.sticker.columns, in: 1...4)
            Stepper("Cantidad: \(model.sticker.count)", value: $model.sticker.count, in: 1...40)
            LabeledSlider("Separación", value: $model.sticker.gapMM, in: 0...10, format: "%.0f mm", step: 1)
            Picker("Borde", selection: $model.sticker.outline) {
                ForEach(StickerOutline.allCases) { Text($0.label).tag($0) }
            }
            if model.sticker.outline == .contour {
                LabeledSlider("Margen", value: $model.sticker.contourWidth, in: 2...20, format: "%.0f px", step: 1)
                Toggle("Tratar el blanco como transparente", isOn: $model.sticker.whiteIsTransparent)
            } else {
                FramePicker(selection: $model.sticker.decor, frames: DecorativeFrame.general)
            }
            TransformControls(transform: $model.sticker.pipeline.transform)
        }
        AdjustmentsSection(pipeline: $model.sticker.pipeline)
    }
}

// MARK: Text

struct TextDocEditor: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Section("Contenido") {
            Picker("Plantilla", selection: $model.text.template) {
                ForEach(TextTemplate.allCases) { Text($0.label).tag($0) }
            }
            if model.text.template == .note || model.text.template == .checklist {
                TextField("Título", text: $model.text.title, prompt: Text("Opcional"))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(model.text.template == .checklist ? "Ítems (uno por línea)" : "Texto").font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $model.text.body)
                    .font(.body)
                    .frame(minHeight: 110)
                    .scrollContentBackground(.hidden)
                    .padding(4)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
            }
        }
        Section("Estilo") {
            FontPicker(family: $model.text.fontFamily)
            if model.text.template != .label {
                LabeledSlider("Tamaño", value: $model.text.fontSize, in: 12...96, format: "%.0f pt", step: 1)
            }
            Toggle("Negrita", isOn: $model.text.bold)
            Picker("Alineación", selection: $model.text.align) {
                ForEach(TextAlign.allCases) { Image(systemName: $0.icon).tag($0) }
            }
            .pickerStyle(.segmented)
            LabeledSlider("Interlineado", value: $model.text.lineSpacing, in: 0...20, format: "%.0f", step: 1)
            FramePicker(selection: $model.text.frame, frames: DecorativeFrame.general)
            Toggle("Invertido (blanco sobre negro)", isOn: $model.text.invert)
            Toggle("Fecha y hora", isOn: $model.text.dateStamp)
        }
    }
}

// MARK: Banner

struct BannerEditor: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Section("Banner") {
            TextField("Texto", text: $model.banner.text, prompt: Text("Escribí el cartel"))
            FontPicker(family: $model.banner.fontFamily)
            Toggle("Negrita", isOn: $model.banner.bold)
            LabeledSlider("Altura", value: $model.banner.heightPercent, in: 40...110, format: "%.0f%%", step: 1)
            LabeledSlider("Espaciado", value: $model.banner.letterSpacing, in: -5...30, format: "%.0f", step: 1)
            Toggle("Borde", isOn: $model.banner.border)
            Toggle("Invertido", isOn: $model.banner.invert)
        }
        Section {
            Text("El texto se imprime a lo largo del papel: ideal para carteles y guirnaldas.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }
}

// MARK: QR

struct QREditor: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Section("Código QR") {
            Picker("Tipo", selection: $model.qr.kind) {
                ForEach(QRKind.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            switch model.qr.kind {
            case .text:
                TextField("Texto o URL", text: $model.qr.content, prompt: Text("https://…"), axis: .vertical).lineLimit(1...4)
            case .wifi:
                TextField("Red (SSID)", text: $model.qr.wifiSSID, prompt: Text("MiCasa"))
                SecureField("Contraseña", text: $model.qr.wifiPassword, prompt: Text("Vacía si es abierta"))
            }
            TextField("Leyenda", text: $model.qr.caption, prompt: Text("Opcional"))
            LabeledSlider("Tamaño", value: $model.qr.sizePercent, in: 30...100, format: "%.0f%%", step: 5)
            Picker("Corrección de errores", selection: $model.qr.correction) {
                Text("Baja (L)").tag("L")
                Text("Media (M)").tag("M")
                Text("Alta (Q)").tag("Q")
                Text("Máxima (H)").tag("H")
            }
        }
    }
}

// MARK: Print settings

struct PrintSettingsSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Section("Impresión") {
            Picker("Densidad", selection: $model.settings.density) {
                ForEach(Density.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            if !model.printsOnLabels {
                ContinuousPaperSettings()
            }
        }
    }
}

private struct ContinuousPaperSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Group {
            Stepper("Copias: \(model.settings.copies)", value: $model.settings.copies, in: 1...20)
            if model.settings.copies > 1 {
                LabeledSlider("Entre copias", value: $model.settings.gapBetweenCopiesMM, in: 0...20, format: "%.0f mm", step: 1)
            }
            LabeledSlider("Margen inferior", value: $model.settings.bottomMarginMM, in: 0...30, format: "%.0f mm", step: 1)
                .help("Papel en blanco entre el final de la impresión y el corte. El margen superior es de ~7 mm, así que 7 mm deja la tira simétrica.")
        }
    }
}

// MARK: Frames

struct FramePicker: View {
    @Binding var selection: DecorativeFrame
    let frames: [DecorativeFrame]

    var body: some View {
        Picker("Marco", selection: $selection) {
            ForEach(frames) { frame in
                Label { Text(frame.title) } icon: { FrameThumbnail(frame: frame) }.tag(frame)
            }
        }
    }
}

/// Tiny rendering of a frame, cached per style.
struct FrameThumbnail: View {
    let frame: DecorativeFrame
    @MainActor private static var cache: [DecorativeFrame: CGImage] = [:]

    var body: some View {
        if let cg = Self.image(for: frame) {
            Image(decorative: cg, scale: 3).renderingMode(.template).interpolation(.none)
        } else {
            Image(systemName: "square.dashed")
        }
    }

    @MainActor private static func image(for frame: DecorativeFrame) -> CGImage? {
        guard frame != .none else { return nil }
        if let cached = cache[frame] { return cached }
        let framed = frame.apply(to: MonoBitmap(width: 40, height: 16), width: 96, compact: true)
        let image = framed.maskImage()
        cache[frame] = image
        return image
    }
}

// MARK: Labels

struct LabelEditor: View {
    @Environment(AppModel.self) private var model
    @Binding var showImporter: Bool
    @State private var showAlign = false

    var body: some View {
        @Bindable var model = model
        Section("Contenido") {
            Picker("Tipo", selection: $model.label.content) {
                ForEach(LabelContent.allCases) { Text($0.title).tag($0) }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(model.label.content == .image ? "Una etiqueta por línea (texto opcional)" : "Una etiqueta por línea")
                    .font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $model.label.lines)
                    .font(.body)
                    .frame(minHeight: 80)
                    .scrollContentBackground(.hidden)
                    .padding(4)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
            }
            if model.label.content != .barcode && model.label.content != .image {
                TextField("Subtítulo", text: $model.label.subtitle, prompt: Text("Opcional, va en todas"))
                Toggle("Fecha (dd/mm/aa)", isOn: $model.label.dateStamp)
            }
            Stepper("Copias de cada una: \(model.label.copies)", value: $model.label.copies, in: 1...30)
        }
        if model.label.content == .iconText || model.label.content == .image {
            Section("Ícono / imagen") {
                HStack {
                    if let img = model.labelImage {
                        Image(decorative: img, scale: 1).resizable().scaledToFit().frame(width: 36, height: 36)
                        Text(model.labelImageName ?? "Imagen").lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button("Quitar") { model.labelImage = nil }
                    } else if model.label.content == .iconText {
                        Image(systemName: model.label.symbol).font(.title2).frame(width: 36)
                        TextField("Símbolo", text: $model.label.symbol, prompt: Text("SF Symbol, ej. leaf.fill"))
                    } else {
                        Text("Ninguna").foregroundStyle(.secondary)
                        Spacer()
                    }
                }
                HStack {
                    Button("Elegir imagen…") { showImporter = true }
                    Button("Abrir tienda…") { NotificationCenter.default.post(name: .openStore, object: nil) }
                }
                if model.label.content == .iconText && model.labelImage == nil {
                    SymbolGrid(selection: $model.label.symbol)
                }
                Picker("Trama", selection: $model.label.pipeline.algorithm) {
                    ForEach(DitherAlgorithm.allCases) { Text($0.label).tag($0) }
                }
            }
        }
        Section("Estilo") {
            FontPicker(family: $model.label.fontFamily)
            Toggle("Negrita", isOn: $model.label.bold)
            Picker("Alineación", selection: $model.label.align) {
                ForEach(TextAlign.allCases) { Image(systemName: $0.icon).tag($0) }
            }
            .pickerStyle(.segmented)
            FramePicker(selection: $model.label.frame, frames: DecorativeFrame.general)
            Toggle("Invertido (blanco sobre negro)", isOn: $model.label.invert)
        }
        Section {
            LabeledSlider("Alto", value: $model.label.heightMM, in: 8...60, format: "%.1f mm", step: 0.5)
            LabeledSlider("Separación", value: $model.label.gapMM, in: 0...15, format: "%.1f mm", step: 0.5)
            LabeledSlider("Ajuste fino", value: $model.label.adjustMM, in: -3...3, format: "%+.2f mm", step: 0.25)
                .help("Si lo impreso queda corrido hacia arriba, subilo; si queda corrido hacia abajo, bajalo.")
            Button("Alinear rollo y calibrar…") { showAlign = true }
        } header: {
            Text("Rollo de etiquetas")
        } footer: {
            Text("Cada trabajo termina con el corte justo al comienzo de una separación, así el siguiente arranca alineado.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .sheet(isPresented: $showAlign) { LabelAlignSheet() }
    }
}

private struct SymbolGrid: View {
    @Binding var selection: String
    static let symbols = ["leaf.fill", "cup.and.saucer.fill", "fork.knife", "birthday.cake.fill", "carrot.fill", "fish.fill",
                          "heart.fill", "star.fill", "sun.max.fill", "moon.fill", "snowflake", "flame.fill",
                          "house.fill", "gift.fill", "book.fill", "pencil", "scissors", "paintbrush.fill",
                          "pawprint.fill", "bolt.fill", "drop.fill", "shippingbox.fill", "archivebox.fill", "tag.fill"]

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(30), spacing: 6), count: 8), spacing: 6) {
            ForEach(Self.symbols, id: \.self) { name in
                Button { selection = name } label: {
                    Image(systemName: name).frame(width: 26, height: 26)
                        .background(RoundedRectangle(cornerRadius: 5).fill(selection == name ? Color.accentColor.opacity(0.25) : .clear))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct LabelAlignSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Alinear el rollo de etiquetas").font(.title2.bold())
            Text("1. Avanzá el papel hasta que el **final de una etiqueta** quede justo en el filo de corte (que se vea el comienzo de la separación).\n2. Cortá ahí. Desde ese momento cada impresión termina en la misma posición y la siguiente queda alineada.\n3. Si lo impreso queda corrido, imprimí la calibración y corregí con *Ajuste fino*.")
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Text("Avanzar:")
                ForEach([0.5, 1, 2, 5], id: \.self) { mm in
                    Button("\(mm, specifier: mm < 1 ? "%.1f" : "%.0f") mm") { Task { await model.feedPaper(mm: mm) } }
                }
                Button("1 etiqueta") { Task { await model.feedPaper(mm: model.label.heightMM + model.label.gapMM) } }
            }
            .disabled(model.isPrinting)
            Text("Cada avance suma ~1 mm que la impresora agrega sola al empezar.").font(.caption).foregroundStyle(.secondary)
            Divider()
            HStack {
                Button("Imprimir calibración (2 etiquetas)") { Task { await model.printLabelCalibration() } }
                Button("Probar sensor de separación") { Task { await model.testGapSensor() } }
                    .help("Experimental: algunos modelos PeriPage detectan la separación entre etiquetas.")
            }
            .disabled(model.isPrinting)
            Spacer()
            HStack {
                Spacer()
                Button("Listo") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 560, height: 360)
    }
}

// MARK: Games

struct GamesEditor: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        PuzzleEditor(doc: $model.puzzle)
        Section("Solución") {
            Button("Imprimir solución") { Task { await model.printPuzzleSolution() } }
                .disabled(model.isPrinting)
            Text("Se imprime aparte, con el mismo número de juego.").font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: Social

struct SocialModeEditor: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        SocialEditor(doc: $model.social, post: $model.socialPost)
        if let post = model.socialPost, let first = post.images.first {
            Section("Usar la imagen") {
                HStack {
                    Button("Como foto") { model.useCapturedImage(first, as: .photo) }
                    Button("Como sticker") { model.useCapturedImage(first, as: .sticker) }
                }
            }
        }
        if model.social.layout == .label {
            Section("Etiqueta") {
                Text("Se imprime en tus etiquetas de \(model.label.heightMM, specifier: "%.0f") mm con la alineación del modo Etiquetas.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: History

struct HistoryEditor: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Section {
            if model.history.isEmpty {
                Text("Todavía no imprimiste nada desde esta versión.").foregroundStyle(.secondary)
            }
            ForEach(model.history) { entry in
                HistoryRow(entry: entry, selected: entry.id == model.selectedHistoryID)
                    .contentShape(Rectangle())
                    .onTapGesture { model.selectedHistoryID = entry.id }
                    .contextMenu {
                        Button("Borrar", role: .destructive) { model.deleteHistory(entry) }
                    }
            }
        } header: {
            HStack {
                Text("Últimas impresiones")
                Spacer()
                if !model.history.isEmpty {
                    Button("Borrar todo", role: .destructive) { model.clearHistory() }.buttonStyle(.borderless).font(.caption)
                }
            }
        }
    }
}

private struct HistoryRow: View {
    let entry: HistoryEntry
    let selected: Bool
    @State private var thumbnail: NSImage?

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let thumbnail {
                    Image(nsImage: thumbnail).resizable().interpolation(.medium).scaledToFit()
                } else {
                    Color.gray.opacity(0.1)
                }
            }
            .frame(width: 44, height: 44)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title).lineLimit(1)
                Text("\(entry.date.formatted(date: .abbreviated, time: .shortened)) · \(entry.height / 8) mm")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor) }
        }
        .task(id: entry.id) { thumbnail = NSImage(contentsOf: HistoryStore.imageURL(for: entry)) }
    }
}

// MARK: Collage

struct CollageEditor: View {
    @Environment(AppModel.self) private var model
    @Binding var showImporter: Bool

    var body: some View {
        @Bindable var model = model
        Section("Fotos (\(model.collageImages.count)/\(AppModel.maxCollageImages))") {
            if model.collageImages.isEmpty {
                Text("Agregá fotos con el botón o arrastrándolas.").foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(Array(model.collageImages.enumerated()), id: \.offset) { index, image in
                            Image(decorative: image, scale: 1).resizable().scaledToFill()
                                .frame(width: 56, height: 56).clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(alignment: .topTrailing) {
                                    Button { model.collageImages.remove(at: index) } label: {
                                        Image(systemName: "xmark.circle.fill").symbolRenderingMode(.palette)
                                            .foregroundStyle(.white, .black.opacity(0.6))
                                    }
                                    .buttonStyle(.plain)
                                    .padding(2)
                                }
                        }
                    }
                }
            }
            HStack {
                Button("Agregar fotos…") { showImporter = true }
                    .disabled(model.collageImages.count >= AppModel.maxCollageImages)
                if !model.collageImages.isEmpty {
                    Button("Mezclar") { model.collageImages.shuffle() }
                    Button("Quitar todas", role: .destructive) { model.collageImages.removeAll() }
                }
            }
        }
        Section("Diseño") {
            Picker("Disposición", selection: $model.collage.layout) {
                ForEach(CollageLayout.allCases) { Text($0.title).tag($0) }
            }
            LabeledSlider("Separación", value: $model.collage.spacingMM, in: 0...8, format: "%.0f mm", step: 1)
            FramePicker(selection: $model.collage.frame, frames: DecorativeFrame.general)
            TextField("Texto", text: $model.collage.caption, prompt: Text("Opcional"))
            Toggle("Fecha y hora", isOn: $model.collage.dateStamp)
        }
        AdjustmentsSection(pipeline: $model.collage.pipeline)
    }
}

extension MonoBitmap {
    /// Ink as opaque black on a transparent background, for template images in menus.
    func maskImage() -> CGImage? {
        guard width > 0, height > 0 else { return nil }
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width where self[x, y] { rgba[(y * width + x) * 4 + 3] = 255 }
        }
        guard let provider = CGDataProvider(data: Data(rgba) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
