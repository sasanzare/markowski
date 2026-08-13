import SwiftUI

struct InspectorView: View {
    let metadata: DocumentMetadata

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: metadata.fileExtension == "mmd" ? "diagram.png" : "doc.text.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(metadata.fileExtension == "mmd" ? Color.orange : Color.blue)
                    .font(.system(size: 28))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(metadata.fileName)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    
                    Text(metadata.fileExtension.uppercased() + " Document")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                InspectorRow(label: "Size", value: metadata.fileSizeFormatted)
                InspectorRow(label: "Modified", value: metadata.modificationDateFormatted)
                InspectorRow(label: "Lines", value: "\(metadata.lineCount)")
                InspectorRow(label: "Words", value: "\(metadata.wordCount)")
                InspectorRow(label: "Characters", value: "\(metadata.characterCount)")
            }

            if !metadata.path.isEmpty {
                Divider()

                VStack(alignment: .leading, spacing: 4) {
                    Text("Location")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(metadata.path)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(3)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(16)
        .frame(width: 260)
    }
}

struct InspectorRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .fontDesign(.monospaced)
                .foregroundStyle(.primary)
        }
    }
}
