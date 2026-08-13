import Foundation

enum AIProviderType: String, CaseIterable, Identifiable, Codable, Hashable {
    case gemini = "Google Gemini"
    case openAI = "OpenAI"
    case anthropic = "Anthropic"
    case openRouter = "OpenRouter"
    case mistral = "Mistral AI"
    case groq = "Groq"
    case xAI = "xAI"
    case deepSeek = "DeepSeek"
    case mock = "Mock Provider"

    var id: String { rawValue }

    var keychainAccount: String {
        switch self {
        case .gemini: return "gemini_api_key"
        case .openAI: return "openai_api_key"
        case .anthropic: return "anthropic_api_key"
        case .openRouter: return "openrouter_api_key"
        case .mistral: return "mistral_api_key"
        case .groq: return "groq_api_key"
        case .xAI: return "xai_api_key"
        case .deepSeek: return "deepseek_api_key"
        case .mock: return "mock_api_key"
        }
    }

    var shortDisplayName: String {
        switch self {
        case .gemini: return "Gemini"
        case .openAI: return "OpenAI"
        case .anthropic: return "Anthropic"
        case .openRouter: return "OpenRouter"
        case .mistral: return "Mistral"
        case .groq: return "Groq"
        case .xAI: return "xAI"
        case .deepSeek: return "DeepSeek"
        case .mock: return "Mock"
        }
    }

    var assetName: String {
        switch self {
        case .gemini: return "ProviderGemini"
        case .openAI: return "ProviderOpenAI"
        case .anthropic: return "ProviderAnthropic"
        case .openRouter: return "ProviderOpenRouter"
        case .mistral: return "ProviderMistral"
        case .groq: return "ProviderGroq"
        case .xAI: return "ProviderXAI"
        case .deepSeek: return "ProviderDeepSeek"
        case .mock: return "ProviderMock"
        }
    }

    var settingsSubtitle: String {
        switch self {
        case .gemini: return "Gemini Pro and Flash models from Google."
        case .openAI: return "GPT and reasoning models from OpenAI."
        case .anthropic: return "Claude models for writing and analysis."
        case .openRouter: return "One key for a broad catalog of text models."
        case .mistral: return "Mistral and Ministral text models."
        case .groq: return "Fast hosted open-weight language models."
        case .xAI: return "Grok text models from xAI."
        case .deepSeek: return "DeepSeek chat and reasoning models."
        case .mock: return "Development-only provider."
        }
    }
}

struct AIModel: Identifiable, Hashable, Codable {
    let id: String
    let displayName: String
    let provider: AIProviderType

    /// Provider names are often much longer than the compact model label an
    /// inspector can comfortably display. Keep the full value for menus and
    /// use this only for the header/composer chrome.
    var inspectorDisplayName: String {
        let normalized = displayName
            .replacingOccurrences(of: "Google ", with: "")
            .replacingOccurrences(of: "OpenAI ", with: "")

        if provider == .gemini {
            switch id {
            case "gemini-pro-latest": return "Gemini Pro"
            case "gemini-flash-latest": return "Gemini Flash"
            case "gemini-flash-lite-latest": return "Gemini Flash Lite"
            default: break
            }
        }

        if normalized.count <= 28 {
            return normalized
        }

        let lowercased = normalized.lowercased()
        if lowercased.contains("flash") {
            return "Gemini Flash Latest"
        }
        if lowercased.contains("pro") {
            return "Gemini Pro"
        }
        if lowercased.hasPrefix("gpt-") {
            return normalized
        }

        return String(normalized.prefix(25)) + "…"
    }
}

enum AIModelCatalog {
    static let geminiModels: [AIModel] = [
        AIModel(id: "gemini-pro-latest", displayName: "gemini-pro-latest", provider: .gemini),
        AIModel(id: "gemini-flash-latest", displayName: "gemini-flash-latest", provider: .gemini),
        AIModel(id: "gemini-flash-lite-latest", displayName: "gemini-flash-lite-latest", provider: .gemini)
    ]

    /// Whether a model accepts image input. Sending an image to a text-only
    /// model is a hard 400, so the composer hides the action instead.
    static func supportsImages(_ model: AIModel) -> Bool {
        switch model.provider {
        case .gemini, .mock:
            return true
        case .openAI:
            let id = model.id.lowercased()
            let visionFamilies = ["gpt-4o", "gpt-4.1", "gpt-4.5", "gpt-5", "o1", "o3", "o4"]
            return visionFamilies.contains { id.hasPrefix($0) }
        case .anthropic, .openRouter, .mistral, .groq, .xAI, .deepSeek:
            return false
        }
    }

    static func isTextOnlyOpenAIModel(_ id: String) -> Bool {
        let normalized = id.lowercased()
        let supportedFamily = normalized.hasPrefix("gpt-")
            || normalized.hasPrefix("o1")
            || normalized.hasPrefix("o3")
            || normalized.hasPrefix("o4")
        guard supportedFamily else { return false }

        let nonTextMarkers = [
            "audio", "realtime", "transcri", "tts", "image", "vision",
            "embedding", "moderation", "instruct", "whisper", "sora",
            "computer-use"
        ]
        return !nonTextMarkers.contains(where: normalized.contains)
    }

    static func isUsableTextModel(_ id: String) -> Bool {
        let normalized = id.lowercased()
        let nonTextMarkers = [
            "audio", "whisper", "tts", "speech", "transcri", "embedding",
            "moderation", "image", "dall-e", "sora", "realtime", "guard",
            "vision", "ocr", "rerank", "search", "tool-use", "computer-use",
            "banana", "lyria", "robotics", "antigravity", "imagen", "veo"
        ]
        return !nonTextMarkers.contains(where: normalized.contains)
    }

    static func supportsReasoningEffort(_ model: AIModel) -> Bool {
        let id = model.id.lowercased()
        switch model.provider {
        case .openAI:
            return id.hasPrefix("o1") || id.hasPrefix("o3") || id.hasPrefix("o4") || id.hasPrefix("gpt-5")
        case .openRouter:
            return id.contains("openai/") && (id.contains("/o") || id.contains("gpt-5"))
        default:
            return false
        }
    }
}

enum AIModelPreferences {
    static let didChange = Notification.Name("AIModelPreferencesDidChange")

    static func isEnabled(_ model: AIModel) -> Bool {
        enabledModelIDs(for: model.provider).contains(model.id)
    }

    static func setEnabled(_ enabled: Bool, for model: AIModel) {
        var selected = enabledModelIDs(for: model.provider)
        if enabled { selected.insert(model.id) } else { selected.remove(model.id) }
        UserDefaults.standard.set(Array(selected).sorted(), forKey: key(for: model.provider))
        UserDefaults.standard.set(true, forKey: configuredKey(for: model.provider))
        NotificationCenter.default.post(name: didChange, object: nil)
    }

    static func enabledIDs(for provider: AIProviderType) -> Set<String> {
        enabledModelIDs(for: provider)
    }

    static func installDefaultsIfNeeded(for provider: AIProviderType, models: [AIModel]) {
        guard !UserDefaults.standard.bool(forKey: configuredKey(for: provider)) else { return }
        let defaults = models
            .filter { model in
                let id = model.id.lowercased()
                return !id.contains("preview")
                    && !id.contains("computer-use")
                    && !id.contains("antigravity")
                    && !id.contains("legacy")
            }
            .sorted { $0.id.localizedStandardCompare($1.id) == .orderedDescending }
            .prefix(3)
            .map(\.id)
        UserDefaults.standard.set(Array(defaults), forKey: key(for: provider))
        UserDefaults.standard.set(true, forKey: configuredKey(for: provider))
    }


    private static func enabledModelIDs(for provider: AIProviderType) -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: key(for: provider)) ?? [])
    }

    private static func key(for provider: AIProviderType) -> String {
        "enabledAIModels_v2_\(provider.rawValue)"
    }

    private static func configuredKey(for provider: AIProviderType) -> String {
        "didConfigureAIModels_v2_\(provider.rawValue)"
    }
}

enum MessageSender: Codable {
    case user
    case assistant
}

struct AIEditProposal: Identifiable, Codable, Equatable {
    let id: UUID
    let summary: String
    let updatedDocument: String
    let originalDocument: String?
    let originalHash: String
    var status: EditStatus
    /// One sentence per change the assistant asked for, in its own terms —
    /// "Rewrite paragraph “…”", "Add a row to table". Present when the edit
    /// arrived as scoped operations rather than a whole rewritten document, so
    /// the review can say *what* is changing before showing any diff.
    var changes: [String]

    enum EditStatus: String, Codable {
        case pending
        case applied
        case discarded
        case reverted
    }

    init(
        id: UUID = UUID(),
        summary: String,
        updatedDocument: String,
        originalDocument: String? = nil,
        originalHash: String,
        status: EditStatus = .pending,
        changes: [String] = []
    ) {
        self.id = id
        self.summary = summary
        self.updatedDocument = updatedDocument
        self.originalDocument = originalDocument
        self.originalHash = originalHash
        self.status = status
        self.changes = changes
    }

    private enum CodingKeys: String, CodingKey {
        case id, summary, updatedDocument, originalDocument, originalHash, status, changes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        summary = try container.decode(String.self, forKey: .summary)
        updatedDocument = try container.decode(String.self, forKey: .updatedDocument)
        originalDocument = try container.decodeIfPresent(String.self, forKey: .originalDocument)
        originalHash = try container.decode(String.self, forKey: .originalHash)
        status = try container.decode(EditStatus.self, forKey: .status)
        changes = try container.decodeIfPresent([String].self, forKey: .changes) ?? []
    }
}

struct DocumentReference: Identifiable, Codable, Equatable {
    let id: UUID
    let title: String
    let preview: String?
    let location: DocumentLocation

    init(id: UUID = UUID(), title: String, preview: String? = nil, location: DocumentLocation) {
        self.id = id
        self.title = title
        self.preview = preview
        self.location = location
    }
}

/// A semantic block lets the inspector give structured AI results their own
/// visual treatment instead of flattening every result into a chat bubble.
enum AIContentBlock: Identifiable, Equatable, Codable {
    case markdown(String)
    case documentReference(DocumentReference)
    case editProposal(AIEditProposal)
    case status(String)
    case error(String)

    var id: String {
        switch self {
        case .markdown(let text): return "markdown-\(text.hashValue)"
        case .documentReference(let reference): return "reference-\(reference.id.uuidString)"
        case .editProposal(let proposal): return "proposal-\(proposal.id.uuidString)"
        case .status(let status): return "status-\(status.hashValue)"
        case .error(let error): return "error-\(error.hashValue)"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case value
    }

    private enum BlockType: String, Codable {
        case markdown
        case documentReference
        case editProposal
        case status
        case error
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(BlockType.self, forKey: .type)

        switch type {
        case .markdown: self = .markdown(try container.decode(String.self, forKey: .value))
        case .documentReference: self = .documentReference(try container.decode(DocumentReference.self, forKey: .value))
        case .editProposal: self = .editProposal(try container.decode(AIEditProposal.self, forKey: .value))
        case .status: self = .status(try container.decode(String.self, forKey: .value))
        case .error: self = .error(try container.decode(String.self, forKey: .value))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .markdown(let text):
            try container.encode(BlockType.markdown, forKey: .type)
            try container.encode(text, forKey: .value)
        case .documentReference(let reference):
            try container.encode(BlockType.documentReference, forKey: .type)
            try container.encode(reference, forKey: .value)
        case .editProposal(let proposal):
            try container.encode(BlockType.editProposal, forKey: .type)
            try container.encode(proposal, forKey: .value)
        case .status(let status):
            try container.encode(BlockType.status, forKey: .type)
            try container.encode(status, forKey: .value)
        case .error(let error):
            try container.encode(BlockType.error, forKey: .type)
            try container.encode(error, forKey: .value)
        }
    }
}

struct AIMessage: Identifiable, Codable {
    let id: UUID
    let sender: MessageSender
    var content: String
    let timestamp: Date
    var editProposal: AIEditProposal?
    var documentLocation: DocumentLocation?
    var blocks: [AIContentBlock]
    /// Images sent with this message. Kept on the message rather than in
    /// `blocks` so the bubble can lay them out as a grid above its text, and so
    /// they can be replayed into provider history.
    var attachments: [AIImageAttachment]

    init(
        id: UUID = UUID(),
        sender: MessageSender,
        content: String,
        timestamp: Date = Date(),
        editProposal: AIEditProposal? = nil,
        documentLocation: DocumentLocation? = nil,
        blocks: [AIContentBlock] = [],
        attachments: [AIImageAttachment] = []
    ) {
        self.id = id
        self.sender = sender
        self.content = content
        self.timestamp = timestamp
        self.editProposal = editProposal
        self.documentLocation = documentLocation
        self.blocks = blocks
        self.attachments = attachments
    }

    private enum CodingKeys: String, CodingKey {
        case id, sender, content, timestamp, editProposal, documentLocation, blocks, attachments
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        sender = try container.decode(MessageSender.self, forKey: .sender)
        content = try container.decode(String.self, forKey: .content)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        editProposal = try container.decodeIfPresent(AIEditProposal.self, forKey: .editProposal)
        documentLocation = try container.decodeIfPresent(DocumentLocation.self, forKey: .documentLocation)
        blocks = try container.decodeIfPresent([AIContentBlock].self, forKey: .blocks) ?? []
        attachments = try container.decodeIfPresent([AIImageAttachment].self, forKey: .attachments) ?? []
    }

    var contentBlocks: [AIContentBlock] {
        if !blocks.isEmpty {
            return blocks
        }

        var legacyBlocks: [AIContentBlock] = []
        if !content.isEmpty {
            legacyBlocks.append(.markdown(content))
        }
        if let documentLocation {
            legacyBlocks.append(.documentReference(DocumentReference(title: documentLocation.displayTitle, location: documentLocation)))
        }
        if let editProposal {
            legacyBlocks.append(.editProposal(editProposal))
        }
        return legacyBlocks
    }
}

enum AIRequestState: Equatable {
    case idle
    case preparing
    case thinking
    case streaming(text: String)
    case validating
    case proposedEdit(AIEditProposal)
    case applying
    case failed(String)
    case cancelled
}
