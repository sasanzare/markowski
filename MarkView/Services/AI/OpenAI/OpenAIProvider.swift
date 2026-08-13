import Foundation

final class OpenAIProvider: AIProvider {
    let providerType: AIProviderType = .openAI

    func fetchModels(apiKey: String) async throws -> [AIModel] {
        guard let url = URL(string: "https://api.openai.com/v1/models") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard httpResponse.statusCode == 200 else {
            throw AIProviderError.httpStatus(
                provider: providerType,
                code: httpResponse.statusCode,
                detail: AIProviderResponse.errorDetail(from: data)
            )
        }

        struct OpenAIModelsResponse: Decodable {
            struct ModelItem: Decodable {
                let id: String
            }
            let data: [ModelItem]?
        }

        let decoded = try JSONDecoder().decode(OpenAIModelsResponse.self, from: data)
        guard let modelsList = decoded.data else { return [] }

        let validModels = modelsList.compactMap { item -> AIModel? in
            let id = item.id
            guard AIModelCatalog.isTextOnlyOpenAIModel(id) else { return nil }
            return AIModel(id: id, displayName: id, provider: .openAI)
        }

        return validModels.sorted { $0.displayName < $1.displayName }
    }

    func testConnection(apiKey: String) async throws -> Bool {
        let models = try await fetchModels(apiKey: apiKey)
        return !models.isEmpty
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
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
                        continuation.finish(throwing: URLError(.badURL))
                        return
                    }

                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

                    let systemInstruction = AIPromptBuilder.systemInstruction(
                        documentText: documentText,
                        selectedText: selectedText,
                        documentType: documentType,
                        blockListing: blockListing
                    )

                    var messages: [[String: Any]] = []
                    messages.append(["role": "system", "content": systemInstruction])

                    for message in history.suffix(6) {
                        messages.append([
                            "role": message.sender == .user ? "user" : "assistant",
                            "content": Self.content(text: message.content, images: message.attachments)
                        ])
                    }

                    messages.append([
                        "role": "user",
                        "content": Self.content(text: prompt, images: images)
                    ])

                    var payload: [String: Any] = [
                        "model": model.id,
                        "messages": messages,
                        "stream": true,
                        "stream_options": ["include_usage": true],
                        "response_format": ["type": "json_object"]
                    ]
                    if let maxOutputTokens { payload["max_completion_tokens"] = min(maxOutputTokens, 32_768) }
                    if let reasoningEffort { payload["reasoning_effort"] = reasoningEffort.apiValue }

                    request.httpBody = try JSONSerialization.data(withJSONObject: payload)

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let httpResponse = response as? HTTPURLResponse else {
                        continuation.finish(throwing: URLError(.badServerResponse))
                        return
                    }
                    guard httpResponse.statusCode == 200 else {
                        let body = try await Self.collectBody(from: bytes)
                        continuation.finish(throwing: AIProviderError.httpStatus(
                            provider: self.providerType,
                            code: httpResponse.statusCode,
                            detail: AIProviderResponse.errorDetail(from: body)
                        ))
                        return
                    }

                    var didYield = false
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let jsonString = String(line.dropFirst(6))
                        if jsonString == "[DONE]" { break }

                        guard let data = jsonString.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

                        if let usage = Self.usage(from: json) {
                            continuation.yield(.usage(usage))
                        }

                        guard let choices = json["choices"] as? [[String: Any]],
                              let first = choices.first,
                              let delta = first["delta"] as? [String: Any],
                              let text = delta["content"] as? String,
                              !text.isEmpty else {
                            continue
                        }

                        didYield = true
                        continuation.yield(.text(text))
                    }

                    if !didYield {
                        continuation.finish(throwing: AIProviderError.emptyResponse(provider: self.providerType))
                        return
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private static func usage(from json: [String: Any]) -> AITokenUsage? {
        guard let usage = json["usage"] as? [String: Any] else { return nil }
        let input = usage["prompt_tokens"] as? Int ?? usage["input_tokens"] as? Int ?? 0
        let output = usage["completion_tokens"] as? Int ?? usage["output_tokens"] as? Int ?? 0
        guard input + output > 0 else { return nil }
        return AITokenUsage(inputTokens: input, outputTokens: output)
    }

    /// A text-only turn stays a plain string — the multi-part form is only
    /// needed when images are present, and older models are happier without it.
    static func content(text: String, images: [AIImageAttachment]) -> Any {
        guard !images.isEmpty else { return text }

        var parts: [[String: Any]] = [["type": "text", "text": text]]
        parts.append(contentsOf: images.map { image in
            [
                "type": "image_url",
                "image_url": ["url": "data:\(image.mimeType);base64,\(image.base64)"]
            ]
        })
        return parts
    }

    /// An error response arrives on the same byte stream as a success, so the
    /// body has to be drained before it can be reported.
    private static func collectBody(from bytes: URLSession.AsyncBytes) async throws -> String {
        var body = ""
        for try await line in bytes.lines {
            body += line
            if body.count > 4_000 { break }
        }
        return body
    }
}
