import CaptureKit
import Foundation

/// The finished captures: one .zip per recording in the app's Documents folder, which is also
/// visible in the Files app (On My iPhone > Splat Capture) and in Finder when the phone is plugged in.
final class CaptureLibrary: ObservableObject {
    struct Item: Identifiable, Hashable {
        let url: URL
        let date: Date
        let bytes: Int64
        var id: URL { url }
        var name: String { url.deletingPathExtension().lastPathComponent }
    }

    @Published private(set) var items: [Item] = []

    static var folder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    init() { refresh() }

    func refresh() {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: Self.folder, includingPropertiesForKeys: keys)) ?? []
        items = urls.filter { $0.pathExtension == "zip" }.map { url in
            let v = try? url.resourceValues(forKeys: Set(keys))
            return Item(url: url, date: v?.contentModificationDate ?? .distantPast, bytes: Int64(v?.fileSize ?? 0))
        }.sorted { $0.date > $1.date }
    }

    func delete(_ item: Item) {
        try? FileManager.default.removeItem(at: item.url)
        refresh()
    }

    /// "vase-window-light_2026-10-14_153012", or "capture_2026-10-14_153012" without a name.
    static func newName(_ name: String = "", date: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd_HHmmss"
        let slug = captureSlug(name)
        return (slug.isEmpty ? "capture" : slug) + "_" + f.string(from: date)
    }

    /// Zips a finished capture folder into Documents and removes the folder. The zip holds the
    /// folder itself (capture_<date>/video.mov, ...), which is what Splat Studio expects.
    static func store(_ folder: URL) throws -> URL {
        let dest = Self.folder.appendingPathComponent(folder.lastPathComponent + ".zip")
        var coordinatorError: NSError?
        var copyError: Error?
        // Asking to read a folder "for uploading" makes the system zip it for us.
        NSFileCoordinator().coordinate(readingItemAt: folder, options: [.forUploading], error: &coordinatorError) { zip in
            do {
                if FileManager.default.fileExists(atPath: dest.path) {
                    try FileManager.default.removeItem(at: dest)
                }
                try FileManager.default.copyItem(at: zip, to: dest)
            } catch {
                copyError = error
            }
        }
        if let e = coordinatorError ?? copyError { throw e }
        try? FileManager.default.removeItem(at: folder)
        return dest
    }
}
