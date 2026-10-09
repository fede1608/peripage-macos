import CoreText
import Foundation

/// Fonts downloaded from the store's "Fuentes" tab, kept in ~/Library/Application Support/PeriPrint/Fonts/<Family>/
/// and registered for this process only.
public enum FontLibrary {
    /// Posted (on the main thread) when fonts are installed or removed so font pickers refresh.
    public static let didChange = Notification.Name("PeriPrint.FontLibrary.didChange")

    /// Registers fonts previously downloaded from the store. Call it once at launch; repeated calls are cheap.
    public static func registerInstalledFonts() {
        for family in installed() {
            for file in family.files { register(file) }
        }
    }

    /// Family names as CoreText/NSFontManager know them, sorted.
    public static var installedFamilies: [String] {
        Array(Set(installed().map(\.family))).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    struct Installed: Hashable, Identifiable, Sendable {
        /// Google Fonts family name (folder name).
        var folderName: String
        /// Family name reported by the font file.
        var family: String
        var files: [URL]
        var id: String { folderName }
    }

    static var directory: URL { StorePaths.fonts }

    static func installed() -> [Installed] {
        let fm = FileManager.default
        guard let folders = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil,
                                                        options: [.skipsHiddenFiles]) else { return [] }
        return folders.compactMap { folder -> Installed? in
            let files = fontFiles(in: folder)
            guard let first = files.first else { return nil }
            return Installed(folderName: folder.lastPathComponent, family: familyName(of: first) ?? folder.lastPathComponent,
                             files: files)
        }
        .sorted { $0.folderName.localizedCaseInsensitiveCompare($1.folderName) == .orderedAscending }
    }

    static func isInstalled(_ family: String) -> Bool {
        !fontFiles(in: directory.appendingPathComponent(family, isDirectory: true)).isEmpty
    }

    static func fontFiles(in folder: URL) -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil,
                                                                  options: [.skipsHiddenFiles])) ?? []
        return files.filter { ["ttf", "otf"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static func familyName(of url: URL) -> String? {
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
              let first = descriptors.first else { return nil }
        return CTFontDescriptorCopyAttribute(first, kCTFontFamilyNameAttribute) as? String
    }

    private static let lock = NSLock()
    private static var registered = Set<String>()

    @discardableResult
    static func register(_ url: URL) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if registered.contains(url.path) { return true }
        var error: Unmanaged<CFError>?
        let ok = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
        let code = error.map { CFErrorGetCode($0.takeRetainedValue()) }
        if ok || code == CTFontManagerError.alreadyRegistered.rawValue {
            registered.insert(url.path)
            return true
        }
        return false
    }

    static func unregister(_ url: URL) {
        lock.lock()
        defer { lock.unlock() }
        var error: Unmanaged<CFError>?
        if !CTFontManagerUnregisterFontsForURL(url as CFURL, .process, &error) { error?.release() }
        registered.remove(url.path)
    }

    /// Downloads the regular (and bold, if the family has it) TrueType files and registers them.
    static func install(_ family: GoogleFontFamily, http: StoreHTTP = .shared) async throws {
        guard let regular = family.regularWeight else { throw StoreError.fontUnavailable }
        var weights = [regular]
        if let bold = family.boldWeight { weights.append(bold) }
        let css = try await http.data(from: GoogleFonts.cssURL(family: family.family, weights: weights),
                                      headers: ["User-Agent": GoogleFonts.cssUserAgent])
        var faces: [Int: GoogleFonts.FontFace] = [:]
        for face in GoogleFonts.trueTypeFaces(GoogleFonts.parseCSS(String(decoding: css, as: UTF8.self))) where !face.italic {
            faces[face.weight] = faces[face.weight] ?? face
        }
        guard !faces.isEmpty else { throw StoreError.fontUnavailable }

        var downloads: [(weight: Int, data: Data)] = []
        for (weight, face) in faces.sorted(by: { $0.key < $1.key }) {
            let data = try await http.data(from: face.url, policy: .returnCacheDataElseLoad, timeout: 60)
            guard CTFontManagerCreateFontDescriptorFromData(data as CFData) != nil else { throw StoreError.fontUnavailable }
            downloads.append((weight, data))
        }

        let folder = directory.appendingPathComponent(family.family, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let base = family.family.replacingOccurrences(of: " ", with: "")
        for (weight, data) in downloads {
            let file = folder.appendingPathComponent("\(base)-\(weight).ttf")
            try data.write(to: file, options: .atomic)
            register(file)
        }
        notifyChange()
    }

    /// Unregisters and deletes an installed family (by its folder name).
    static func remove(_ folderName: String) throws {
        let folder = directory.appendingPathComponent(folderName, isDirectory: true)
        for file in fontFiles(in: folder) { unregister(file) }
        if FileManager.default.fileExists(atPath: folder.path) { try FileManager.default.removeItem(at: folder) }
        notifyChange()
    }

    static func notifyChange() {
        if Thread.isMainThread {
            NotificationCenter.default.post(name: didChange, object: nil)
        } else {
            DispatchQueue.main.async { NotificationCenter.default.post(name: didChange, object: nil) }
        }
    }
}
