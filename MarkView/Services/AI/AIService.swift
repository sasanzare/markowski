import Foundation
import SwiftUI

@MainActor
final class AIService: ObservableObject {
    @Published var activeProviderType: AIProviderType = .gemini {
        didSet {
            guard oldValue != activeProviderType else { return }
            UserDefaults.standard.set(activeProviderType.rawValue, forKey: "selectedAIProvider")
            Task { await refreshModels() }
        }
    }

    @Published var availableModels: [AIModel] = []
    @Published private(set) var modelsByProvider: [AIProviderType: [AIModel]] = [:]
    @Published var selectedModel: AIModel? {
        didSet {
            if let model = selectedModel {
                UserDefaults.standard.set(model.id, forKey: "selectedAIModel_\(model.provider.rawValue)")
            }
        }
    }

    @Published var conversation: [AIMessage] = [] {
        didSet { persistConversation() }
    }
    @Published var currentState: AIRequestState = .idle
    @Published var activeProposal: AIEditProposal?
    @Published private var modelPreferenceRevision = 0
    let tokenUsageStore = AITokenUsageStore.shared

    /// Where the conversations live between launches. Injectable so a test can
    /// point it at a scratch folder instead of the user's real history.
    let sessions: ChatSessionStore
    /// The chat currently on screen. A fresh one until something is said in it,
    /// at which point it earns a row in the history.
    @Published private(set) var currentSessionID = UUID()
    private var currentSessionCreatedAt = Date()
    private var currentSessionTitle = ChatSession.untitled

    // MARK: - Conversations

    /// Puts the current chat away and starts an empty one.
    func startNewChat() {
        activeTask?.cancel()
        persistConversation()

        currentSessionID = UUID()
        currentSessionCreatedAt = Date()
        currentSessionTitle = ChatSession.untitled
        activeProposal = nil
        currentState = .idle
        conversation = []
    }

    /// Reopens a chat from the history.
    func openChat(_ id: UUID) {
        guard id != currentSessionID else { return }
        activeTask?.cancel()
        persistConversation()

        guard let session = sessions.load(id) else { return }
        currentSessionID = session.id
        currentSessionCreatedAt = session.createdAt
        currentSessionTitle = session.title
        activeProposal = nil
        currentState = .idle

        // Reading a chat is not a change to it. Without this it would be
        // written straight back with a fresh timestamp and jump to the top of
        // the history just for having been opened.
        isRestoring = true
        conversation = session.messages
        isRestoring = false
    }

    /// Deletes a chat, and clears the screen if it was the one being shown.
    @discardableResult
    func deleteChat(_ id: UUID) -> Int {
        let freed = sessions.delete(id)
        if id == currentSessionID {
            currentSessionID = UUID()
            currentSessionCreatedAt = Date()
            currentSessionTitle = ChatSession.untitled
            conversation = []
        }
        return freed
    }

    @discardableResult
    func deleteAllChats() -> Int {
        let freed = sessions.deleteAll()
        currentSessionID = UUID()
        currentSessionCreatedAt = Date()
        currentSessionTitle = ChatSession.untitled
        conversation = []
        return freed
    }

    /// Writes the visible conversation to disk.
    ///
    /// Driven off `conversation`'s own `didSet` so every path that adds a
    /// message — a reply, a streamed chunk landing, an edit proposal — is
    /// covered without each having to remember to save.
    private func persistConversation() {
        // An empty conversation is a chat that has not happened yet; clearing
        // the screen is handled by whoever cleared it.
        guard !isRestoring, !conversation.isEmpty else { return }
        sessions.save(ChatSession(
            id: currentSessionID,
            title: currentSessionTitle,
            createdAt: currentSessionCreatedAt,
            updatedAt: Date(),
            messages: conversation
        ))
    }

    /// Set while a stored chat is being put back on screen, so restoring does
    /// not immediately write what it just read.
    private var isRestoring = false

    private var activeTask: Task<Void, Never>?
    /// A superseded request must not write state or transcript entries for the
    /// request that replaced it — cancellation only unblocks the old stream, it
    /// doesn't stop its continuation from running.
    private var requestGeneration = 0
    private var modelPreferenceObserver: NSObjectProtocol?

    private let geminiProvider = GeminiProvider()
    private let openAIProvider = OpenAIProvider()
    private let anthropicProvider = AnthropicProvider()
    private let mockProvider = MockAIProvider()

    private lazy var compatibleProviders: [AIProviderType: AIProvider] = [
        .openRouter: OpenAICompatibleProvider(
            providerType: .openRouter,
            baseURL: URL(string: "https://openrouter.ai/api/v1")!,
            extraHeaders: ["X-OpenRouter-Title": "Markowski"]
        ),
        .mistral: OpenAICompatibleProvider(
            providerType: .mistral,
            baseURL: URL(string: "https://api.mistral.ai/v1")!
        ),
        .groq: OpenAICompatibleProvider(
            providerType: .groq,
            baseURL: URL(string: "https://api.groq.com/openai/v1")!
        ),
        .xAI: OpenAICompatibleProvider(
            providerType: .xAI,
            baseURL: URL(string: "https://api.x.ai/v1")!
        ),
        .deepSeek: OpenAICompatibleProvider(
            providerType: .deepSeek,
            baseURL: URL(string: "https://api.deepseek.com/v1")!
        )
    ]

    /// `nil` rather than `.shared` as the default: a default argument is
    /// evaluated outside the initialiser's isolation, and reaching for a
    /// main-actor singleton from there is an error under Swift 6.
    init(sessions: ChatSessionStore? = nil) {
        self.sessions = sessions ?? .shared

        if let savedProvider = UserDefaults.standard.string(forKey: "selectedAIProvider"),
           let provider = AIProviderType(rawValue: savedProvider),
           provider != .mock {
            activeProviderType = provider
        }

        modelPreferenceObserver = NotificationCenter.default.addObserver(
            forName: AIModelPreferences.didChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.modelPreferenceRevision += 1
                self?.repairSelectedModelAfterPreferenceChange()
            }
        }

        Task { await refreshModels() }
    }

    var activeProvider: AIProvider {
        provider(for: activeProviderType)
    }

    var modelPickerModels: [AIModel] {
        _ = modelPreferenceRevision
        return configuredProviderTypes
            .filter { !apiKey(for: $0).isEmpty }
            .flatMap { modelsByProvider[$0] ?? [] }
            .filter(AIModelPreferences.isEnabled)
    }

    private func provider(for type: AIProviderType) -> AIProvider {
        switch type {
        case .gemini: return geminiProvider
        case .openAI: return openAIProvider
        case .anthropic: return anthropicProvider
        case .openRouter, .mistral, .groq, .xAI, .deepSeek:
            return compatibleProviders[type]!
        case .mock: return mockProvider
        }
    }

    private func apiKey(for type: AIProviderType) -> String {
        KeychainService.shared.getKey(forAccount: type.keychainAccount) ?? ""
    }

    var configuredProviderTypes: [AIProviderType] {
        AIProviderType.allCases.filter { provider in
            // MockAIProvider remains available to unit tests, but its
            // development-only models are never exposed in the user picker.
            guard provider != .mock else { return false }

            if provider == activeProviderType {
                return true
            }

            return !apiKey(for: provider).isEmpty
        }
    }

    /// The provider a request would actually use. The picker lists every
    /// configured provider in one flat list, so the selected model — not the
    /// last provider toggled — decides where the request goes.
    var requestProviderType: AIProviderType {
        selectedModel?.provider ?? activeProviderType
    }

    /// Non-nil when the provider a request would use has no key yet.
    var missingKeyProvider: AIProviderType? {
        let type = requestProviderType
        guard type != .mock, apiKey(for: type).isEmpty else { return nil }
        return type
    }

    func selectModel(_ model: AIModel) {
        if activeProviderType != model.provider {
            activeProviderType = model.provider
        }
        selectedModel = model
    }

    private func repairSelectedModelAfterPreferenceChange() {
        guard let selectedModel, !AIModelPreferences.isEnabled(selectedModel) else { return }
        self.selectedModel = modelPickerModels.first
        if let replacement = self.selectedModel {
            activeProviderType = replacement.provider
        }
    }

    var isRequestInFlight: Bool {
        switch currentState {
        case .preparing, .thinking, .streaming, .validating, .applying:
            return true
        case .idle, .proposedEdit, .failed, .cancelled:
            return false
        }
    }

    var streamingPreview: String {
        guard case .streaming(let rawText) = currentState else { return "" }
        return Self.extractPartialContent(from: rawText)
    }

    /// A `document_edit` streams a huge `updated_document` string that must not
    /// be shown raw, which used to leave the sidebar on a bare "Thinking…" for
    /// the whole rewrite. Say what is happening instead.
    var streamingProgressNote: String? {
        guard case .streaming(let rawText) = currentState else { return nil }
        guard rawText.contains("\"updated_document\"") else { return nil }
        return "Writing the updated document…"
    }

    func refreshModels() async {
        var refreshedModels: [AIProviderType: [AIModel]] = [:]

        for providerType in configuredProviderTypes {
            let key = apiKey(for: providerType)
            guard providerType == .mock || !key.isEmpty else { continue }

            do {
                let models = try await provider(for: providerType).fetchModels(apiKey: key)
                AIModelPreferences.installDefaultsIfNeeded(for: providerType, models: models)
                refreshedModels[providerType] = models
            } catch {
                refreshedModels[providerType] = []
            }
        }

        modelsByProvider = refreshedModels
        availableModels = refreshedModels[activeProviderType] ?? []

        // A refresh must not silently move the user off the model they picked.
        let allModels = refreshedModels.values.flatMap { $0 }
        if let current = selectedModel, allModels.contains(where: { $0.id == current.id && $0.provider == current.provider }) {
            return
        }

        let savedId = UserDefaults.standard.string(forKey: "selectedAIModel_\(activeProviderType.rawValue)")
        selectedModel = availableModels.first(where: { $0.id == savedId })
            ?? availableModels.first
            ?? allModels.first
    }

    func sendMessage(
        prompt: String,
        documentText: String,
        selectedText: String?,
        documentType: String,
        fileURL: URL?,
        images: [AIImageAttachment] = []
    ) {
        activeTask?.cancel()

        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        // An image on its own is a complete request — "what is this?" is
        // implied — so only reject a prompt that is empty in every way.
        guard !trimmedPrompt.isEmpty || !images.isEmpty else { return }

        conversation.append(AIMessage(sender: .user, content: trimmedPrompt, attachments: images))

        // Literal location questions are deterministic local work. Resolve
        // them from the in-memory document index before sending a whole file
        // to a provider. An attached image always needs the model.
        if images.isEmpty, let reference = localReference(for: trimmedPrompt, in: documentText) {
            let answer = "It appears under **\(reference.title)**."
            conversation.append(AIMessage(
                sender: .assistant,
                content: answer,
                documentLocation: reference.location,
                blocks: [
                    .markdown(answer),
                    .documentReference(reference)
                ]
            ))
            currentState = .idle
            return
        }

        guard let model = selectedModel else {
            currentState = .failed("No AI model is connected yet. Open AI Settings to continue.")
            return
        }

        // Route by the selected model's own provider. Using the last-toggled
        // provider instead sent Gemini requests with an OpenAI key whenever the
        // combined picker crossed providers.
        let providerType = model.provider
        let key = apiKey(for: providerType)
        if providerType != .mock && key.isEmpty {
            currentState = .failed("\(providerType.shortDisplayName) needs an API key before it can answer. Add one in AI Settings.")
            return
        }
        if activeProviderType != providerType {
            activeProviderType = providerType
        }
        let requestProvider = provider(for: providerType)

        let history = Array(conversation.dropLast())
        let estimatedInput = AITokenEstimator.inputTokens(
            prompt: trimmedPrompt,
            documentText: documentText,
            selectedText: selectedText,
            history: history,
            images: images
        )
        let remainingTokens = tokenUsageStore.remainingTokens(for: model)
        if let remainingTokens, remainingTokens <= estimatedInput {
            currentState = .failed(AITokenLimitError.exhausted(
                modelName: model.displayName,
                limit: tokenUsageStore.policy(for: model).tokenLimit ?? remainingTokens
            ).localizedDescription)
            return
        }
        let maxOutputTokens = remainingTokens.map { max(1, $0 - estimatedInput) }
        let originalHash = DocumentSafetyService.computeHash(text: documentText)

        // The assistant addresses blocks by handle, so it needs to see them.
        let baseDocument = MarkdownDocumentParser.parse(documentText)
        let handles = AIBlockHandles(document: baseDocument)
        let blockListing = AIDocumentOperations.promptListing(for: baseDocument, handles: handles)
        // Images with no question still need *a* question: an empty text part
        // is rejected by OpenAI, and asking nothing gets an unhelpful answer.
        let outgoingPrompt = trimmedPrompt.isEmpty
            ? "Describe what you see in the attached image, and relate it to this document where relevant."
            : trimmedPrompt
        currentState = .preparing

        requestGeneration += 1
        let generation = requestGeneration

        activeTask = Task { [weak self] in
            guard let self else { return }

            var accumulatedResponse = ""
            var reportedUsage: AITokenUsage?

            do {
                guard self.requestGeneration == generation else { return }
                self.currentState = .thinking
                let stream = requestProvider.streamResponse(
                    prompt: outgoingPrompt,
                    documentText: documentText,
                    selectedText: selectedText,
                    documentType: documentType,
                    history: history,
                    images: images,
                    blockListing: blockListing,
                    model: model,
                    apiKey: key,
                    maxOutputTokens: maxOutputTokens,
                    reasoningEffort: self.tokenUsageStore.policy(for: model).reasoningEffort
                )

                var lastPublishedAt = Date.distantPast

                for try await event in stream {
                    guard self.requestGeneration == generation else { return }
                    if Task.isCancelled {
                        self.commitPartialResponse(accumulatedResponse, state: .cancelled)
                        return
                    }

                    switch event {
                    case .text(let chunk):
                        accumulatedResponse += chunk
                    case .usage(let usage):
                        reportedUsage = usage
                        continue
                    }
                    let shouldPublish = Date().timeIntervalSince(lastPublishedAt) > 0.045
                        || accumulatedResponse.count < 80
                    if shouldPublish {
                        self.currentState = .streaming(text: accumulatedResponse)
                        lastPublishedAt = Date()
                    }
                }

                guard self.requestGeneration == generation else { return }
                guard !Task.isCancelled else {
                    self.commitPartialResponse(accumulatedResponse, state: .cancelled)
                    return
                }

                let finalUsage = reportedUsage ?? AITokenUsage(
                    inputTokens: estimatedInput,
                    outputTokens: max(1, accumulatedResponse.count / 4),
                    isEstimated: true
                )
                self.tokenUsageStore.record(finalUsage, for: model)

                self.currentState = .validating
                self.parseAndCommitResponse(
                    rawResponse: accumulatedResponse,
                    originalDocument: documentText,
                    originalHash: originalHash,
                    baseDocument: baseDocument,
                    handles: handles
                )
            } catch is CancellationError {
                guard self.requestGeneration == generation else { return }
                self.commitPartialResponse(accumulatedResponse, state: .cancelled)
            } catch {
                guard self.requestGeneration == generation else { return }
                self.commitPartialResponse(accumulatedResponse, state: .failed(self.userFacingError(for: error)))
            }
        }
    }

    func cancelRequest() {
        activeTask?.cancel()
        activeTask = nil
        // The generation is left alone so the stopped request still commits the
        // prose the user was already reading.
        currentState = .cancelled
    }

    func discardProposal() {
        guard let proposal = activeProposal else {
            currentState = .idle
            return
        }

        updateProposalStatus(proposal, to: .discarded)
        activeProposal = nil
        currentState = .idle
    }

    func markProposalApplied(_ proposal: AIEditProposal) {
        updateProposalStatus(proposal, to: .applied)
        activeProposal = nil
        currentState = .idle
    }

    func markProposalReverted(_ proposal: AIEditProposal) {
        updateProposalStatus(proposal, to: .reverted)
        currentState = .idle
    }

    private func updateProposalStatus(_ proposal: AIEditProposal, to status: AIEditProposal.EditStatus) {
        conversation = conversation.map { message in
            var updated = message
            if updated.editProposal?.id == proposal.id {
                updated.editProposal?.status = status
            }
            updated.blocks = updated.blocks.map { block in
                guard case .editProposal(var blockProposal) = block,
                      blockProposal.id == proposal.id else { return block }
                blockProposal.status = status
                return .editProposal(blockProposal)
            }
            return updated
        }
    }

    /// Text the user already watched arrive should survive a stop or a mid-stream
    /// failure rather than vanishing from the transcript.
    private func commitPartialResponse(_ rawResponse: String, state: AIRequestState) {
        let partial = Self.decodeUnicodeEscapes(in: Self.extractPartialContent(from: rawResponse))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if !partial.isEmpty {
            conversation.append(AIMessage(sender: .assistant, content: partial))
        }
        currentState = state
    }

    private func parseAndCommitResponse(
        rawResponse: String,
        originalDocument: String,
        originalHash: String,
        baseDocument: RichDocument = RichDocument(),
        handles: AIBlockHandles? = nil
    ) {
        let cleanResponse = Self.stripCodeFence(from: rawResponse)

        guard let data = cleanResponse.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            if cleanResponse.hasPrefix("{") || cleanResponse.hasPrefix("[") {
                // The envelope is malformed — usually cut off at the output
                // limit. Keep whatever prose already arrived instead of
                // discarding the whole response.
                commitPartialResponse(
                    cleanResponse,
                    state: .failed("The model’s response was cut off before it finished. Try again, ask for a smaller change, or choose another model.")
                )
                return
            }
            conversation.append(AIMessage(
                sender: .assistant,
                content: Self.decodeUnicodeEscapes(in: rawResponse.trimmingCharacters(in: .whitespacesAndNewlines))
            ))
            currentState = .idle
            return
        }

        switch type {
        case "document_operations":
            guard let handles else {
                currentState = .failed("The assistant proposed changes for a document that is no longer open.")
                return
            }
            let summary = (json["summary"] as? String) ?? "Proposed changes"
            let raw = (json["operations"] as? [[String: Any]]) ?? []

            do {
                let operations = try AIDocumentOperations.decode(raw, handles: handles)
                let updated = try baseDocument.applying(operations)
                let updatedMarkdown = MarkdownDocumentSerializer.serialize(updated)

                let changes = operations.map {
                    AIDocumentOperations.describe($0, in: baseDocument, handles: handles)
                }

                let proposal = AIEditProposal(
                    summary: summary,
                    updatedDocument: updatedMarkdown,
                    originalDocument: originalDocument,
                    originalHash: originalHash,
                    changes: changes
                )
                activeProposal = proposal
                conversation.append(AIMessage(
                    sender: .assistant,
                    content: summary,
                    editProposal: proposal,
                    blocks: [.markdown(summary), .editProposal(proposal)]
                ))
                currentState = .proposedEdit(proposal)
            } catch {
                // A malformed or unlandable operation is reported rather than
                // half-applied — the document is never left partly edited.
                let detail = (error as? LocalizedError)?.errorDescription
                    ?? "The assistant's proposed change couldn't be applied."
                conversation.append(AIMessage(sender: .assistant, content: summary))
                currentState = .failed(detail)
            }

        case "document_edit":
            guard let rawSummary = json["summary"] as? String,
                  let updatedDocument = json["updated_document"] as? String,
                  !updatedDocument.isEmpty else {
                conversation.append(AIMessage(sender: .assistant, content: "I couldn’t validate the proposed document change."))
                currentState = .failed("The edit returned by the model was incomplete.")
                return
            }
            let summary = Self.decodeUnicodeEscapes(in: rawSummary)

            let proposal = AIEditProposal(
                summary: summary,
                updatedDocument: updatedDocument,
                originalDocument: originalDocument,
                originalHash: originalHash
            )
            activeProposal = proposal
            conversation.append(AIMessage(
                sender: .assistant,
                content: summary,
                editProposal: proposal,
                blocks: [.markdown(summary), .editProposal(proposal)]
            ))
            currentState = .proposedEdit(proposal)

        case "document_reference", "search_result":
            let content = Self.decodeUnicodeEscapes(
                in: (json["content"] as? String) ?? "Here’s the relevant place in the document."
            )
            if let reference = makeReference(from: json) {
                conversation.append(AIMessage(
                    sender: .assistant,
                    content: content,
                    documentLocation: reference.location,
                    blocks: [.markdown(content), .documentReference(reference)]
                ))
            } else {
                conversation.append(AIMessage(sender: .assistant, content: content))
            }
            currentState = .idle

        case "chat_response", "answer":
            let content = Self.decodeUnicodeEscapes(in: (json["content"] as? String) ?? rawResponse)
            var blocks: [AIContentBlock] = [.markdown(content)]
            if let reference = makeReference(from: json) {
                blocks.append(.documentReference(reference))
            }
            conversation.append(AIMessage(sender: .assistant, content: content, blocks: blocks))
            currentState = .idle

        case "error":
            let message = (json["message"] as? String) ?? "The model couldn’t complete that request."
            currentState = .failed(message)

        default:
            let content = Self.decodeUnicodeEscapes(in: (json["content"] as? String) ?? rawResponse)
            conversation.append(AIMessage(sender: .assistant, content: content))
            currentState = .idle
        }
    }

    private func makeReference(from json: [String: Any]) -> DocumentReference? {
        let locationObject = (json["location"] as? [String: Any]) ?? (json["reference"] as? [String: Any])
        guard let locationObject else { return nil }

        let heading = (locationObject["heading"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let quote = (locationObject["quote"] as? String).flatMap { $0.isEmpty ? nil : $0 }

        let location = DocumentLocation(
            heading: heading,
            quote: quote,
            startLine: locationObject["startLine"] as? Int,
            endLine: locationObject["endLine"] as? Int,
            // A model has no way to know the renderer's block IDs, so anything
            // it puts here is invented — and an invented "block-1" resolved to
            // the top of the document every time. Locations are matched on the
            // quote and heading instead.
            blockId: nil
        )

        guard heading != nil || quote != nil || location.startLine != nil else { return nil }

        let title = (locationObject["title"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? heading
            ?? location.displayTitle
        let preview = (locationObject["preview"] as? String) ?? quote
        return DocumentReference(title: title, preview: preview, location: location)
    }

    private func localReference(for prompt: String, in text: String) -> DocumentReference? {
        guard let term = Self.localSearchTerm(from: prompt), !term.isEmpty else { return nil }

        let index = DocumentIndex()
        index.buildIndex(from: text)
        guard let block = index.blocks.first(where: { $0.contentText.localizedCaseInsensitiveContains(term) }) else {
            return nil
        }

        let quote = block.contentText
            .components(separatedBy: .newlines)
            .first(where: { $0.localizedCaseInsensitiveContains(term) })?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let location = DocumentLocation(
            heading: block.headingTitle,
            quote: quote,
            startLine: block.lineRange.lowerBound,
            endLine: block.lineRange.upperBound,
            blockId: block.id
        )
        return DocumentReference(title: block.headingTitle ?? "Document match", preview: quote, location: location)
    }

    /// Only a literal "where …" lookup is answered locally. The previous rule
    /// fired on any prompt containing "find", "mention", or "talk about", so
    /// requests like "find the typos and fix them" never reached the model at
    /// all and came back as an unrelated document reference.
    static func localSearchTerm(from prompt: String) -> String? {
        let normalized = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count <= 200 else { return nil }

        let lowercased = normalized.lowercased()
        guard lowercased.hasPrefix("where ") else { return nil }

        // "where should I add the install steps?" is a request for the model,
        // not a lookup.
        let actionVerbs = [
            "rewrite", "fix", "change", "replace", "update", "remove", "delete",
            "translate", "summarize", "summarise", "improve", "format", "convert",
            "insert", "should i", "should it", "would you", "can i put", "do i put"
        ]
        guard !actionVerbs.contains(where: lowercased.contains) else { return nil }

        var rest = String(normalized.dropFirst("where".count))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Longest first, so "do i mention" wins over "do".
        let leadIns = [
            "in the document do i mention", "in this document do i mention",
            "in the document is", "in this document is",
            "does the document mention", "does this document mention",
            "does it talk about", "do you talk about", "do i talk about",
            "does it mention", "do you mention", "did i mention", "do i mention",
            "does it discuss", "do i discuss", "does it say about", "does it say",
            "exactly is", "exactly are", "is", "are", "was", "were", "does", "do", "did"
        ]
        let lowerRest = rest.lowercased()
        for leadIn in leadIns where lowerRest.hasPrefix(leadIn) {
            // Only strip a whole word: "is" must not eat the "is" in "issue".
            guard lowerRest.count == leadIn.count || lowerRest.dropFirst(leadIn.count).hasPrefix(" ") else { continue }
            rest = String(rest.dropFirst(leadIn.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            break
        }

        var term = rest.trimmingCharacters(in: CharacterSet(charactersIn: " ?.:\"'“”"))

        for trailing in ["in the document", "in this document", "in the file", "mentioned", "discussed", "located"] {
            if term.lowercased().hasSuffix(trailing) {
                term = String(term.dropLast(trailing.count))
                    .trimmingCharacters(in: CharacterSet(charactersIn: " ?.,:\"'“”"))
            }
        }

        for article in ["the ", "a ", "an ", "my ", "our "] {
            if term.lowercased().hasPrefix(article) {
                term = String(term.dropFirst(article.count))
                break
            }
        }

        term = term.trimmingCharacters(in: CharacterSet(charactersIn: " ?.,:\"'“”"))
        // One- or two-character terms match almost every document.
        return term.count >= 3 ? term : nil
    }

    private func userFacingError(for error: Error) -> String {
        if let providerError = error as? AIProviderError, let description = providerError.errorDescription {
            return description
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost:
                return "Couldn’t reach the AI provider. Check your connection and try again."
            case .timedOut:
                return "The AI provider took too long to respond. Try again or choose a faster model."
            default:
                break
            }
        }
        return "The AI provider couldn’t complete that request. Try again or choose another model."
    }

    static func stripCodeFence(from rawResponse: String) -> String {
        var value = rawResponse.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("```json") { value = String(value.dropFirst(7)) }
        else if value.hasPrefix("```") { value = String(value.dropFirst(3)) }
        if value.hasSuffix("```") { value = String(value.dropLast(3)) }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Providers stream a JSON envelope. Reveal only the already-available
    /// prose while it is incomplete; the inspector never exposes the envelope
    /// itself as debug text.
    static func extractPartialContent(from rawResponse: String) -> String {
        // A `document_edit` has no "content" — its prose lives in "summary",
        // and without this the sidebar showed nothing at all for every rewrite.
        for key in ["\"content\"", "\"summary\""] {
            if let value = stringValue(forKey: key, in: rawResponse) {
                return value
            }
        }
        return ""
    }

    private static func stringValue(forKey key: String, in rawResponse: String) -> String? {
        guard let marker = rawResponse.range(of: key) else { return nil }
        let suffix = rawResponse[marker.upperBound...]
        guard let colon = suffix.firstIndex(of: ":") else { return nil }
        var cursor = suffix.index(after: colon)

        while cursor < suffix.endIndex, suffix[cursor].isWhitespace { cursor = suffix.index(after: cursor) }
        guard cursor < suffix.endIndex, suffix[cursor] == "\"" else { return nil }
        cursor = suffix.index(after: cursor)

        var result = ""
        var escaped = false
        while cursor < suffix.endIndex {
            let character = suffix[cursor]
            cursor = suffix.index(after: cursor)

            if escaped {
                switch character {
                case "n": result.append("\n")
                case "r": result.append("\r")
                case "t": result.append("\t")
                case "\\", "\"", "/": result.append(character)
                case "u":
                    var hex = ""
                    for _ in 0..<4 where cursor < suffix.endIndex {
                        hex.append(suffix[cursor])
                        cursor = suffix.index(after: cursor)
                    }
                    if let value = UInt32(hex, radix: 16), let scalar = UnicodeScalar(value) {
                        result.unicodeScalars.append(scalar)
                    } else {
                        result.append("u")
                        result.append(contentsOf: hex)
                    }
                default: result.append(character)
                }
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "\"" {
                break
            } else {
                result.append(character)
            }
        }
        return result
    }

    static func decodeUnicodeEscapes(in text: String) -> String {
        guard text.range(of: #"\\?u[0-9a-fA-F]{4}"#, options: .regularExpression) != nil else {
            return text
        }

        let pattern = #"\\?u([0-9a-fA-F]{4})"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let mutable = NSMutableString(string: text)
        let matches = regex.matches(
            in: text,
            range: NSRange(location: 0, length: (text as NSString).length)
        )
        for match in matches.reversed() {
            let hex = (text as NSString).substring(with: match.range(at: 1))
            guard let value = UInt32(hex, radix: 16), let scalar = UnicodeScalar(value) else { continue }
            mutable.replaceCharacters(in: match.range, with: String(Character(scalar)))
        }
        return mutable as String
    }
}
