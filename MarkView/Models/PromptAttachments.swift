import AppKit
import Foundation
import UniformTypeIdentifiers

/// An image the user attached to a prompt.
///
/// The payload is kept as already-encoded bytes plus its MIME type, because
/// that is exactly what both provider APIs want (base64 inline data). The
/// thumbnail is derived once, at attach time, so scrolling the conversation
/// never decodes the full-size image again.
struct AIImageAttachment: Identifiable, Equatable, Codable {
    let id: UUID
    let fileName: String
    let mimeType: String
    let data: Data
    let pixelSize: CGSize
    let thumbnail: NSImage?

    init(
        id: UUID = UUID(),
        fileName: String,
        mimeType: String,
        data: Data,
        pixelSize: CGSize,
        thumbnail: NSImage?
    ) {
        self.id = id
        self.fileName = fileName
        self.mimeType = mimeType
        self.data = data
        self.pixelSize = pixelSize
        self.thumbnail = thumbnail
    }

    // `NSImage` isn't `Codable`, and it doesn't need to be: the thumbnail is
    // derived from `data`, so it is rebuilt rather than stored.
    private enum CodingKeys: String, CodingKey {
        case id, fileName, mimeType, data, pixelSize
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        fileName = try container.decode(String.self, forKey: .fileName)
        mimeType = try container.decode(String.self, forKey: .mimeType)
        data = try container.decode(Data.self, forKey: .data)
        pixelSize = try container.decode(CGSize.self, forKey: .pixelSize)
        thumbnail = NSImage(data: data)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(fileName, forKey: .fileName)
        try container.encode(mimeType, forKey: .mimeType)
        try container.encode(data, forKey: .data)
        try container.encode(pixelSize, forKey: .pixelSize)
    }

    var base64: String { data.base64EncodedString() }

    var byteCountDescription: String {
        ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
    }

    var dimensionsDescription: String {
        "\(Int(pixelSize.width)) × \(Int(pixelSize.height))"
    }

    static func == (lhs: AIImageAttachment, rhs: AIImageAttachment) -> Bool {
        lhs.id == rhs.id
    }
}

/// Long pasted text, held beside the prompt instead of dumped into it.
///
/// Pasting a whole article into the composer buries the actual question and
/// makes the field unusable, so anything past `pasteThreshold` becomes a
/// numbered chip the user can open, read, and edit.
struct PastedTextItem: Identifiable, Equatable {
    let id: UUID
    /// 1-based, shown as "Pasted text 1". Stays stable when earlier chips are
    /// removed so the label never renumbers under the user.
    let number: Int
    var text: String

    init(id: UUID = UUID(), number: Int, text: String) {
        self.id = id
        self.number = number
        self.text = text
    }

    var title: String { "Pasted text \(number)" }

    var lineCount: Int {
        text.components(separatedBy: .newlines).count
    }

    var summary: String {
        "\(lineCount) lines · \(text.count) chars"
    }

    var previewLine: String {
        text
            .components(separatedBy: .newlines)
            .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })?
            .trimmingCharacters(in: .whitespaces) ?? ""
    }
}

enum PromptAttachmentLimits {
    /// Below this a paste is just typing — inserting it inline is what the
    /// user expects. Above it, the composer would become unreadable.
    static let pasteThreshold = 320
    static let pasteLineThreshold = 8

    /// Providers reject very large inline images and bill by pixels, so cap
    /// the long edge. Screenshots are usually far above this.
    static let maximumImageDimension: CGFloat = 1568
    static let maximumImageBytes = 5 * 1024 * 1024

    static func shouldBecomeChip(_ text: String) -> Bool {
        text.count > pasteThreshold
            || text.components(separatedBy: .newlines).count > pasteLineThreshold
    }
}

/// Turns arbitrary image input — a file, a drag, a clipboard paste — into an
/// `AIImageAttachment` sized for a provider.
enum ImageAttachmentLoader {
    enum LoadError: LocalizedError {
        case unreadable(String)
        case tooLarge(String)

        var errorDescription: String? {
            switch self {
            case .unreadable(let name):
                return "“\(name)” couldn’t be read as an image."
            case .tooLarge(let name):
                return "“\(name)” is too large to send even after downscaling."
            }
        }
    }

    static let supportedTypes: [UTType] = [.png, .jpeg, .gif, .bmp, .tiff, .webP, .heic, .heif]

    static func isSupported(url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else {
            return false
        }
        return supportedTypes.contains { type.conforms(to: $0) }
    }

    /// Decoding and re-encoding is genuinely slow for a big screenshot, so this
    /// is `async` and callers show progress while it runs.
    static func load(from url: URL) async throws -> AIImageAttachment {
        let name = url.lastPathComponent
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url), let image = NSImage(data: data) else {
            throw LoadError.unreadable(name)
        }
        return try await make(from: image, fileName: name)
    }

    static func load(from image: NSImage, fileName: String = "Pasted image.png") async throws -> AIImageAttachment {
        try await make(from: image, fileName: fileName)
    }

    private static func make(from image: NSImage, fileName: String) async throws -> AIImageAttachment {
        try await Task.detached(priority: .userInitiated) {
            guard let source = bitmap(from: image) else {
                throw LoadError.unreadable(fileName)
            }

            let originalSize = CGSize(width: source.pixelsWide, height: source.pixelsHigh)
            let scaled = downscaled(source, limit: PromptAttachmentLimits.maximumImageDimension)

            // PNG keeps text in screenshots crisp; JPEG is only worth it when
            // PNG comes out unreasonably large.
            var mimeType = "image/png"
            guard var encoded = scaled.representation(using: .png, properties: [:]) else {
                throw LoadError.unreadable(fileName)
            }
            if encoded.count > PromptAttachmentLimits.maximumImageBytes {
                guard let jpeg = scaled.representation(
                    using: .jpeg,
                    properties: [.compressionFactor: 0.82]
                ) else {
                    throw LoadError.tooLarge(fileName)
                }
                encoded = jpeg
                mimeType = "image/jpeg"
            }
            guard encoded.count <= PromptAttachmentLimits.maximumImageBytes else {
                throw LoadError.tooLarge(fileName)
            }

            return AIImageAttachment(
                fileName: fileName,
                mimeType: mimeType,
                data: encoded,
                pixelSize: originalSize,
                thumbnail: thumbnail(from: scaled)
            )
        }.value
    }

    private static func bitmap(from image: NSImage) -> NSBitmapImageRep? {
        if let existing = image.representations.compactMap({ $0 as? NSBitmapImageRep }).first,
           existing.pixelsWide > 0 {
            return existing
        }
        guard let tiff = image.tiffRepresentation else { return nil }
        return NSBitmapImageRep(data: tiff)
    }

    private static func downscaled(_ source: NSBitmapImageRep, limit: CGFloat) -> NSBitmapImageRep {
        let width = CGFloat(source.pixelsWide)
        let height = CGFloat(source.pixelsHigh)
        let longEdge = max(width, height)
        guard longEdge > limit, longEdge > 0 else { return source }

        let scale = limit / longEdge
        let targetWidth = Int((width * scale).rounded())
        let targetHeight = Int((height * scale).rounded())

        guard let destination = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: targetWidth,
            pixelsHigh: targetHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return source
        }
        destination.size = NSSize(width: targetWidth, height: targetHeight)

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        guard let context = NSGraphicsContext(bitmapImageRep: destination) else { return source }
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        source.draw(in: NSRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
        context.flushGraphics()

        return destination
    }

    private static func thumbnail(from source: NSBitmapImageRep) -> NSImage? {
        let image = NSImage(size: NSSize(width: source.pixelsWide, height: source.pixelsHigh))
        image.addRepresentation(source)
        return image
    }
}
