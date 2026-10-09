import AppKit
import Combine
import SwiftUI
import WebKit

/// Embedded browser for Instagram / X with a capture mode: hover outlines the post (or story) under the
/// mouse and a click snapshots it. Uses the default persistent website data store, so the user's own
/// login (done manually) survives relaunches. Nothing is automated or read from the session.
public struct SocialBrowserView: View {
    @StateObject private var browser = BrowserController()
    private let onCapture: (CGImage) -> Void

    public init(onCapture: @escaping (CGImage) -> Void) {
        self.onCapture = onCapture
    }

    public var body: some View {
        VStack(spacing: 0) {
            toolbar
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            Divider()
            ZStack(alignment: .top) {
                WebViewHost(webView: browser.webView)
                if browser.capturing {
                    Text("Pasá el mouse por encima del posteo o la historia y hacé clic para capturarlo. Esc para salir.")
                        .font(.callout.weight(.medium))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.regularMaterial, in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.accentColor.opacity(0.6)))
                        .padding(.top, 10)
                        .allowsHitTesting(false)
                }
                if let message = browser.message {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.red.opacity(0.85), in: Capsule())
                        .padding(.top, 10)
                }
            }
        }
        .onAppear {
            browser.onCapture = onCapture
            browser.loadHomeIfNeeded()
        }
        .onExitCommand { browser.setCapturing(false) }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Picker("Sitio", selection: Binding(get: { browser.site }, set: { browser.open($0) })) {
                ForEach(BrowserController.Site.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 170)

            Button { browser.webView.goBack() } label: { Image(systemName: "chevron.left") }
                .disabled(!browser.canGoBack)
                .help("Atrás")
            Button { browser.webView.goForward() } label: { Image(systemName: "chevron.right") }
                .disabled(!browser.canGoForward)
                .help("Adelante")
            Button {
                if browser.isLoading { browser.webView.stopLoading() } else { browser.webView.reload() }
            } label: {
                Image(systemName: browser.isLoading ? "xmark" : "arrow.clockwise")
            }
            .help(browser.isLoading ? "Detener" : "Recargar")

            TextField("Dirección", text: $browser.address, prompt: Text("instagram.com/… o x.com/…"))
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
                .onSubmit { browser.go(to: browser.address) }

            Toggle(isOn: Binding(get: { browser.capturing }, set: { browser.setCapturing($0) })) {
                Label("Capturar", systemImage: "viewfinder")
            }
            .toggleStyle(.button)
            .help("Elegí con el mouse el posteo o la historia a capturar (Esc para salir)")

            Button { browser.captureVisible() } label: { Label("Capturar todo lo visible", systemImage: "rectangle.dashed") }
                .help("Captura todo lo que se ve en el navegador")
        }
    }
}

private struct WebViewHost: NSViewRepresentable {
    let webView: WKWebView
    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

@MainActor
final class BrowserController: NSObject, ObservableObject {
    enum Site: String, CaseIterable, Identifiable {
        case instagram, x
        var id: String { rawValue }
        var title: String { self == .instagram ? "Instagram" : "X" }
        var home: URL { URL(string: self == .instagram ? "https://www.instagram.com/" : "https://x.com/home")! }
    }

    @Published private(set) var site: Site = .instagram
    @Published var address = ""
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var isLoading = false
    @Published private(set) var capturing = false
    @Published private(set) var message: String?
    var onCapture: ((CGImage) -> Void)?

    let webView: WKWebView
    private var cancellables: Set<AnyCancellable> = []
    private var messageTask: Task<Void, Never>?

    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let content = WKUserContentController()
        content.addUserScript(WKUserScript(source: CaptureScript.source, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        config.userContentController = content
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1000, height: 700), configuration: config)
        webView.customUserAgent = SocialFetcher.safariUserAgent
        webView.allowsBackForwardNavigationGestures = true
        super.init()
        content.add(WeakScriptHandler(self), name: CaptureScript.handlerName)
        webView.navigationDelegate = self
        webView.uiDelegate = self

        webView.publisher(for: \.canGoBack).receive(on: RunLoop.main).sink { [weak self] in self?.canGoBack = $0 }.store(in: &cancellables)
        webView.publisher(for: \.canGoForward).receive(on: RunLoop.main).sink { [weak self] in self?.canGoForward = $0 }.store(in: &cancellables)
        webView.publisher(for: \.isLoading).receive(on: RunLoop.main).sink { [weak self] in self?.isLoading = $0 }.store(in: &cancellables)
        webView.publisher(for: \.url).receive(on: RunLoop.main).sink { [weak self] url in
            guard let self, let url else { return }
            self.address = url.absoluteString
            if let host = url.host?.lowercased() {
                if host.hasSuffix("instagram.com") { self.site = .instagram } else if host == "x.com" || host.hasSuffix("twitter.com") { self.site = .x }
            }
        }.store(in: &cancellables)
    }

    func loadHomeIfNeeded() {
        if webView.url == nil { webView.load(URLRequest(url: site.home)) }
    }

    func open(_ site: Site) {
        self.site = site
        webView.load(URLRequest(url: site.home))
    }

    func go(to string: String) {
        var s = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return }
        if !s.contains("://") { s = "https://" + s }
        guard let url = URL(string: s), url.host != nil else {
            show("Esa dirección no es válida.")
            return
        }
        webView.load(URLRequest(url: url))
    }

    func setCapturing(_ on: Bool) {
        guard capturing != on else { return }
        capturing = on
        webView.evaluateJavaScript(on ? "window.__periCapture && window.__periCapture.enable()" : "window.__periCapture && window.__periCapture.disable()")
        if on { webView.window?.makeFirstResponder(webView) }
    }

    func captureVisible() {
        setCapturing(false)
        snapshot(rect: nil)
    }

    /// `rect` is in CSS pixels relative to the viewport (from `getBoundingClientRect`); nil captures everything visible.
    func snapshot(rect: CGRect?) {
        let config = WKSnapshotConfiguration()
        config.afterScreenUpdates = true
        if let rect {
            let zoom = webView.pageZoom * webView.magnification
            let r = CGRect(x: rect.minX * zoom, y: rect.minY * zoom, width: rect.width * zoom, height: rect.height * zoom)
                .intersection(webView.bounds)
            guard r.width >= 8, r.height >= 8 else {
                show("No pude capturar esa parte de la página.")
                return
            }
            config.rect = r
        }
        webView.takeSnapshot(with: config) { [weak self] image, error in
            guard let self else { return }
            guard let image, let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                self.show("No pude capturar la página\(error.map { ": \($0.localizedDescription)" } ?? ".")")
                return
            }
            self.onCapture?(cg)
        }
    }

    fileprivate func handle(_ body: Any) {
        guard let dict = body as? [String: Any], let type = dict["type"] as? String else { return }
        switch type {
        case "capture":
            capturing = false
            let n = { (key: String) in (dict[key] as? NSNumber)?.doubleValue ?? 0 }
            snapshot(rect: CGRect(x: n("x"), y: n("y"), width: n("width"), height: n("height")))
        case "cancel":
            capturing = false
        default:
            break
        }
    }

    private func show(_ text: String) {
        message = text
        messageTask?.cancel()
        messageTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.message = nil
        }
    }
}

extension BrowserController: WKNavigationDelegate, WKUIDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // A full page load replaces the script state: re-arm capture mode if it was on.
        if capturing { webView.evaluateJavaScript("window.__periCapture && window.__periCapture.enable()") }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        reportNavigationError(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        reportNavigationError(error)
    }

    private func reportNavigationError(_ error: Error) {
        let nsError = error as NSError
        guard !(nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled) else { return }
        show("No se pudo cargar la página: \(nsError.localizedDescription)")
    }

    /// Links that open a new window load in place.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil { webView.load(navigationAction.request) }
        return nil
    }
}

/// Breaks the retain cycle between `WKUserContentController` and the controller.
private final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    weak var target: BrowserController?
    init(_ target: BrowserController) { self.target = target }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        let body = message.body
        MainActor.assumeIsolated { target?.handle(body) }
    }
}

/// Injected into every page: outlines the element under the mouse while capture mode is on.
enum CaptureScript {
    static let handlerName = "periCapture"

    static let source = #"""
    (() => {
      if (window.__periCapture) return;
      let active = false, current = null, box = null, lastX = -1, lastY = -1, frame = 0;
      const post = (msg) => { try { window.webkit.messageHandlers.periCapture.postMessage(msg); } catch (e) {} };

      function ensureBox() {
        if (box && box.isConnected) return box;
        box = document.createElement('div');
        box.setAttribute('data-peri-capture', '');
        box.style.cssText = 'position:fixed;left:0;top:0;width:0;height:0;z-index:2147483647;pointer-events:none;' +
          'box-sizing:border-box;border:3px solid #ff2d55;border-radius:6px;background:rgba(255,45,85,0.08);' +
          'box-shadow:0 0 0 100vmax rgba(0,0,0,0.25);display:none;transition:left 60ms,top 60ms,width 60ms,height 60ms;';
        document.documentElement.appendChild(box);
        return box;
      }

      function visibleRect(el) {
        const r = el.getBoundingClientRect();
        const x = Math.max(0, r.left), y = Math.max(0, r.top);
        const w = Math.min(window.innerWidth, r.right) - x, h = Math.min(window.innerHeight, r.bottom) - y;
        return { x, y, width: Math.max(0, w), height: Math.max(0, h) };
      }

      // Innermost post-like container (article, tweet, dialog, story section); else the smallest ancestor of at least 200×200.
      function pick(target) {
        if (!target || target.nodeType !== 1) return null;
        const vw = window.innerWidth, vh = window.innerHeight;
        let fallback = null;
        for (let n = target; n && n !== document.body && n !== document.documentElement; n = n.parentElement) {
          if (n === box) continue;
          const r = n.getBoundingClientRect();
          if (r.width * r.height >= vw * vh * 0.92) break;
          const tag = n.tagName.toLowerCase(), role = n.getAttribute('role');
          if ((tag === 'article' || role === 'dialog' || n.getAttribute('data-testid') === 'tweet') && r.width >= 120 && r.height >= 80) return n;
          if (tag === 'section' && r.width >= 200 && r.height >= 200) return n;
          if (!fallback && r.width >= 200 && r.height >= 200) fallback = n;
        }
        return fallback;
      }

      function update() {
        frame = 0;
        if (!active) return;
        const el = lastX >= 0 ? document.elementFromPoint(lastX, lastY) : null;
        current = pick(el);
        const b = ensureBox();
        if (!current) { b.style.display = 'none'; return; }
        const r = visibleRect(current);
        b.style.display = 'block';
        b.style.left = r.x + 'px'; b.style.top = r.y + 'px';
        b.style.width = r.width + 'px'; b.style.height = r.height + 'px';
      }
      const schedule = () => { if (!frame) frame = requestAnimationFrame(update); };

      function onMove(e) { if (!active) return; lastX = e.clientX; lastY = e.clientY; schedule(); }
      function swallow(e) { if (!active) return; e.preventDefault(); e.stopPropagation(); e.stopImmediatePropagation(); }
      function onClick(e) {
        if (!active) return;
        swallow(e);
        lastX = e.clientX; lastY = e.clientY;
        const el = pick(document.elementFromPoint(lastX, lastY)) || current;
        if (!el) return;
        const r = visibleRect(el);
        disable();
        // Let the outline disappear from the screen before Swift takes the snapshot.
        requestAnimationFrame(() => requestAnimationFrame(() => post({ type: 'capture', x: r.x, y: r.y, width: r.width, height: r.height })));
      }
      function onKey(e) {
        if (active && e.key === 'Escape') { swallow(e); disable(); post({ type: 'cancel' }); }
      }

      function enable() { active = true; document.documentElement.style.cursor = 'crosshair'; schedule(); }
      function disable() {
        active = false; current = null;
        document.documentElement.style.cursor = '';
        if (box) box.style.display = 'none';
      }

      window.addEventListener('mousemove', onMove, true);
      window.addEventListener('scroll', schedule, true);
      for (const type of ['mousedown', 'mouseup', 'pointerdown', 'pointerup', 'auxclick', 'dblclick']) window.addEventListener(type, swallow, true);
      window.addEventListener('click', onClick, true);
      window.addEventListener('keydown', onKey, true);
      window.__periCapture = { enable, disable, pick, isActive: () => active };
    })();
    """#
}
