import AppKit
import SwiftUI

struct WelcomeView: View {
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var recentDocuments: [URL] = []

    var body: some View {
        HStack(spacing: 0) {
            brandPanel
                .frame(width: 292)

            Divider().opacity(0.55)

            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Recent files")
                            .font(.system(size: 22, weight: .bold))
                        Text("Continue where you left off.")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        recentDocuments = DocumentActions.recentDocuments()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help("Refresh recent files")
                }

                if recentDocuments.isEmpty {
                    ContentUnavailableView(
                        "No recent files",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Files you open in Markowski will appear here.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(recentDocuments, id: \.self) { url in
                                recentRow(url)
                            }
                        }
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 760, idealWidth: 820, minHeight: 500, idealHeight: 540)
        .background(.regularMaterial)
        .task { recentDocuments = DocumentActions.recentDocuments() }
    }

    private var brandPanel: some View {
        VStack(alignment: .leading, spacing: 22) {
            Spacer()

            // A standing figure, so the height is what's fixed and the width
            // follows from it. Forcing a square would letterbox the character
            // into the middle third of the box and render it far smaller than
            // the space allows.
            Image("MarkowskiWelcome")
                .resizable()
                .scaledToFit()
                .frame(height: 184)
                .frame(maxWidth: .infinity, alignment: .center)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 7) {
                Text("Markowski")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Text("Write, preview, and work with Markdown in one calm workspace.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 10) {
                Button {
                    if DocumentActions.createMarkdownDocument() { closeWelcome() }
                } label: {
                    Label("New Markdown File", systemImage: "square.and.pencil")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut("n", modifiers: .command)

                Button {
                    if DocumentActions.chooseAndOpenDocument() { closeWelcome() }
                } label: {
                    Label("Open Existing File…", systemImage: "folder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .keyboardShortcut("o", modifiers: .command)
            }

            Text("New files start in Downloads. After creation, Markowski saves your edits in place automatically.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .padding(30)
        .background(MarkViewDesign.secondarySurface.opacity(0.72))
    }

    private func recentRow(_ url: URL) -> some View {
        Button {
            DocumentActions.open(url)
            closeWelcome()
        } label: {
            HStack(spacing: 13) {
                Image(systemName: url.pathExtension.lowercased() == "mmd" ? "point.3.connected.trianglepath.dotted" : "doc.text")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(MarkViewDesign.accent)
                    .frame(width: 34, height: 34)
                    .background(MarkViewDesign.accentSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(url.lastPathComponent)
                        .font(.system(size: 13.5, weight: .semibold))
                        .lineLimit(1)
                    Text(url.deletingLastPathComponent().path(percentEncoded: false))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()
                Image(systemName: "arrow.up.forward")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(11)
            .contentShape(Rectangle())
            .background(Color.primary.opacity(0.035))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(MarkViewDesign.subtleBorder, lineWidth: 0.7)
            )
        }
        .buttonStyle(.plain)
    }

    private func closeWelcome() {
        if reduceMotion {
            dismissWindow(id: "welcome")
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                dismissWindow(id: "welcome")
            }
        }
    }
}
