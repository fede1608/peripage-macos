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
    /// Page the browser opens on (a login page when signing in).
    @State private var browserStart: URL?
    @State private var loggedIn: [SocialPlatform: Bool] = [:]

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
                if post.images.count > 1 {
                    CarouselPicker(images: post.images, selection: $doc.imageIndex)
                }
            } else if !fetching, errorMessage == nil {
                Text("Posteos de X (x.com, twitter.com) e Instagram: fotos, carruseles, reels e historias. Para cuentas privadas que seguís e historias, iniciá sesión en Cuentas.")
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
            ForEach([SocialPlatform.instagram, .x], id: \.self) { platform in
                accountRow(platform)
            }
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Navegador con Capturar")
                    Text("Para imprimir lo que veas en pantalla: tu feed, comentarios, perfiles…")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { browserStart = nil; showBrowser = true } label: { Label("Abrir…", systemImage: "safari") }
            }
        } header: {
            Text("Cuentas")
        } footer: {
            Text("Con la sesión iniciada, el link también trae posteos de cuentas privadas que seguís e historias. Iniciás sesión en la página oficial dentro del navegador: PeriPrint nunca ve tu contraseña y la sesión queda solo en esta Mac.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .task { await refreshSessions() }
        .sheet(isPresented: $showBrowser, onDismiss: { Task { await refreshSessions() } }) {
            BrowserSheet(start: browserStart) { image in
                post = SocialPost(platform: .capture, images: [image])
                doc.imageIndex = 0
                errorMessage = nil
                showBrowser = false
            }
        }
    }

    private func accountRow(_ platform: SocialPlatform) -> some View {
        let active = loggedIn[platform] == true
        return HStack {
            Image(systemName: active ? "checkmark.circle.fill" : "person.crop.circle.badge.questionmark")
                .foregroundStyle(active ? Color.green : Color.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(platform.title)
                Text(active ? "Sesión iniciada" : "Sin sesión").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if active {
                Button("Cerrar sesión") {
                    Task {
                        await SocialSession.logOut(platform)
                        await refreshSessions()
                    }
                }
            } else {
                Button("Iniciar sesión…") {
                    browserStart = SocialSession.loginURL(platform)
                    showBrowser = true
                }
            }
        }
    }

    private func refreshSessions() async {
        var state: [SocialPlatform: Bool] = [:]
        for platform in [SocialPlatform.instagram, .x] { state[platform] = await SocialSession.isLoggedIn(platform) }
        loggedIn = state
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

/// The photos of a carousel post as a strip of thumbnails; the selected one is printed.
private struct CarouselPicker: View {
    let images: [CGImage]
    @Binding var selection: Int

    private var selected: Int { min(max(0, selection), images.count - 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Foto")
                Spacer()
                Text("\(selected + 1) de \(images.count)").monospacedDigit().foregroundStyle(.secondary)
            }
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(images.indices, id: \.self) { index in
                            Button { selection = index } label: {
                                Image(decorative: images[index], scale: 1)
                                    .resizable().scaledToFill()
                                    .frame(width: 58, height: 58)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 6)
                                            .strokeBorder(index == selected ? Color.accentColor : Color.primary.opacity(0.12),
                                                          lineWidth: index == selected ? 3 : 1)
                                    }
                                    .opacity(index == selected ? 1 : 0.75)
                            }
                            .buttonStyle(.plain)
                            .help("Foto \(index + 1)")
                            .id(index)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .onAppear { proxy.scrollTo(selected, anchor: .center) }
            }
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
    let start: URL?
    let onCapture: (CGImage) -> Void

    init(start: URL? = nil, onCapture: @escaping (CGImage) -> Void) {
        self.start = start
        self.onCapture = onCapture
    }

    var body: some View {
        VStack(spacing: 0) {
            SocialBrowserView(onCapture: onCapture, start: start)
            Divider()
            HStack {
                Text(start != nil ? "Iniciá sesión y tocá Cerrar: después pegá el link del posteo o la historia y tocá Traer."
                                  : "Navegá hasta el posteo o la historia, tocá Capturar y hacé clic sobre lo que quieras imprimir.")
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
