import SwiftUI

struct FindBarView: View {
    @ObservedObject var navigator: DocumentNavigator
    let documentText: String
    let onClose: () -> Void

    @FocusState private var isFieldFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.caption)

            TextField("Search…", text: $navigator.searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($isFieldFocused)
                .onChange(of: navigator.searchQuery) { _, newQuery in
                    navigator.performSearch(query: newQuery, in: documentText)
                }
                .onSubmit {
                    navigator.nextMatch()
                }

            if !navigator.searchMatches.isEmpty, let idx = navigator.selectedMatchIndex {
                Text("\(idx + 1) of \(navigator.searchMatches.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
            } else if !navigator.searchQuery.isEmpty {
                Text("No Results")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 2) {
                Button(action: { navigator.previousMatch() }) {
                    Image(systemName: "chevron.up")
                        .font(.caption2.bold())
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: [.shift])
                .disabled(navigator.searchMatches.isEmpty)

                Button(action: { navigator.nextMatch() }) {
                    Image(systemName: "chevron.down")
                        .font(.caption2.bold())
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: [])
                .disabled(navigator.searchMatches.isEmpty)
            }

            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: Color.black.opacity(0.12), radius: 7, x: 0, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.8)
        )
        .frame(minWidth: 300, maxWidth: 340, minHeight: 36, maxHeight: 38)
        .onExitCommand(perform: onClose)
        .onAppear {
            isFieldFocused = true
            if !navigator.searchQuery.isEmpty {
                navigator.performSearch(query: navigator.searchQuery, in: documentText)
            }
        }
    }
}
