import Foundation

final class AnthropicProvider: AIProvider {
    let providerType: AIProviderType = .anthropic
    private let apiVersion = "2023-06-01"

    func fetchModels(apiKey: String) async throws -> [AIModel] {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/models")!)
        configure(&request, apiKey: apiKey)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response, data: data)

        struct ModelsResponse: Decodable {
            struct Item: Decodable { let id: String; let display_name: String? }
            let data: [Item]
        }
        return try JSONDecoder().decode(ModelsResponse.self, from: data).data
            .map { AIModel(id: $0.id, displayName: $0.display_name ?? $0.id, provider: .anthropic) }
            .filter { AIModelCatalog.isUsableTextModel($0.id) }
    }

    func testConnection(apiKey: String) async throws -> Bool {
        try await !fetchModels(apiKey: apiKey).isEmpty
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
                    var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
                    request.httpMethod = "POST"
                    configure(&request, apiKey: apiKey)

                    var messages = history.suffix(6).map { message in
                        ["role": message.sender == .user ? "user" : "assistant", "content": message.content]
                    }
                    messages.append(["role": "user", "content": prompt])
                    request.httpBody = try JSONSerialization.data(withJSONObject: [
                        "model": model.id,
                        "system": AIPromptBuilder.systemInstruction(
                            documentText: documentText,
                            selectedText: selectedText,
                            documentType: documentType,
                            blockListing: blockListing
                        ),
                        "messages": messages,
                        "max_tokens": min(maxOutputTokens ?? 16_384, 16_384),
                        "stream": true
                    ])

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
                    guard http.statusCode == 200 else {
                        var body = ""
                        for try await line in bytes.lines where body.count < 4_000 { body += line }
                        throw AIProviderError.httpStatus(
                            provider: providerType,
                            code: http.statusCode,
                            detail: AIProviderResponse.errorDetail(from: body)
                        )
                    }

                    var yielded = false
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        guard let data = payload.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                        if let usage = json["usage"] as? [String: Any] {
                            let input = usage["input_tokens"] as? Int ?? 0
                            let output = usage["output_tokens"] as? Int ?? 0
                            if input + output > 0 {
                                continuation.yield(.usage(AITokenUsage(inputTokens: input, outputTokens: output)))
                            }
                        }
                        guard json["type"] as? String == "content_block_delta",
                              let delta = json["delta"] as? [String: Any],
                              let text = delta["text"] as? String,
                              !text.isEmpty else { continue }
                        yielded = true
                        continuation.yield(.text(text))
                    }
                    guard yielded else { throw AIProviderError.emptyResponse(provider: providerType) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func configure(_ request: inout URLRequest, apiKey: String) {
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }

    private func validate(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard http.statusCode == 200 else {
            throw AIProviderError.httpStatus(
                provider: providerType,
                code: http.statusCode,
                detail: AIProviderResponse.errorDetail(from: data)
            )
        }
    }
}
