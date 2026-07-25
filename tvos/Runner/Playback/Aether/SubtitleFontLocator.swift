import Foundation

/// Locates the Flutter-bundled Noto Sans so subtitle renderers always have a
/// resolvable fallback font (tvOS/iOS have no fontconfig configuration), and
/// materializes in-container font attachments (MKV embedded TTF/OTF) into a
/// directory libass can scan.
enum SubtitleFontLocator {
    static let fontFamily = "Noto Sans"

    static func bundledFontsDirectory() -> String? {
        var candidates: [String] = []
        if let frameworksPath = Bundle.main.privateFrameworksPath {
            candidates.append("\(frameworksPath)/App.framework/flutter_assets/assets/fonts")
        }
        if let resourcePath = Bundle.main.resourcePath {
            candidates.append("\(resourcePath)/flutter_assets/assets/fonts")
        }
        return candidates.first {
            FileManager.default.fileExists(atPath: "\($0)/NotoSans-Regular.ttf")
        }
    }

    /// Writes embedded font attachments to a session temp directory (seeded
    /// with the bundled fallback font) and returns its path. Returns the
    /// plain bundled directory when there are no attachments.
    static func materializeFontsDirectory(attachments: [(filename: String, data: Data)])
        -> String?
    {
        guard !attachments.isEmpty else { return bundledFontsDirectory() }
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("moonfin-sub-fonts", isDirectory: true)
        let fm = FileManager.default
        try? fm.removeItem(at: dir)
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            return bundledFontsDirectory()
        }
        if let bundled = bundledFontsDirectory() {
            let src = URL(fileURLWithPath: bundled).appendingPathComponent("NotoSans-Regular.ttf")
            try? fm.copyItem(at: src, to: dir.appendingPathComponent("NotoSans-Regular.ttf"))
        }
        for attachment in attachments {
            let name = URL(fileURLWithPath: attachment.filename).lastPathComponent
            guard !name.isEmpty else { continue }
            try? attachment.data.write(to: dir.appendingPathComponent(name))
        }
        return dir.path
    }
}
