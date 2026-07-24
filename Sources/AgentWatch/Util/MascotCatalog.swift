import AppKit
import Foundation

/// A built-in, asset-free drawn mascot.
enum DrawnKind: String, CaseIterable {
    case sponge, robot, blob
    var displayName: String { rawValue.capitalized }
}

/// One appearance of a mascot: a drawn character or a loaded image.
/// Image personas carry 1+ frames; multi-frame ones flip through them as a
/// walk cycle (see MascotView.frameLoop).
enum MascotPersona {
    case drawn(DrawnKind)
    case image([NSImage])
}

/// A selectable entry in the mascot picker.
struct MascotItem: Identifiable {
    enum Source {
        case drawn(DrawnKind)
        case image([URL])   // 1+ frame URLs, in animation order
    }
    let id: String        // "drawn:sponge" | "img:penguin"
    let name: String      // "Sponge" | "Penguin"
    let source: Source
    var isImage: Bool { if case .image = source { return true }; return false }
}

/// Discovers every available mascot — the built-in drawn characters, PNGs bundled
/// in the app's Mascots/ folder, and PNGs the user drops into their own writable
/// mascots folder — persists which one is selected (or random), and hands
/// `MascotView` the persona to show on each appearance.
@MainActor
final class MascotCatalog {
    static let shared = MascotCatalog()

    private let defaults = UserDefaults.standard
    private let selectionKey = "mascotSelectionID"   // absent / "" => random rotation

    /// Writable folder for user-uploaded mascots (the .app bundle is read-only).
    /// ~/Library/Application Support/AgentWatch/Mascots/
    let userMascotsDir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("AgentWatch/Mascots", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private var imageCache: [String: NSImage] = [:]

    /// The selected mascot id, or nil for the random rotation.
    var selectionID: String? {
        get {
            let s = defaults.string(forKey: selectionKey)
            return (s == nil || s!.isEmpty) ? nil : s
        }
        set { defaults.set(newValue ?? "", forKey: selectionKey) }
    }

    /// Splits "name-3" into ("name", 3); nil frame for un-suffixed files.
    /// Frame suffixes group `foo-1.png`, `foo-2.png`, … into one animated mascot.
    private func frameParts(_ base: String) -> (stem: String, frame: Int?) {
        guard let dash = base.lastIndex(of: "-"),
              let n = Int(base[base.index(after: dash)...]), n >= 1, n <= 99 else {
            return (base, nil)
        }
        return (String(base[..<dash]), n)
    }

    /// All available mascots, in display order: drawn built-ins, then bundled
    /// images, then user-uploaded images. De-duplicated by id (bundle wins).
    /// `foo-1.png`/`foo-2.png`… group into a single multi-frame "Foo".
    func items() -> [MascotItem] {
        var out: [MascotItem] = DrawnKind.allCases.map {
            MascotItem(id: "drawn:\($0.rawValue)", name: $0.displayName, source: .drawn($0))
        }
        var seen = Set<String>()
        func addImages(_ urls: [URL]) {
            // Group by stem so frame sequences become one item.
            var groups: [String: [(frame: Int, url: URL)]] = [:]
            var singles: [(stem: String, url: URL)] = []
            for url in urls {
                let base = url.deletingPathExtension().lastPathComponent
                let (stem, frame) = frameParts(base)
                if let frame {
                    groups[stem.lowercased(), default: []].append((frame, url))
                } else {
                    singles.append((base, url))
                }
            }
            // A "-1" file with no siblings is still a 1-frame mascot under its stem.
            var entries: [(stem: String, urls: [URL])] =
                groups.map { ($0.key, $0.value.sorted { $0.frame < $1.frame }.map(\.url)) }
            entries += singles.map { ($0.stem, [$0.url]) }
            for (stem, frameURLs) in entries.sorted(by: { $0.stem.lowercased() < $1.stem.lowercased() }) {
                let id = "img:\(stem.lowercased())"
                guard !seen.contains(id) else { continue }
                seen.insert(id)
                out.append(MascotItem(id: id, name: stem.capitalized, source: .image(frameURLs)))
            }
        }
        addImages(Bundle.main.urls(forResourcesWithExtension: "png", subdirectory: "Mascots") ?? [])
        let userPNGs = (try? FileManager.default.contentsOfDirectory(
            at: userMascotsDir, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension.lowercased() == "png" } ?? []
        addImages(userPNGs)
        return out
    }

    /// Human-readable name of the current selection (for menu display).
    func selectionName() -> String {
        guard let id = selectionID else { return "Random" }
        return items().first { $0.id == id }?.name ?? "Random"
    }

    private func loadImage(_ url: URL, id: String) -> NSImage? {
        if let cached = imageCache[id] { return cached }
        guard let img = NSImage(contentsOf: url) else { return nil }
        imageCache[id] = img
        return img
    }

    private func persona(for item: MascotItem) -> MascotPersona? {
        switch item.source {
        case .drawn(let k): return .drawn(k)
        case .image(let urls):
            let frames = urls.enumerated().compactMap { i, url in
                loadImage(url, id: "\(item.id)#\(i)")
            }
            return frames.isEmpty ? nil : .image(frames)
        }
    }

    /// The persona to show for one appearance: the chosen default, else a random
    /// pick across everything available. Falls back to a drawn sponge.
    func pick() -> MascotPersona {
        let all = items()
        if let id = selectionID,
           let item = all.first(where: { $0.id == id }),
           let p = persona(for: item) {
            return p
        }
        return all.compactMap { persona(for: $0) }.randomElement() ?? .drawn(.sponge)
    }

    /// Import a user-picked image into the mascots folder as a PNG. Returns the
    /// new item's id on success (also selectable immediately).
    @discardableResult
    func addMascot(from src: URL) -> String? {
        let rawName = src.deletingPathExtension().lastPathComponent
        let safe = rawName.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }.joined(separator: "-")
        let base = safe.isEmpty ? "mascot" : safe
        let dest = userMascotsDir.appendingPathComponent(base + ".png")
        // Re-encode to PNG (handles jpg/heic/tiff picks too) so the folder is
        // always PNGs the catalog can discover.
        guard let img = NSImage(contentsOf: src),
              let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            DebugLog.write("mascot: could not read image at \(src.lastPathComponent)")
            return nil
        }
        do {
            try png.write(to: dest, options: .atomic)
            let id = "img:\(base.lowercased())"
            imageCache.removeValue(forKey: id)
            DebugLog.write("mascot: imported \(dest.lastPathComponent)")
            return id
        } catch {
            DebugLog.write("mascot: import failed: \(error)")
            return nil
        }
    }
}
