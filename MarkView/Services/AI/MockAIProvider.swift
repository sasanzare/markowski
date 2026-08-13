import Foundation

final class MockAIProvider: AIProvider {
    let providerType: AIProviderType = .mock

    func fetchModels(apiKey: String) async throws -> [AIModel] {
        [
            AIModel(id: "mock-model-fast", displayName: "Mock Fast AI", provider: .mock),
            AIModel(id: "mock-model-smart", displayName: "Mock Smart AI", provider: .mock)
        ]
    }

    func testConnection(apiKey: String) async throws -> Bool {
        true
    }

    func streamResponse(
        prompt: String,
        documentText: String,
        selectedText: String?,
        documentType: String,
        history: [AIMessage],
        images: [AIImageAttachment],
        blockListing: String?,
        model: AIModel,
        apiKey: String,
        maxOutputTokens: Int?,
        reasoningEffort: AIReasoningEffort?
    ) -> AsyncThrowingStream<AIStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let lowerPrompt = prompt.lowercased()
                    let isEdit = lowerPrompt.contains("make")
                        || lowerPrompt.contains("rewrite")
                        || lowerPrompt.contains("add")
                        || lowerPrompt.contains("fix")
                        || lowerPrompt.contains("convert")
                        || lowerPrompt.contains("improve")

                    let payload: [String: Any]
                    if isEdit {
                        let updatedDocument: String
                        if let selectedText,
                           let selectedRange = documentText.range(of: selectedText) {
                            let normalizedSelection = selectedText
                                .replacingOccurrences(of: "  ", with: " ")
                                .replacingOccurrences(of: " very ", with: " ")
                            let replacement = normalizedSelection == selectedText
                                ? "This document covers Markowski’s Markdown features."
                                : normalizedSelection
                            updatedDocument = documentText.replacingCharacters(in: selectedRange, with: replacement)
                        } else if documentText.isEmpty {
                            updatedDocument = "# Title\n\nGenerated content."
                        } else {
                            updatedDocument = documentText + "\n\n## Added Section\n\nThis section was added by AI."
                        }

                        payload = [
                            "type": "document_edit",
                            "summary": selectedText == nil ? "Added a new section based on your prompt." : "Tightened the selected passage while preserving the rest of the document.",
                            "updated_document": updatedDocument
                        ]
                    } else {
                        let wordCount = documentText.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
                        payload = [
                            "type": "chat_response",
                            "content": "## Document snapshot\n\nThis file contains **\(wordCount) words**. I can summarize its structure, explain a section, or propose a focused edit."
                        ]
                    }

                    let data = try JSONSerialization.data(withJSONObject: payload, options: [])
                    let response = String(data: data, encoding: .utf8) ?? "{}"
                    for character in response {
                        try await Task.sleep(nanoseconds: 5_000_000)
                        if Task.isCancelled { return }
                        continuation.yield(.text(String(character)))
                    }
                    continuation.yield(.usage(AITokenUsage(inputTokens: 120, outputTokens: response.count / 4)))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
