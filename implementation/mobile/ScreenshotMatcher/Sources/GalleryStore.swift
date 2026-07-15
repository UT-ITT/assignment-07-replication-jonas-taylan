import Foundation
import UIKit

struct GalleryItem: Identifiable, Codable, Hashable {
    let id: UUID
    let fileName: String
    let createdAt: Date

    init(id: UUID = UUID(), fileName: String, createdAt: Date = Date()) {
        self.id = id
        self.fileName = fileName
        self.createdAt = createdAt
    }
}

enum GalleryKind: String {
    case sent
    case received
}

/// Persists captured/received photos as JPEG files under the app's
/// Documents directory, with a small JSON index per gallery for metadata
/// (timestamps). Kept intentionally simple (no Core Data/SwiftData) since
/// each gallery is just a flat list of images.
@MainActor
final class GalleryStore: ObservableObject {
    @Published private(set) var items: [GalleryItem] = []

    private let kind: GalleryKind
    private let directory: URL
    private let indexURL: URL

    init(kind: GalleryKind) {
        self.kind = kind
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.directory = documents.appendingPathComponent(kind.rawValue, isDirectory: true)
        self.indexURL = directory.appendingPathComponent("index.json")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        load()
    }

    func url(for item: GalleryItem) -> URL {
        directory.appendingPathComponent(item.fileName)
    }

    func image(for item: GalleryItem) -> UIImage? {
        UIImage(contentsOfFile: url(for: item).path)
    }

    @discardableResult
    func add(_ image: UIImage) -> GalleryItem? {
        guard let data = image.jpegData(compressionQuality: 0.9) else { return nil }
        let item = GalleryItem(fileName: "\(UUID().uuidString).jpg")
        do {
            try data.write(to: url(for: item))
        } catch {
            return nil
        }
        items.insert(item, at: 0)
        save()
        return item
    }

    func delete(_ item: GalleryItem) {
        try? FileManager.default.removeItem(at: url(for: item))
        items.removeAll { $0.id == item.id }
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder().decode([GalleryItem].self, from: data) else {
            return
        }
        items = decoded.sorted { $0.createdAt > $1.createdAt }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: indexURL)
    }
}
