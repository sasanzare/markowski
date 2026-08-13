import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// A starting point for an empty document.
///
/// A new file used to open as a genuinely blank preview: nothing rendered,
/// nothing to click, and no indication that editing happens by double-clicking
/// a block — of which there were none. This gives the document its first
/// blocks, and says how the editing surface works while it's doing it.
struct DocumentStarterView: View {
    let onChoose: (String) -> Void
    let onOpenSource: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hoveredTemplate: DocumentTemplate.ID?
    @State private var hasAppeared = false
    @State private var isDropTargeted = false

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                headline

                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(Array(DocumentTemplate.all.enumerated()), id: \.element.id) { index, template in
                        templateCard(template, index: index)
                    }
                }
                .frame(maxWidth: 520)

                existingFileRow

                tips
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 32)
            .padding(.top, 56)
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.accentColor.opacity(0.07))
                    )
                    .padding(20)
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isDropTargeted)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            openDroppedFile(from: providers)
        }
        .onAppear {
            guard !hasAppeared else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3)) {
                hasAppeared = true
            }
        }
    }

    /// Opening an existing file was only reachable from the screen this
    /// replaces, so it comes along rather than being lost.
    private var existingFileRow: some View {
        HStack(spacing: 7) {
            Text("or")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)

            Button(action: openFilePanel) {
                Label("Open an existing file…", systemImage: "folder")
                    .font(.system(size: 11.5, weight: .medium))
            }
            .buttonStyle(.link)
            .help("Open a .md, .markdown, or .mmd file")

            Text("· or drop one anywhere here")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .opacity(hasAppeared ? 1 : 0)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.3).delay(0.18), value: hasAppeared)
    }

    private func openFilePanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = MarkViewDocument.readableContentTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
    }

    private func openDroppedFile(from providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first, provider.canLoadObject(ofClass: URL.self) else {
            return false
        }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url,
                  ["md", "markdown", "mmd"].contains(url.pathExtension.lowercased()) else { return }
            DispatchQueue.main.async {
                NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
            }
        }
        return true
    }

    private var headline: some View {
        VStack(spacing: 7) {
            Image(systemName: "doc.badge.plus")
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(.secondary)
                .padding(.bottom, 3)

            Text("Start this document")
                .font(.system(size: 19, weight: .semibold))

            Text("Pick a starting point — you can change everything afterwards.")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: hasAppeared || reduceMotion ? 0 : 8)
    }

    private func templateCard(_ template: DocumentTemplate, index: Int) -> some View {
        let isHovered = hoveredTemplate == template.id

        return Button {
            onChoose(template.body)
        } label: {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: template.symbol)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 26, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.accentColor.opacity(isHovered ? 0.20 : 0.12))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(template.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(template.detail)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.primary.opacity(isHovered ? 0.085 : 0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(
                        isHovered ? Color.accentColor.opacity(0.34) : Color.primary.opacity(0.10),
                        lineWidth: isHovered ? 1 : 0.7
                    )
            )
            .scaleEffect(isHovered && !reduceMotion ? 1.015 : 1)
        }
        .buttonStyle(.plain)
        .help(template.detail)
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.13)) {
                hoveredTemplate = hovering ? template.id : (hoveredTemplate == template.id ? nil : hoveredTemplate)
            }
        }
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: hasAppeared || reduceMotion ? 0 : 10)
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.26).delay(Double(index) * 0.035),
            value: hasAppeared
        )
    }

    private var tips: some View {
        VStack(alignment: .leading, spacing: 6) {
            tip("hand.tap", "Double-click any block to edit its Markdown in place.")
            tip("plus.circle", "Hover between two blocks for a + to insert a new one.")
            tip("sidebar.left", "⌘⌥F opens the formatting panel — styles, lists, tables, Persian tools.")
            tip("chevron.left.forwardslash.chevron.right", "Prefer raw Markdown? Switch to Source at the top.")

            Divider()
                .opacity(0.4)
                .padding(.vertical, 2)

            Button(action: onOpenSource) {
                HStack(spacing: 8) {
                    Image(systemName: "text.alignleft")
                        .font(.system(size: 10, weight: .medium))
                        .frame(width: 14)
                    Text("Start typing in Source instead")
                        .font(.system(size: 11, weight: .medium))
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .help("Switch to the raw Markdown editor and start from a blank file")
        }
        .frame(maxWidth: 420, alignment: .leading)
        .padding(13)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.7)
        )
        .opacity(hasAppeared ? 1 : 0)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.3).delay(0.22), value: hasAppeared)
    }

    private func tip(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 14)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

enum DocumentStarter {
    /// Whether the starter should stand in for the preview.
    ///
    /// This is the rule that used to live in `ContentView` as "no text and no
    /// file means show a drop target instead of the editor" — which took ⌘N to
    /// a screen with no toolbar, no panels, and a New button that only made
    /// another copy of itself. A new document is a document: it gets the real
    /// editor, and the starter fills the empty preview inside it.
    static func shouldOffer(text: String, fileExtension: String) -> Bool {
        guard fileExtension.lowercased() != "mmd" else { return false }
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct DocumentTemplate: Identifiable {
    let id: String
    let title: String
    let detail: String
    let symbol: String
    let body: String

    /// Every template lands the caret in a real document with real blocks —
    /// an empty file has nothing to double-click, which is exactly what made
    /// a new document feel broken.
    static let all: [DocumentTemplate] = [
        DocumentTemplate(
            id: "blank",
            title: "Blank note",
            detail: "A title and one paragraph to start typing into.",
            symbol: "doc",
            body: """
            # Untitled

            Start writing here.
            """
        ),
        DocumentTemplate(
            id: "notes",
            title: "Meeting notes",
            detail: "Attendees, discussion, and action items.",
            symbol: "person.2",
            body: """
            # Meeting notes

            **Date:** \(DocumentTemplate.today)
            **Attendees:**

            ## Discussion

            -\u{0020}

            ## Action items

            - [ ] \u{0020}
            """
        ),
        DocumentTemplate(
            id: "checklist",
            title: "Checklist",
            detail: "A task list you can tick off.",
            symbol: "checklist",
            body: """
            # Checklist

            - [ ] First task
            - [ ] Second task
            - [ ] Third task
            """
        ),
        DocumentTemplate(
            id: "table",
            title: "Table",
            detail: "A three-column table ready to fill in.",
            symbol: "tablecells",
            body: """
            # Untitled

            | Column 1 | Column 2 | Column 3 |
            | --- | --- | --- |
            |  |  |  |
            |  |  |  |
            """
        ),
        DocumentTemplate(
            id: "readme",
            title: "Project README",
            detail: "Overview, install, usage, and licence headings.",
            symbol: "shippingbox",
            body: """
            # Project name

            One sentence on what this does.

            ## Installation

            ```bash
            # install steps
            ```

            ## Usage

            Describe the common case here.

            ## Licence

            MIT
            """
        ),
        DocumentTemplate(
            id: "persian",
            title: "سند فارسی",
            detail: "A right-to-left document set up for Persian.",
            symbol: "character.textbox",
            body: """
            <div dir="rtl" markdown="1">

            # عنوان سند

            متن خود را از این‌جا بنویسید.

            </div>
            """
        )
    ]

    private static var today: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: Date())
    }
}
