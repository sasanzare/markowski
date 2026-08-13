import Foundation

/// Shared adapter for providers that expose OpenAI-compatible model and chat
/// endpoints. Keeping transport here prevents seven almost-identical clients
/// from drifting while provider identity, errors, and Keychain accounts stay
/// distinct throughout the app.
final class OpenAICompatibleProvider: AIProvider {
    let providerType: AIProviderType
    private let baseURL: URL
    private let extraHeaders: [String: String]

    init(providerType: AIProviderType, baseURL: URL, extraHeaders: [String: String] = [:]) {
        self.providerType = providerType
        self.baseURL = baseURL
        self.extraHeaders = extraHeaders
    }

    func fetchModels(apiKey: String) async throws -> [AIModel] {
        var request = request(path: "models", apiKey: apiKey)
        request.httpMethod = "GET"
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response, data: data)

        struct ModelsResponse: Decodable {
            struct Item: Decodable { let id: String }
            let data: [Item]?
        }
        let models = try JSONDecoder().decode(ModelsResponse.self, from: data).data ?? []
        return models
            .map(\.id)
            .filter(AIModelCatalog.isUsableTextModel)
            .map { AIModel(id: $0, displayName: $0, provider: providerType) }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
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
                    var request = self.request(path: "chat/completions", apiKey: apiKey)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

                    var messages: [[String: Any]] = [[
                        "role": "system",
                        "content": AIPromptBuilder.systemInstruction(
                            documentText: documentText,
                            selectedText: selectedText,
                            documentType: documentType,
                            blockListing: blockListing
                        )
                    ]]
                    for message in history.suffix(6) {
                        messages.append([
                            "role": message.sender == .user ? "user" : "assistant",
                            "content": message.content
                        ])
                    }
                    messages.append(["role": "user", "content": prompt])

                    var payload: [String: Any] = [
                        "model": model.id,
                        "messages": messages,
                        "stream": true
                    ]
                    if let maxOutputTokens { payload["max_tokens"] = min(maxOutputTokens, 16_384) }
                    if let reasoningEffort { payload["reasoning_effort"] = reasoningEffort.apiValue }
                    request.httpBody = try JSONSerialization.data(withJSONObject: payload)

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
                        if payload == "[DONE]" { break }
                        guard let data = payload.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                        if let usage = json["usage"] as? [String: Any] {
                            let input = usage["prompt_tokens"] as? Int ?? 0
                            let output = usage["completion_tokens"] as? Int ?? 0
                            if input + output > 0 {
                                continuation.yield(.usage(AITokenUsage(inputTokens: input, outputTokens: output)))
                            }
                        }
                        guard let choice = (json["choices"] as? [[String: Any]])?.first,
                              let delta = choice["delta"] as? [String: Any],
                              let text = delta["content"] as? String,
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

    private func request(path: String, apiKey: String) -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        for (name, value) in extraHeaders { request.setValue(value, forHTTPHeaderField: name) }
        return request
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
