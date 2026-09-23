import SwiftUI
import UIKit

enum EntryPhotoStore {
    private static var directory: URL {
        let fileManager = FileManager.default
        let base = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: AppGroup.identifier
        ) ?? fileManager.urls(for: .applicationSupportDirectory,
                              in: .userDomainMask).first!
        let directory = base.appendingPathComponent("JournalPhotos", isDirectory: true)
        try? fileManager.createDirectory(at: directory,
                                         withIntermediateDirectories: true)
        return directory
    }

    static func save(_ data: Data, entryID: UUID) -> String? {
        guard let source = UIImage(data: data) else { return nil }
        let image = resized(source, maxDimension: 1800)
        guard let jpeg = image.jpegData(compressionQuality: 0.82) else { return nil }
        let filename = "\(entryID.uuidString)-\(UUID().uuidString).jpg"
        do {
            try jpeg.write(to: directory.appendingPathComponent(filename), options: .atomic)
            return filename
        } catch {
            return nil
        }
    }

    static func image(named filename: String) -> UIImage? {
        UIImage(contentsOfFile: directory.appendingPathComponent(filename).path)
    }

    static func data(named filename: String) -> Data? {
        try? Data(contentsOf: directory.appendingPathComponent(filename))
    }

    static func restore(_ data: Data, named filename: String) throws {
        try data.write(to: directory.appendingPathComponent(filename), options: .atomic)
    }

    static func delete(_ filename: String) {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(filename))
    }

    static func delete(_ filenames: [String]) {
        filenames.forEach(delete)
    }

    private static func resized(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > maxDimension else { return image }
        let scale = maxDimension / longest
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        return UIGraphicsImageRenderer(size: target).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}

struct JournalPhotoGrid: View {
    let filenames: [String]

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(filenames, id: \.self) { filename in
                if let image = EntryPhotoStore.image(named: filename) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 150)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }
}

struct PendingPhotoGrid: View {
    let images: [Data]
    let remove: (Int) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(Array(images.enumerated()), id: \.offset) { index, data in
                if let image = UIImage(data: data) {
                    ZStack(alignment: .topTrailing) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 130)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        Button {
                            remove(index)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, .black.opacity(0.65))
                        }
                        .padding(6)
                    }
                }
            }
        }
    }
}