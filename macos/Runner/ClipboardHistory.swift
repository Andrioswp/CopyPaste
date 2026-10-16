import AppKit
import CryptoKit

enum ClipKind: String, Codable {
    case text
    case rich
    case image
    case files
}

struct ClipItem: Codable {
    var id: String
    var kind: ClipKind
    var text: String
    var blob: String?
    var files: [String]
    var sourceApp: String
    /// Bundle id of the frontmost app at copy time (may be empty for older history).
    var sourceBundleId: String
    var createdAt: Double // milliseconds since 1970
    var pinned: Bool
    var bytes: Int
    var width: Int
    var height: Int
    var hash: String

    enum CodingKeys: String, CodingKey {
        case id, kind, text, blob, files, sourceApp, sourceBundleId
        case createdAt, pinned, bytes, width, height, hash
    }

    init(
        id: String,
        kind: ClipKind,
        text: String,
        blob: String?,
        files: [String],
        sourceApp: String,
        sourceBundleId: String = "",
        createdAt: Double,
        pinned: Bool,
        bytes: Int,
        width: Int,
        height: Int,
        hash: String
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.blob = blob
        self.files = files
        self.sourceApp = sourceApp
        self.sourceBundleId = sourceBundleId
        self.createdAt = createdAt
        self.pinned = pinned
        self.bytes = bytes
        self.width = width
        self.height = height
        self.hash = hash
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        kind = try c.decode(ClipKind.self, forKey: .kind)
        text = try c.decode(String.self, forKey: .text)
        blob = try c.decodeIfPresent(String.self, forKey: .blob)
        files = try c.decodeIfPresent([String].self, forKey: .files) ?? []
        sourceApp = try c.decodeIfPresent(String.self, forKey: .sourceApp) ?? ""
        sourceBundleId = try c.decodeIfPresent(String.self, forKey: .sourceBundleId) ?? ""
        createdAt = try c.decode(Double.self, forKey: .createdAt)
        pinned = try c.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
        bytes = try c.decodeIfPresent(Int.self, forKey: .bytes) ?? 0
        width = try c.decodeIfPresent(Int.self, forKey: .width) ?? 0
        height = try c.decodeIfPresent(Int.self, forKey: .height) ?? 0
        hash = try c.decode(String.self, forKey: .hash)
    }

    var preview: String {
        switch kind {
        case .image:
            return width > 0 && height > 0 ? "Изображение \(width)×\(height)" : "Изображение"
        case .files:
            if files.isEmpty { return "Файлы" }
            let names = files.map { ($0 as NSString).lastPathComponent }
            if names.count == 1 { return names[0] }
            return "\(names[0]) +\(names.count - 1)"
        default:
            // Long enough for the hover peek card; the list row still truncates.
            return String(text.prefix(900))
        }
    }

    var searchText: String {
        var parts: [String] = [preview.lowercased(), text.prefix(600).lowercased()]
        parts.append(contentsOf: files.map { ($0 as NSString).lastPathComponent.lowercased() })
        return parts.joined(separator: " ")
    }

    /// Payload handed to Flutter. Long text never crosses the bridge: native
    /// owns the clipboard payload and performs the paste itself.
    func dict(blobsDir: URL) -> [String: Any] {
        var payload: [String: Any] = [
            "id": id,
            "kind": kind.rawValue,
            "preview": preview,
            "search": searchText,
            "files": files,
            "fileNames": files.prefix(8).map { ($0 as NSString).lastPathComponent },
            "primaryFile": files.first ?? "",
            "fileCount": files.count,
            "sourceApp": sourceApp,
            "sourceBundleId": sourceBundleId,
            "createdAt": createdAt,
            "pinned": pinned,
            "bytes": bytes,
            "width": width,
            "height": height,
        ]
        if let blob {
            payload["blob"] = blobsDir.appendingPathComponent(blob).path
        }
        if let icon = AppIconCache.shared.path(bundleId: sourceBundleId, name: sourceApp) {
            payload["sourceIcon"] = icon
        }
        return payload
    }
}

/// Watches NSPasteboard.general, keeps a persisted history and writes items
/// back to the pasteboard.
final class ClipboardHistory {
    private(set) var items: [ClipItem] = []
    var onChange: (() -> Void)?

    let supportDir: URL
    let blobsDir: URL

    private let fileManager = FileManager.default
    private var timer: Timer?
    private var lastChangeCount = -1
    private var ignoreChangeCount = -2
    private var saveWork: DispatchWorkItem?

    private let maxTextBytes = 2 * 1024 * 1024
    private let maxImageBytes = 16 * 1024 * 1024

    private static let skippedTypes: Set<String> = [
        "org.nspasteboard.ConcealedType",
        "org.nspasteboard.TransientType",
        "org.nspasteboard.AutoGeneratedType",
        "com.agilebits.onepassword",
        "de.petermaurer.TransientPasteboardType",
    ]

    init() {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        supportDir = base.appendingPathComponent("CopyPaste", isDirectory: true)
        blobsDir = supportDir.appendingPathComponent("blobs", isDirectory: true)
        try? fileManager.createDirectory(at: blobsDir, withIntermediateDirectories: true)
        load()
    }

    // MARK: - Monitoring

    func start() {
        lastChangeCount = NSPasteboard.general.changeCount
        if let current = readItem(from: NSPasteboard.general) {
            insert(current)
        }
        let timer = Timer(timeInterval: 0.35, repeats: true) { [weak self] _ in
            self?.poll()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        guard pasteboard.changeCount != ignoreChangeCount else { return }
        guard let item = readItem(from: pasteboard) else { return }
        insert(item)
    }

    // MARK: - Reading the pasteboard

    private func readItem(from pasteboard: NSPasteboard) -> ClipItem? {
        if let types = pasteboard.types {
            for type in types where Self.skippedTypes.contains(type.rawValue) {
                return nil
            }
        }
        let front = NSWorkspace.shared.frontmostApplication
        let source = front?.localizedName ?? ""
        let sourceBundleId = front?.bundleIdentifier ?? ""
        let now = Date().timeIntervalSince1970 * 1000

        // 1. Copied files / folders.
        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], !urls.isEmpty {
            let paths = urls.map { $0.path }
            let text = paths.joined(separator: "\n")
            return ClipItem(
                id: UUID().uuidString,
                kind: .files,
                text: text,
                blob: nil,
                files: paths,
                sourceApp: source,
                sourceBundleId: sourceBundleId,
                createdAt: now,
                pinned: false,
                bytes: text.utf8.count,
                width: 0,
                height: 0,
                hash: Self.hash(text)
            )
        }

        // 2. Images.
        if let png = pasteboard.data(forType: .png), let image = NSImage(data: png) {
            if let item = imageItem(
                data: png, image: image, source: source, sourceBundleId: sourceBundleId, now: now
            ) {
                return item
            }
        }
        if let tiff = pasteboard.data(forType: .tiff), let image = NSImage(data: tiff),
           let png = Self.pngData(from: image) {
            if let item = imageItem(
                data: png, image: image, source: source, sourceBundleId: sourceBundleId, now: now
            ) {
                return item
            }
        }

        // 3. Rich text (keeps formatting when pasted back).
        if let rtf = pasteboard.data(forType: .rtf), rtf.count < maxTextBytes,
           let plain = pasteboard.string(forType: .string), !plain.isEmpty {
            let blobName = "\(UUID().uuidString).rtf"
            let url = blobsDir.appendingPathComponent(blobName)
            try? rtf.write(to: url)
            return ClipItem(
                id: UUID().uuidString,
                kind: .rich,
                text: String(plain.prefix(maxTextBytes)),
                blob: blobName,
                files: [],
                sourceApp: source,
                sourceBundleId: sourceBundleId,
                createdAt: now,
                pinned: false,
                bytes: rtf.count,
                width: 0,
                height: 0,
                hash: Self.hash(plain)
            )
        }

        // 4. Plain text.
        if let string = pasteboard.string(forType: .string),
           !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return ClipItem(
                id: UUID().uuidString,
                kind: .text,
                text: String(string.prefix(maxTextBytes)),
                blob: nil,
                files: [],
                sourceApp: source,
                sourceBundleId: sourceBundleId,
                createdAt: now,
                pinned: false,
                bytes: string.utf8.count,
                width: 0,
                height: 0,
                hash: Self.hash(string)
            )
        }
        return nil
    }

    private func imageItem(
        data: Data,
        image: NSImage,
        source: String,
        sourceBundleId: String,
        now: Double
    ) -> ClipItem? {
        guard data.count < maxImageBytes else { return nil }
        let blobName = "\(UUID().uuidString).png"
        let url = blobsDir.appendingPathComponent(blobName)
        do {
            try data.write(to: url)
        } catch {
            return nil
        }
        let size = image.size
        return ClipItem(
            id: UUID().uuidString,
            kind: .image,
            text: "",
            blob: blobName,
            files: [],
            sourceApp: source,
            sourceBundleId: sourceBundleId,
            createdAt: now,
            pinned: false,
            bytes: data.count,
            width: Int(size.width.rounded()),
            height: Int(size.height.rounded()),
            hash: Self.hash(data)
        )
    }

    // MARK: - History mutation

    private func insert(_ item: ClipItem) {
        if let index = items.firstIndex(where: { $0.hash == item.hash }) {
            var existing = items[index]
            if existing.pinned {
                existing.createdAt = item.createdAt
                items[index] = existing
                scheduleSave()
                onChange?()
                return
            }
            removeBlob(of: existing)
            items.remove(at: index)
        }
        items.insert(item, at: 0)
        trim()
        scheduleSave()
        onChange?()
    }

    func writeToPasteboard(_ item: ClipItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        switch item.kind {
        case .text:
            pasteboard.setString(item.text, forType: .string)
        case .rich:
            if let blob = item.blob, let data = try? Data(contentsOf: blobsDir.appendingPathComponent(blob)) {
                pasteboard.setData(data, forType: .rtf)
            }
            pasteboard.setString(item.text, forType: .string)
        case .image:
            if let blob = item.blob, let data = try? Data(contentsOf: blobsDir.appendingPathComponent(blob)) {
                pasteboard.setData(data, forType: .png)
                if let image = NSImage(data: data), let tiff = image.tiffRepresentation {
                    pasteboard.setData(tiff, forType: .tiff)
                }
            }
        case .files:
            let urls = item.files.map { URL(fileURLWithPath: $0) as NSURL }
            if !pasteboard.writeObjects(urls) {
                pasteboard.setString(item.text, forType: .string)
            }
        }
        ignoreChangeCount = pasteboard.changeCount
        lastChangeCount = pasteboard.changeCount
    }

    func item(with id: String) -> ClipItem? {
        items.first { $0.id == id }
    }

    @discardableResult
    func setPinned(id: String, pinned: Bool) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return false }
        items[index].pinned = pinned
        scheduleSave()
        onChange?()
        return true
    }

    @discardableResult
    func remove(id: String) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return false }
        let item = items.remove(at: index)
        removeBlob(of: item)
        scheduleSave()
        onChange?()
        return true
    }

    func clear(keepPinned: Bool) {
        if keepPinned {
            for item in items where !item.pinned {
                removeBlob(of: item)
            }
            items.removeAll { !$0.pinned }
        } else {
            for item in items {
                removeBlob(of: item)
            }
            items.removeAll()
        }
        scheduleSave()
        onChange?()
    }

    func applyMaxItems(_ value: Int) {
        UserDefaults.standard.set(value, forKey: PrefKey.maxItems)
        trim()
        scheduleSave()
        onChange?()
    }

    private func trim() {
        let limit = AppPrefs.maxItems
        guard items.count > limit else { return }
        var kept: [ClipItem] = []
        kept.reserveCapacity(limit)
        var unpinned = 0
        for item in items {
            if item.pinned {
                kept.append(item)
                continue
            }
            if unpinned < limit {
                unpinned += 1
                kept.append(item)
            } else {
                removeBlob(of: item)
            }
        }
        items = kept
    }

    private func removeBlob(of item: ClipItem) {
        guard let blob = item.blob else { return }
        try? fileManager.removeItem(at: blobsDir.appendingPathComponent(blob))
    }

    func snapshot() -> [[String: Any]] {
        items.map { $0.dict(blobsDir: blobsDir) }
    }

    // MARK: - Persistence

    private var storeURL: URL { supportDir.appendingPathComponent("history.json") }

    private func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.save() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(items)
            try data.write(to: storeURL, options: .atomic)
        } catch {
            NSLog("CopyPaste: failed to save history: \(error.localizedDescription)")
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: storeURL) else { return }
        do {
            items = try JSONDecoder().decode([ClipItem].self, from: data)
        } catch {
            NSLog("CopyPaste: failed to read history: \(error.localizedDescription)")
            items = []
        }
    }

    // MARK: - Helpers

    static func hash(_ string: String) -> String {
        hash(Data(string.utf8))
    }

    static func hash(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else {
            return nil
        }
        return rep.representation(using: .png, properties: [:])
    }
}
