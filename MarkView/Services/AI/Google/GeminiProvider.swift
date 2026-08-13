import Foundation

final class GeminiProvider: AIProvider {
    let providerType: AIProviderType = .gemini

    /// A document rewrite has to fit the *whole* document into one JSON string.
    /// The API default cuts long rewrites off mid-string, which then fails to
    /// parse, so ask for the largest budget these models accept.
    private let maxOutputTokens = 32_768

    func fetchModels(apiKey: String) async throws -> [AIModel] {
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models?key=\(apiKey)") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

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

        struct ModelsResponse: Decodable {
            struct Item: Decodable {
                let name: String
                let displayName: String?
                let supportedGenerationMethods: [String]?
            }
            let models: [Item]?
        }

        let decoded = try JSONDecoder().decode(ModelsResponse.self, from: data)
        return (decoded.models ?? [])
            .filter { $0.supportedGenerationMethods?.contains("generateContent") == true }
            .map { item in
                let id = item.name.replacingOccurrences(of: "models/", with: "")
                return AIModel(id: id, displayName: item.displayName ?? id, provider: .gemini)
            }
            .filter { AIModelCatalog.isUsableTextModel($0.id) }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
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
                    let endpoint = "https://generativelanguage.googleapis.com/v1beta/models/\(model.id):streamGenerateContent?alt=sse&key=\(apiKey)"
                    guard let url = URL(string: endpoint) else {
                        continuation.finish(throwing: URLError(.badURL))
                        return
                    }

                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

                    let systemInstruction = AIPromptBuilder.systemInstruction(
                        documentText: documentText,
                        selectedText: selectedText,
                        documentType: documentType,
                        blockListing: blockListing
                    )

                    var contents: [[String: Any]] = []

                    for message in history.suffix(6) {
                        contents.append([
                            "role": message.sender == .user ? "user" : "model",
                            "parts": Self.parts(text: message.content, images: message.attachments)
                        ])
                    }

                    contents.append([
                        "role": "user",
                        "parts": Self.parts(text: prompt, images: images)
                    ])

                    let payload: [String: Any] = [
                        // The document belongs in `system_instruction`, not in a
                        // user turn: it stays pinned as the history grows and
                        // isn't re-read as something the user just asked.
                        "system_instruction": [
                            "parts": [["text": systemInstruction]]
                        ],
                        "contents": contents,
                        "generationConfig": [
                            "responseMimeType": "application/json",
                            "maxOutputTokens": min(maxOutputTokens ?? self.maxOutputTokens, self.maxOutputTokens)
                        ]
                    ]

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
                        guard let data = jsonString.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

                        if let usage = Self.usage(from: json) {
                            continuation.yield(.usage(usage))
                        }

                        guard let candidates = json["candidates"] as? [[String: Any]],
                              let first = candidates.first,
                              let contentDict = first["content"] as? [String: Any],
                              let parts = contentDict["parts"] as? [[String: Any]] else {
                            continue
                        }

                        // A candidate can carry several parts, and thinking
                        // models put a reasoning part ahead of the answer.
                        // Taking `parts.first` dropped real output on the floor.
                        let text = parts
                            .filter { ($0["thought"] as? Bool) != true }
                            .compactMap { $0["text"] as? String }
                            .joined()

                        if !text.isEmpty {
                            didYield = true
                            continuation.yield(.text(text))
                        }
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
        guard let metadata = json["usageMetadata"] as? [String: Any] else { return nil }
        let input = metadata["promptTokenCount"] as? Int ?? 0
        let output = metadata["candidatesTokenCount"] as? Int ?? 0
        guard input + output > 0 else { return nil }
        return AITokenUsage(inputTokens: input, outputTokens: output)
    }

    /// Gemini takes images as `inline_data` parts alongside the text, and wants
    /// them *before* the text they refer to.
    static func parts(text: String, images: [AIImageAttachment]) -> [[String: Any]] {
        var parts: [[String: Any]] = images.map { image in
            [
                "inline_data": [
                    "mime_type": image.mimeType,
                    "data": image.base64
                ]
            ]
        }
        if !text.isEmpty {
            parts.append(["text": text])
        }
        return parts.isEmpty ? [["text": ""]] : parts
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
