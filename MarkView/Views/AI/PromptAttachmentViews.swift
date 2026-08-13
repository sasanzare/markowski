import AppKit
import SwiftUI

/// One item in the composer's attachment strip while it is being prepared or
/// waiting to be sent.
enum ComposerAttachment: Identifiable, Equatable {
    /// Decoding and downscaling a screenshot takes real time, so the chip
    /// exists — with progress — before the image does.
    case loadingImage(id: UUID, fileName: String)
    case image(AIImageAttachment)
    case failed(id: UUID, fileName: String, message: String)
    case pastedText(PastedTextItem)
    case textFile(id: UUID, name: String, contents: String)
    /// Reading a PDF or a spreadsheet takes real time, so the chip exists —
    /// with progress — before the text does.
    case loadingDocument(id: UUID, fileName: String)
    case document(ExtractedDocument)

    var id: UUID {
        switch self {
        case .loadingImage(let id, _): return id
        case .image(let attachment): return attachment.id
        case .failed(let id, _, _): return id
        case .pastedText(let item): return item.id
        case .textFile(let id, _, _): return id
        case .loadingDocument(let id, _): return id
        case .document(let document): return document.id
        }
    }

    var isLoading: Bool {
        switch self {
        case .loadingImage, .loadingDocument: return true
        default: return false
        }
    }

    var extractedDocument: ExtractedDocument? {
        if case .document(let document) = self { return document }
        return nil
    }

    var imageAttachment: AIImageAttachment? {
        if case .image(let attachment) = self { return attachment }
        return nil
    }

    var pastedItem: PastedTextItem? {
        if case .pastedText(let item) = self { return item }
        return nil
    }
}

// MARK: - Extracted text preview

/// Shows exactly the text an attached file was turned into.
///
/// Attaching a PDF is an act of faith otherwise: the user cannot tell whether
/// the model got their tables, whether the columns survived, or where it was
/// cut off. This makes the answer checkable.
struct ExtractedDocumentSheet: View {
    let document: ExtractedDocument
    var onRemove: (() -> Void)?
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: document.kind.symbolName)
                    .font(.system(size: 15))
                    .foregroundStyle(MarkViewDesign.accent)

                VStack(alignment: .leading, spacing: 1) {
                    Text(document.fileName)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text("\(document.summary) · \(document.text.count) characters read")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                if let onRemove {
                    Button("Remove", action: onRemove)
                        .controlSize(.small)
                }
                Button("Done", action: onClose)
                    .controlSize(.small)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)

            Divider()

            if document.isTruncated {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                    Text("This file was longer than fits in one prompt, so only the beginning is attached.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Color.orange.opacity(0.10))
            }

            ScrollView {
                Text(document.text)
                    .font(.system(size: 11.5, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            }
        }
        .frame(width: 620, height: 520)
    }
}

// MARK: - Document chip

/// An attached PDF, Word file, or spreadsheet.
///
/// The subtitle carries what the user needs to trust it — the kind of file, how
/// much of it there is, and whether it had to be shortened — because the whole
/// question with an attached document is "does the model actually have my
/// file?". Clicking opens the extracted text, so that is answerable rather
/// than a matter of faith.
struct ComposerDocumentChip: View {
    let document: ExtractedDocument
    let onOpen: () -> Void
    let onRemove: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 8) {
                Image(systemName: document.kind.symbolName)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(MarkViewDesign.accent)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(document.fileName)
                        .font(.system(size: 11.5, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    HStack(spacing: 4) {
                        Text(document.summary)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        if document.isTruncated {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(.orange)
                        }
                    }
                }
                .frame(maxWidth: 150, alignment: .leading)
            }
            .padding(.horizontal, 9)
            .frame(height: 46)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(MarkViewDesign.controlSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(MarkViewDesign.strongBorder, lineWidth: 0.7)
            )
        }
        .buttonStyle(.plain)
        .help(document.isTruncated
              ? "\(document.fileName) — only the first part fits, so the rest wasn’t attached. Click to read what the model will see."
              : "\(document.fileName) — click to read exactly what the model will see")
        .overlay(alignment: .topTrailing) {
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(Color.white, Color.black.opacity(0.55))
            }
            .buttonStyle(.plain)
            .padding(3)
            .opacity(isHovered ? 1 : 0)
            .accessibilityLabel("Remove \(document.fileName)")
        }
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) { isHovered = hovering }
        }
    }
}

/// Shown while a document is being read.
struct ComposerDocumentLoadingChip: View {
    let fileName: String

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(fileName)
                    .font(.system(size: 11.5, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("Reading…")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 150, alignment: .leading)
        }
        .padding(.horizontal, 9)
        .frame(height: 46)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(MarkViewDesign.controlSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(MarkViewDesign.strongBorder, lineWidth: 0.7)
        )
        .accessibilityLabel("Reading \(fileName)")
    }
}

// MARK: - Image chip

struct ComposerImageChip: View {
    let attachment: AIImageAttachment
    let onRemove: () -> Void
    let onOpen: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    private let side: CGFloat = 54

    var body: some View {
        Button(action: onOpen) {
            thumbnail
                .overlay(alignment: .topTrailing) { removeButton }
                .overlay { hoverOverlay }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.14)) { isHovered = hovering }
        }
        .help("\(attachment.fileName) · \(attachment.dimensionsDescription) · \(attachment.byteCountDescription)")
        .accessibilityLabel("Attached image \(attachment.fileName)")
    }

    private var thumbnail: some View {
        Group {
            if let image = attachment.thumbnail {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.primary.opacity(isHovered ? 0.28 : 0.14), lineWidth: 0.8)
        )
    }

    /// Hovering the thumbnail is how the user inspects what they attached, so
    /// it says what the image *is* rather than just dimming.
    @ViewBuilder
    private var hoverOverlay: some View {
        if isHovered {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.black.opacity(0.42))

                Image(systemName: "eye")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.bottom, 14)

                Text(attachment.dimensionsDescription)
                    .font(.system(size: 8.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
                    .padding(.horizontal, 3)
                    .padding(.bottom, 3)
            }
            .frame(width: side, height: side)
            .transition(.opacity)
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var removeButton: some View {
        if isHovered {
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 7.5, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 15, height: 15)
                    .background(Circle().fill(Color.black.opacity(0.72)))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.5), lineWidth: 0.6))
            }
            .buttonStyle(.plain)
            .offset(x: 5, y: -5)
            .transition(.opacity.combined(with: .scale(scale: 0.7)))
            .accessibilityLabel("Remove \(attachment.fileName)")
        }
    }
}

/// The placeholder shown while an image is decoded and downscaled.
struct ComposerImageLoadingChip: View {
    let fileName: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shimmerPhase: CGFloat = -1

    private let side: CGFloat = 54

    var body: some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(Color.primary.opacity(0.07))
            .frame(width: side, height: side)
            .overlay {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.72)
            }
            .overlay { shimmer }
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.8)
            )
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
                    shimmerPhase = 1.6
                }
            }
            .help("Preparing \(fileName)…")
            .accessibilityLabel("Preparing image \(fileName)")
    }

    @ViewBuilder
    private var shimmer: some View {
        if !reduceMotion {
            LinearGradient(
                colors: [.clear, Color.white.opacity(0.22), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: side * 0.7)
            .offset(x: shimmerPhase * side)
            .allowsHitTesting(false)
        }
    }
}

struct ComposerFailedChip: View {
    let fileName: String
    let message: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text(fileName)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                Text(message)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss failed attachment")
        }
        .padding(.horizontal, 9)
        .frame(height: 38)
        .background(Color.orange.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.28), lineWidth: 0.7)
        )
    }
}

// MARK: - Pasted text chip

struct PastedTextChip: View {
    let item: PastedTextItem
    let onOpen: () -> Void
    let onRemove: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 7) {
                Image(systemName: "doc.plaintext")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(item.summary)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                }

                if isHovered {
                    Button(action: onRemove) {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 15, height: 15)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                    .accessibilityLabel("Remove \(item.title)")
                }
            }
            .padding(.horizontal, 9)
            .frame(height: 38)
            .background(isHovered ? Color.primary.opacity(0.095) : Color.primary.opacity(0.055))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color.primary.opacity(isHovered ? 0.22 : 0.12), lineWidth: 0.7)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.13)) { isHovered = hovering }
        }
        .help("Click to view or edit \(item.title)")
    }
}

// MARK: - Editors and viewers

/// Opening a pasted chip shows the whole thing, editable, without ever having
/// let it flood the composer.
struct PastedTextEditorSheet: View {
    let title: String
    @State var text: String
    let onSave: (String) -> Void
    let onRemove: () -> Void
    let onCancel: () -> Void

    @FocusState private var isEditorFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "doc.plaintext")
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text("\(text.count) chars")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(role: .destructive, action: onRemove) {
                    Label("Remove", systemImage: "trash")
                        .font(.system(size: 11.5))
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            PlainTextEditor(text: $text)
                .frame(minWidth: 520, minHeight: 320)

            Divider()

            HStack(spacing: 10) {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Done") { onSave(text) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(width: 620, height: 460)
    }
}

/// Clicking an attached image opens it at a readable size.
struct ImagePreviewSheet: View {
    let attachment: AIImageAttachment
    let onRemove: (() -> Void)?
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
                Text(attachment.fileName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text("\(attachment.dimensionsDescription) · \(attachment.byteCountDescription)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                if let onRemove {
                    Button(role: .destructive, action: onRemove) {
                        Label("Remove", systemImage: "trash")
                            .font(.system(size: 11.5))
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            ScrollView([.horizontal, .vertical]) {
                if let image = attachment.thumbnail {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 760, maxHeight: 520)
                        .padding(16)
                } else {
                    Text("This image couldn’t be decoded.")
                        .foregroundStyle(.secondary)
                        .padding(40)
                }
            }
            .frame(minWidth: 420, minHeight: 300)

            Divider()

            HStack {
                Spacer()
                Button("Done", action: onClose)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(width: 800, height: 620)
    }
}

/// A monospaced `NSTextView` editor. SwiftUI's `TextEditor` gets sluggish with
/// the multi-thousand-line pastes this sheet exists to hold.
struct PlainTextEditor: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        textView.isEditable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.delegate = context.coordinator
        textView.string = text
        // A very long paste is unreadable when it is also re-wrapped, but
        // horizontal scrolling is worse. Wrap, and keep layout cheap.
        textView.textContainer?.widthTracksTextView = true
        context.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = nsView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PlainTextEditor
        weak var textView: NSTextView?

        init(_ parent: PlainTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }
}
