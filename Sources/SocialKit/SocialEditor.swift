import AppKit
import PeriPageKit
import SwiftUI

/// Form sections for the social mode; meant to be embedded in the app's `Form { … }.formStyle(.grouped)`.
public struct SocialEditor: View {
    @Binding var doc: SocialDoc
    @Binding var post: SocialPost?
    @State private var fetching = false
    @State private var errorMessage: String?
    @State private var fetchTask: Task<Void, Never>?
    /// Bumped on every fetch or cancel, so a superseded request never touches the state.
    @State private var fetchGeneration = 0
    @State private var showBrowser = false

    public init(doc: Binding<SocialDoc>, post: Binding<SocialPost?>) {
        self._doc = doc
        self._post = post
    }

    public var body: some View {
        linkSection
        browserSection
        designSection
        toneSection
    }

    // MARK: Link

    private var linkSection: some View {
        Section {
            HStack {
                TextField("Link", text: $doc.urlString, prompt: Text("Pegá el link de X o Instagram"))
                    .labelsHidden()
                    .onSubmit(fetch)
                Button { pasteAndFetch() } label: { Image(systemName: "doc.on.clipboard") }
                    .help("Pegar el link del portapapeles y traer el posteo")
                Button("Traer", action: fetch)
                    .disabled(fetching || doc.urlString.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if fetching {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Trayendo el posteo…").foregroundStyle(.secondary)
                    Spacer()
                    Button("Cancelar") { cancelFetch() }.buttonStyle(.link)
                }
            }
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let post, !fetching {
                PostSummary(post: post)
            } else if !fetching, errorMessage == nil {
                Text("Posteos públicos de X (x.com, twitter.com) e Instagram (fotos, carruseles y reels). Para historias o cuentas privadas usá el navegador.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text("Link")
        }
        .task {
            // The post is not persisted: bring it back when the mode reopens with a saved link.
            if post == nil, SocialFetcher.canHandle(doc.urlString) { fetch() }
        }
    }

    private func pasteAndFetch() {
        guard let string = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !string.isEmpty else { return }
        doc.urlString = string
        fetch()
    }

    private func fetch() {
        let link = doc.urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !link.isEmpty else { return }
        cancelFetch()
        let generation = fetchGeneration
        errorMessage = nil
        fetching = true
        fetchTask = Task { @MainActor in
            let result: Result<SocialPost, Error>
            do { result = .success(try await SocialFetcher.fetch(link)) } catch { result = .failure(error) }
            guard generation == fetchGeneration else { return }
            fetching = false
            switch result {
            case .success(let fetched):
                post = fetched
                doc.imageIndex = 0
            case .failure(let error):
                if !(error is CancellationError) { errorMessage = error.localizedDescription }
            }
        }
    }

    private func cancelFetch() {
        fetchTask?.cancel()
        fetchTask = nil
        fetchGeneration += 1
        fetching = false
    }

    // MARK: Browser

    private var browserSection: some View {
        Section {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Historias, cuentas privadas o lo que veas en pantalla")
                    Text("Iniciá sesión vos mismo; la sesión queda guardada en esta Mac.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { showBrowser = true } label: { Label("Abrir…", systemImage: "safari") }
            }
        } header: {
            Text("Navegador")
        }
        .sheet(isPresented: $showBrowser) {
            BrowserSheet { image in
                post = SocialPost(platform: .capture, images: [image])
                doc.imageIndex = 0
                errorMessage = nil
                showBrowser = false
            }
        }
    }

    // MARK: Design

    private var designSection: some View {
        Section("Diseño") {
            Picker("Formato", selection: $doc.layout) {
                ForEach(SocialLayout.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            Text(layoutHint).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

            if post?.platform != .capture {
                switch doc.layout {
                case .card:
                    Toggle("Texto", isOn: $doc.showText)
                    Toggle("Me gusta, respuestas y reposts", isOn: $doc.showStats)
                    Toggle("Fecha", isOn: $doc.showDate)
                case .photo, .sticker:
                    Toggle("Usuario", isOn: $doc.showText)
                    Toggle("Fecha", isOn: $doc.showDate)
                case .label:
                    Toggle("Primera línea del texto", isOn: $doc.showText)
                }
            }
            if doc.layout == .label {
                LabeledContent("Alto de la etiqueta") {
                    HStack(spacing: 8) {
                        Slider(value: Binding(get: { doc.labelHeightMM }, set: { doc.labelHeightMM = $0.rounded() }), in: 10...40)
                            .labelsHidden().frame(minWidth: 130)
                        Text(String(format: "%.0f mm", doc.labelHeightMM)).monospacedDigit().foregroundStyle(.secondary)
                            .frame(width: 56, alignment: .trailing)
                    }
                }
            }
            if let count = post?.images.count, count > 1 {
                Stepper(value: $doc.imageIndex, in: 0...(count - 1)) {
                    Text("Imagen \(min(doc.imageIndex, count - 1) + 1) de \(count)")
                }
            }
        }
    }

    private var layoutHint: String {
        switch doc.layout {
        case .card: "El posteo completo, como se ve en la app."
        case .photo: "Solo la imagen, a todo el ancho."
        case .sticker: "Imagen con esquinas redondeadas y línea de corte."
        case .label: "Para etiquetas precortadas: imagen a la izquierda, nombre y usuario a la derecha."
        }
    }

    // MARK: Tone

    private var toneSection: some View {
        Section("Tono") {
            Picker("Trama", selection: $doc.pipeline.algorithm) {
                ForEach(DitherAlgorithm.allCases) { Text($0.label).tag($0) }
            }
            if doc.pipeline.algorithm == .threshold {
                ToneSlider("Umbral", value: $doc.pipeline.adjustments.threshold, in: 0.1...0.9, format: "%.2f")
            }
            ToneSlider("Brillo", value: $doc.pipeline.adjustments.brightness, in: -0.5...0.5, format: "%+.2f")
            ToneSlider("Contraste", value: $doc.pipeline.adjustments.contrast, in: 0.5...2, format: "%.2f")
            ToneSlider("Gamma", value: $doc.pipeline.adjustments.gamma, in: 0.5...2.2, format: "%.2f")
                .help("Valores > 1 aclaran los medios tonos (el papel térmico tiende a oscurecer)")
            Button("Restablecer tono") { doc.pipeline = .recommendedPhoto }
        }
    }
}

/// Thumbnail, name and counts of the fetched post.
private struct PostSummary: View {
    let post: SocialPost

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let avatar = post.avatar ?? post.images.first {
                    Image(decorative: avatar, scale: 1).resizable().scaledToFill()
                } else {
                    Image(systemName: "person.crop.circle").resizable().foregroundStyle(.secondary)
                }
            }
            .frame(width: 36, height: 36)
            .clipShape(post.platform == .capture ? AnyShape(RoundedRectangle(cornerRadius: 6)) : AnyShape(Circle()))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).fontWeight(.semibold).lineLimit(1)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
        }
    }

    private var title: String {
        post.platform == .capture ? "Captura del navegador" : post.displayName
    }

    private var subtitle: String {
        if post.platform == .capture, let image = post.images.first { return "\(image.width) × \(image.height) px" }
        var parts = [post.handle.isEmpty ? post.platform.title : "@\(post.handle) · \(post.platform.title)"]
        switch post.images.count {
        case 0: parts.append("sin imágenes")
        case 1: parts.append("1 imagen")
        default: parts.append("\(post.images.count) imágenes")
        }
        return parts.joined(separator: " · ")
    }
}

private struct ToneSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: String

    init(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>, format: String) {
        self.title = title
        self._value = value
        self.range = range
        self.format = format
    }

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                Slider(value: $value, in: range).labelsHidden().frame(minWidth: 130, maxWidth: .infinity)
                Text(String(format: format, value)).monospacedDigit().foregroundStyle(.secondary)
                    .frame(width: 56, alignment: .trailing)
            }
        }
    }
}

/// The browser in a sheet, with a close button.
private struct BrowserSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onCapture: (CGImage) -> Void

    var body: some View {
        VStack(spacing: 0) {
            SocialBrowserView(onCapture: onCapture)
            Divider()
            HStack {
                Text("Navegá hasta el posteo o la historia, tocá Capturar y hacé clic sobre lo que quieras imprimir.")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
                // No Esc shortcut here: Esc leaves capture mode inside the browser.
                Button("Cerrar") { dismiss() }
            }
            .padding(10)
        }
        .frame(minWidth: 900, idealWidth: 1040, minHeight: 640, idealHeight: 820)
    }
}
