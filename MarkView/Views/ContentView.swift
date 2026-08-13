import AppKit
import SwiftUI

struct ContentView: View {
    @Binding var document: MarkViewDocument
    let fileURL: URL?

    var body: some View {
        DocumentView(document: $document, fileURL: fileURL)
            .navigationTitle(fileURL?.lastPathComponent ?? "Untitled")
            .onAppear {
                guard let fileURL else { return }
                NSDocumentController.shared.noteNewRecentDocumentURL(fileURL)
            }
    }
}
