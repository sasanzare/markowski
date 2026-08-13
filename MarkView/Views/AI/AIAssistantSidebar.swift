import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

enum MarkViewDesign {
    private static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }

    private static func dark(_ value: CGFloat) -> NSColor {
        NSColor(srgbRed: value / 255, green: value / 255, blue: value / 255, alpha: 1)
    }

    // The reading canvas and inspector share one quiet, opaque dark surface.
    // Glass remains reserved for window chrome so text contrast stays stable.
    static let canvas = adaptive(light: .windowBackgroundColor, dark: dark(28))
    static let documentSurface = adaptive(light: .underPageBackgroundColor, dark: dark(28))
    static let sidebarSurface = adaptive(light: .windowBackgroundColor, dark: dark(28))
    static let sidebarHeaderSurface = adaptive(light: .controlBackgroundColor, dark: dark(28))
    static let composerSurface = adaptive(light: .textBackgroundColor, dark: dark(46))
    static let composerHoverSurface = adaptive(light: .controlBackgroundColor, dark: dark(57))
    static let controlSurface = adaptive(light: .controlBackgroundColor, dark: dark(42))
    static let controlHoverSurface = adaptive(light: .selectedControlColor.withAlphaComponent(0.12), dark: dark(55))
    static let controlPressedSurface = adaptive(light: .selectedControlColor.withAlphaComponent(0.20), dark: dark(66))
    static let panel = Color(nsColor: .controlBackgroundColor)
    static let glass = Color(nsColor: .controlBackgroundColor)
    static let glassStrong = adaptive(light: .white, dark: dark(68))
    static let textPrimary = Color.primary
    static let textSecondary = Color.secondary
    // A warm copper accent sampled from Markowski's quills and backpack. The
    // dark variant is brighter so it keeps sufficient contrast on #1C1C1C.
    static let accent = adaptive(
        light: NSColor(srgbRed: 0.69, green: 0.31, blue: 0.08, alpha: 1),
        dark: NSColor(srgbRed: 0.91, green: 0.52, blue: 0.20, alpha: 1)
    )
    static let accentSoft = adaptive(
        light: NSColor(srgbRed: 0.96, green: 0.72, blue: 0.45, alpha: 0.24),
        dark: NSColor(srgbRed: 0.91, green: 0.52, blue: 0.20, alpha: 0.20)
    )
    static let subtleBorder = Color(nsColor: .separatorColor)
    static let strongBorder = Color(nsColor: .gridColor)
    static let secondarySurface = controlSurface
    static let referenceSurface = adaptive(
        light: NSColor(srgbRed: 0.96, green: 0.72, blue: 0.45, alpha: 0.18),
        dark: NSColor(srgbRed: 0.91, green: 0.52, blue: 0.20, alpha: 0.14)
    )
    static let userSurface = adaptive(
        light: NSColor(srgbRed: 0.67, green: 0.28, blue: 0.055, alpha: 1),
        dark: NSColor(srgbRed: 0.72, green: 0.32, blue: 0.09, alpha: 1)
    )
    static let userText = Color.white
    static let addedSurface = Color.green.opacity(0.12)
    static let removedSurface = Color.red.opacity(0.10)
    static let shadow = Color.black.opacity(0.20)
}

private struct MarkViewHoverButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = 9
    var horizontalPadding: CGFloat = 11
    var height: CGFloat = 30
    var expands = false

    func makeBody(configuration: Configuration) -> some View {
        MarkViewHoverButtonBody(
            configuration: configuration,
            cornerRadius: cornerRadius,
            horizontalPadding: horizontalPadding,
            height: height,
            expands: expands
        )
    }
}

private struct MarkViewHoverButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let cornerRadius: CGFloat
    let horizontalPadding: CGFloat
    let height: CGFloat
    let expands: Bool
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .padding(.horizontal, horizontalPadding)
            .frame(maxWidth: expands ? .infinity : nil)
            .frame(height: height)
            .background(
                configuration.isPressed
                    ? MarkViewDesign.controlPressedSurface
                    : (isHovered ? MarkViewDesign.controlHoverSurface : MarkViewDesign.controlSurface)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        isHovered ? Color.white.opacity(0.22) : MarkViewDesign.strongBorder,
                        lineWidth: isHovered ? 1 : 0.8
                    )
                    .allowsHitTesting(false)
            }
            .shadow(color: isHovered ? MarkViewDesign.shadow.opacity(0.72) : .clear, radius: 5, y: 2)
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .animation(.easeOut(duration: 0.14), value: isHovered)
            .animation(.easeOut(duration: 0.10), value: configuration.isPressed)
            .onHover { isHovered = $0 }
    }
}

private struct PromptAttachment: Identifiable {
    let id = UUID()
    let name: String
    let contents: String
}

/// Text the next prompt is about, pinned until the user removes it.
///
/// It deliberately does *not* clear when the underlying selection collapses:
/// clicking into the composer drops the selection in both the web view and the
/// source editor, which used to throw the context away at the exact moment the
/// user went to type their question.
struct PromptContext: Equatable {
    enum Source: Equatable {
        case document
        case reply

        var label: String {
            switch self {
            case .document: return "Selected in document"
            case .reply: return "From Markowski’s reply"
            }
        }

        var symbol: String {
            switch self {
            case .document: return "text.quote"
            case .reply: return "sparkles"
            }
        }
    }

    let source: Source
    let text: String

    var characterCount: Int { text.count }
}

struct AIAssistantSidebar: View {
    @ObservedObject var aiService: AIService
    @ObservedObject private var tokenUsage = AITokenUsageStore.shared
    @Binding var documentText: String
    let fileURL: URL?
    let fileExtension: String

    var externalSelectedText: String?
    var selectionRequest: PreviewSelectionRequest?
    var onApplyEdit: ((String) -> Void)?
    var onUndoLastEdit: (() -> Void)?
    var onNavigateToLocation: ((DocumentLocation) -> Void)?
    var onReviewEdit: ((AIEditProposal) -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openSettings) private var openSettings
    @State private var inputPrompt = ""
    @State private var lastPrompt = ""
    @State private var pinnedContext: PromptContext?
    @State private var composerFocusToken: UUID?
    @State private var conflictError: String?
    @State private var isModelPickerPresented = false
    @State private var modelSearchQuery = ""
    @State private var attachments: [ComposerAttachment] = []
    @State private var pasteCounter = 0
    @State private var editingPastedItem: PastedTextItem?
    @State private var previewingImage: AIImageAttachment?
    /// The attached file whose extracted text the user is reading.
    @State private var previewingDocument: ExtractedDocument?
    @State private var showingHistory = false
    @State private var isDropTargeted = false
    @State private var hoveredMessageID: UUID?
    @State private var isComposerHovered = false
    @State private var isSendHovered = false
    @State private var hasAcceptedPrivacyNotice = UserDefaults.standard.bool(forKey: "acceptedAIPrivacyNotice")

    private let promptFieldBaseHeight: CGFloat = 38
    private let promptFieldMaxHeight: CGFloat = 164
    private let promptLineHeight: CGFloat = 18

    var body: some View {
        VStack(spacing: 0) {
            if hasStartedConversation {
                headerView
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .asymmetric(
                                insertion: .scale(scale: 0.84, anchor: .top)
                                    .combined(with: .opacity)
                                    .combined(with: .offset(y: -9)),
                                removal: .opacity
                            )
                    )
            }

            if !hasAcceptedPrivacyNotice {
                privacyNoticeView
            } else if let missingKeyProvider = aiService.missingKeyProvider {
                missingKeyView(for: missingKeyProvider)
            } else {
                conversationView

                if let proposal = aiService.activeProposal, proposal.status == .pending {
                    pendingActionView(proposal)
                }

                composerView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MarkViewDesign.sidebarSurface)
        .animation(
            reduceMotion ? .easeOut(duration: 0.14) : .spring(response: 0.46, dampingFraction: 0.58),
            value: hasStartedConversation
        )
        .alert("File changed", isPresented: Binding(
            get: { conflictError != nil },
            set: { if !$0 { conflictError = nil } }
        )) {
            Button("Apply Anyway") {
                if let proposal = aiService.activeProposal {
                    forceApplyProposal(proposal)
                }
            }
            Button("Cancel", role: .cancel) { conflictError = nil }
        } message: {
            Text(conflictError ?? "The file changed while this proposal was being prepared.")
        }
        .sheet(item: $editingPastedItem) { item in
            PastedTextEditorSheet(
                title: item.title,
                text: item.text,
                onSave: { updated in
                    updatePastedItem(item, to: updated)
                    editingPastedItem = nil
                },
                onRemove: {
                    removeAttachment(id: item.id)
                    editingPastedItem = nil
                },
                onCancel: { editingPastedItem = nil }
            )
        }
        .sheet(item: $previewingImage) { image in
            ImagePreviewSheet(
                attachment: image,
                onRemove: attachments.contains(where: { $0.id == image.id })
                    ? {
                        removeAttachment(id: image.id)
                        previewingImage = nil
                    }
                    : nil,
                onClose: { previewingImage = nil }
            )
        }
        .sheet(item: $previewingDocument) { document in
            ExtractedDocumentSheet(
                document: document,
                onRemove: attachments.contains(where: { $0.id == document.id })
                    ? {
                        removeAttachment(id: document.id)
                        previewingDocument = nil
                    }
                    : nil,
                onClose: { previewingDocument = nil }
            )
        }
        .onChange(of: externalSelectedText) { _, newValue in
            pinContext(from: newValue, source: .document)
        }
        .onChange(of: selectionRequest) { _, request in
            guard let request else { return }
            handle(request)
        }
        .onChange(of: aiService.activeProviderType) { _, _ in
            modelSearchQuery = ""
        }
    }

    // MARK: - Header

    private var hasStartedConversation: Bool {
        !aiService.conversation.isEmpty || aiService.isRequestInFlight
    }

    /// Title on the left, actions on the right, in one row.
    ///
    /// This used to centre the title in a `ZStack` with the actions floating
    /// over it — which works only while the actions stay narrow. Adding the
    /// chat buttons pushed them straight through the wordmark. A single `HStack`
    /// cannot overlap itself, whatever gets added later.
    private var headerView: some View {
        HStack(spacing: 8) {
            Image("MarkowskiToolbar")
                .resizable()
                .scaledToFit()
                .frame(width: 30, height: 30)
                .accessibilityHidden(true)

            Text("Markowski")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(MarkViewDesign.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
                // Above the spacer, below the controls. A `Spacer` is greedy
                // and sits at priority 0, so giving the title a *lower*
                // priority let the spacer claim the whole row and squeezed the
                // wordmark — and the icon beside it — down to nothing.
                .layoutPriority(1)

            Spacer(minLength: 6)

            headerActions
                .layoutPriority(2)
        }
        .frame(height: 56)
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .background(MarkViewDesign.sidebarHeaderSurface)
        .accessibilityElement(children: .contain)
    }

    /// Three bordered circles and a menu chevron is a lot of furniture for a
    /// 56pt bar, and it was what made the row too wide to fit. These carry
    /// their weight on hover instead, which is quieter and narrower.
    private var headerActions: some View {
        HStack(spacing: 2) {
            AssistantHeaderButton(
                symbol: "square.and.pencil",
                help: "New chat (⌘⌥N)",
                isEnabled: !aiService.conversation.isEmpty
            ) {
                aiService.startNewChat()
            }

            AssistantHeaderButton(
                symbol: "clock.arrow.circlepath",
                help: "Past chats and stored attachments"
            ) {
                showingHistory = true
            }
            .popover(isPresented: $showingHistory, arrowEdge: .bottom) {
                ChatHistoryView(
                    aiService: aiService,
                    onOpen: { aiService.openChat($0) },
                    onClose: { showingHistory = false }
                )
            }

            Menu {
                Button("AI Settings…") {
                    openSettings()
                }
                Button("Refresh Models") {
                    Task { await aiService.refreshModels() }
                }
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(MarkViewDesign.textSecondary)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            // Without this the menu reserves room for a disclosure chevron it
            // does not need, and the row grows by another 14pt.
            .menuIndicator(.hidden)
            .frame(width: 26)
            .accessibilityLabel("AI settings")
            .help("AI settings")
        }
    }

    private var filteredModels: [AIModel] {
        let query = modelSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return aiService.modelPickerModels }

        return aiService.modelPickerModels.filter { model in
            model.id.localizedCaseInsensitiveContains(query)
                || model.displayName.localizedCaseInsensitiveContains(query)
        }
    }

    private var modelPickerButton: some View {
        Button {
            isModelPickerPresented.toggle()
        } label: {
            HStack(spacing: 8) {
                if let model = aiService.selectedModel {
                    ModelProviderLogo(provider: model.provider, size: 19)
                }
                Text(aiService.selectedModel?.inspectorDisplayName ?? "Choose model")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let model = aiService.selectedModel {
                    Text(compactTokens(tokenUsage.usage(for: model).totalTokens))
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.05))
                        .clipShape(Capsule())
                }

                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(MarkViewHoverButtonStyle())
        .popover(isPresented: $isModelPickerPresented, arrowEdge: .bottom) {
            modelPickerPopover
        }
        .accessibilityLabel("Choose AI model")
        .help("Choose AI model")
    }

    private var modelPickerPopover: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("Search models", text: $modelSearchQuery)
                    .textFieldStyle(.plain)

                if !modelSearchQuery.isEmpty {
                    Button {
                        modelSearchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(MarkViewDesign.glassStrong)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(MarkViewDesign.subtleBorder, lineWidth: 0.7)
            )
            .padding(10)

            Rectangle()
                .fill(MarkViewDesign.subtleBorder)
                .frame(height: 0.7)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    if filteredModels.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(aiService.modelPickerModels.isEmpty ? "No models connected" : "No matching models")
                                .font(.system(size: 12, weight: .medium))
                            Text(aiService.modelPickerModels.isEmpty ? "Add an API key in AI Settings." : "Try a different search.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .padding(10)
                    } else {
                        ForEach(filteredModels) { model in
                            Button {
                                aiService.selectModel(model)
                                isModelPickerPresented = false
                            } label: {
                                HStack(spacing: 8) {
                                    ModelProviderLogo(provider: model.provider, size: 19)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(model.displayName)
                                            .font(.system(size: 12))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                        Text(modelUsageLabel(model))
                                            .font(.system(size: 9.5, weight: .medium))
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer(minLength: 8)

                                    if aiService.selectedModel?.id == model.id {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundStyle(MarkViewDesign.accent)
                                    }
                                }
                                .padding(.horizontal, 10)
                                .frame(minHeight: 38)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(8)
            }
            .frame(maxHeight: 220)

            Divider()

            HStack {
                Button("AI Settings…") {
                    isModelPickerPresented = false
                    openSettings()
                }
                .buttonStyle(.borderless)
                .font(.system(size: 11.5))

                Spacer()

                Button {
                    Task { await aiService.refreshModels() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh models")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .frame(width: 280)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(MarkViewDesign.strongBorder, lineWidth: 0.8)
        )
        .shadow(color: MarkViewDesign.shadow, radius: 18, y: 7)
    }

    private func modelUsageLabel(_ model: AIModel) -> String {
        let used = tokenUsage.usage(for: model).totalTokens
        let period = tokenUsage.policy(for: model).resetPeriod == .daily ? "today" : "used"
        if let remaining = tokenUsage.remainingTokens(for: model) {
            return "\(compactTokens(used)) \(period) • \(compactTokens(remaining)) left"
        }
        return "\(compactTokens(used)) tokens \(period)"
    }

    private func compactTokens(_ value: Int) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000).replacingOccurrences(of: ".0M", with: "M")
        }
        if value >= 1_000 {
            return String(format: "%.1fK", Double(value) / 1_000).replacingOccurrences(of: ".0K", with: "K")
        }
        return value.formatted()
    }

    // MARK: - Gated states

    private var privacyNoticeView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(MarkViewDesign.accent)

                VStack(alignment: .leading, spacing: 7) {
                    Text("AI is ready when you are")
                        .font(.system(size: 18, weight: .semibold))
                    Text("When you ask a question, the current document is sent to the model you choose. Nothing is sent until you submit a prompt.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button("Continue") {
                    UserDefaults.standard.set(true, forKey: "acceptedAIPrivacyNotice")
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                        hasAcceptedPrivacyNotice = true
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
    }

    private func missingKeyView(for provider: AIProviderType) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "key")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(.secondary)

            Text("Connect \(provider.rawValue)")
                .font(.system(size: 16, weight: .semibold))

            Text("Add an API key in AI Settings to ask questions about this document.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button("Open AI Settings") {
                openSettings()
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(24)
    }

    // MARK: - Conversation

    private var conversationView: some View {
        Group {
            if !hasStartedConversation {
                emptyStateView
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                        ForEach(aiService.conversation) { message in
                            messageRow(message)
                        }

                            if case .thinking = aiService.currentState {
                                thinkingView
                            }

                            if case .streaming = aiService.currentState {
                                streamingView
                            }

                            if case .failed(let message) = aiService.currentState {
                                errorView(message)
                            }

                            Color.clear
                                .frame(height: 1)
                                .id("conversation-bottom")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 18)
                        .animation(
                            reduceMotion
                                ? .easeOut(duration: 0.14)
                                : .spring(response: 0.34, dampingFraction: 0.9, blendDuration: 0.08),
                            value: aiService.conversation.count
                        )
                    }
                    .scrollIndicators(.automatic)
                    .onChange(of: aiService.conversation.count) { _, _ in
                        scrollToBottom(proxy, animated: true)
                    }
                    .onChange(of: aiService.currentState) { _, state in
                        if case .streaming = state {
                            scrollToBottom(proxy, animated: false)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MarkViewDesign.sidebarSurface)
    }

    private var emptyStateView: some View {
        VStack(spacing: 13) {
            Image("MarkowskiAssistant")
                .resizable()
                .scaledToFit()
                .frame(height: 138)
                .frame(maxWidth: .infinity, alignment: .center)
                .accessibilityHidden(true)

            Text("Ask Markowski")
                .font(.system(size: 15, weight: .semibold))

            Text("Understand, rewrite, find, compare,\nor update anything in this file.")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                suggestionButton("Summarize", systemImage: "doc.text", color: .blue)
                suggestionButton("Improve writing", systemImage: "wand.and.stars", color: .indigo)
                suggestionButton("Find section", systemImage: "magnifyingglass", color: .orange)
                suggestionButton("Create diagram", systemImage: "chart.xyaxis.line", color: .green)
            }
            .padding(.top, 5)
            .frame(maxWidth: 390)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.horizontal, 16)
        .overlay(alignment: .topTrailing) {
            headerActions
                .padding(.top, 14)
                .padding(.trailing, 16)
        }
    }

    private func suggestionButton(_ title: String, systemImage: String, color: Color) -> some View {
        Button {
            submitPrompt(title)
        } label: {
            HStack(spacing: 7) {
                Image(systemName: systemImage)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 15)
                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.primary)
            }
        }
        .buttonStyle(MarkViewHoverButtonStyle(height: 31, expands: true))
        .accessibilityLabel("Ask AI to \(title.lowercased())")
    }

    private func userBubble(_ message: AIMessage) -> some View {
        let isRTL = TextDirection.isRightToLeft(message.content)
        return Text(message.content)
            .font(isRTL ? .custom("IRANSansX-Regular", size: 13) : .system(size: 13))
            .foregroundStyle(MarkViewDesign.userText)
            .lineSpacing(2)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(MarkViewDesign.userSurface)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.24), lineWidth: 0.7)
            )
            .shadow(color: MarkViewDesign.shadow.opacity(0.42), radius: 6, y: 2)
            .textSelection(.enabled)
            .environment(\.layoutDirection, isRTL ? .rightToLeft : .leftToRight)
            .multilineTextAlignment(isRTL ? .trailing : .leading)
    }

    /// Images already sent stay visible in the transcript, and stay clickable —
    /// the conversation is the record of what the model was actually shown.
    private func sentImages(_ images: [AIImageAttachment]) -> some View {
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(images) { image in
                Button {
                    previewingImage = image
                } label: {
                    Group {
                        if let thumbnail = image.thumbnail {
                            Image(nsImage: thumbnail)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } else {
                            Image(systemName: "photo")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 108, height: 82)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.16), lineWidth: 0.7)
                    )
                    .shadow(color: MarkViewDesign.shadow.opacity(0.34), radius: 5, y: 2)
                }
                .buttonStyle(.plain)
                .help("\(image.fileName) · \(image.dimensionsDescription)")
                .accessibilityLabel("Sent image \(image.fileName)")
            }
        }
    }

    private func messageRow(_ message: AIMessage) -> some View {
        Group {
            if message.sender == .user {
                HStack(alignment: .bottom) {
                    Spacer(minLength: 22)
                    VStack(alignment: .trailing, spacing: 6) {
                        if !message.attachments.isEmpty {
                            sentImages(message.attachments)
                        }
                        if !message.content.isEmpty {
                            userBubble(message)
                        }
                    }
                    .contextMenu {
                        Button("Copy") { copyToPasteboard(message.content) }
                    }
                }
                .padding(.vertical, 7)
                .transition(.opacity.combined(with: .offset(y: reduceMotion ? 0 : 6)))
            } else {
                HStack(alignment: .top, spacing: 0) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(message.contentBlocks) { block in
                            contentBlockView(block)
                        }

                        replyActions(for: message)
                            .opacity(hoveredMessageID == message.id ? 1 : 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contextMenu {
                        Button("Ask About This Reply") {
                            pinContext(from: message.content, source: .reply)
                            composerFocusToken = UUID()
                        }
                        Button("Copy") { copyToPasteboard(message.content) }
                    }
                }
                .padding(.vertical, 9)
                .transition(.opacity.combined(with: .offset(y: reduceMotion ? 0 : 4)))
                .onHover { hovering in
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) {
                        hoveredMessageID = hovering ? message.id : (hoveredMessageID == message.id ? nil : hoveredMessageID)
                    }
                }
            }
        }
        .id(message.id)
    }

    /// Selecting inside a reply pins that passage the same way a document
    /// selection does, so a follow-up question can be about what Markowski
    /// just said rather than about the file.
    private func replyActions(for message: AIMessage) -> some View {
        HStack(spacing: 6) {
            Button {
                pinContext(from: message.content, source: .reply)
                composerFocusToken = UUID()
            } label: {
                Label("Ask about this", systemImage: "text.bubble")
                    .font(.system(size: 10.5, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Pin this reply as context for your next question")

            Button {
                copyToPasteboard(message.content)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
                    .font(.system(size: 10.5, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Copy this reply")

            Spacer(minLength: 0)
        }
        .padding(.top, 1)
    }

    @ViewBuilder
    private func contentBlockView(_ block: AIContentBlock) -> some View {
        switch block {
        case .markdown(let markdown):
            StreamingTextView(
                fullText: markdown,
                isGenerating: false,
                onSelectionChanged: { selection in
                    pinContext(from: selection, source: .reply)
                }
            )
        case .documentReference(let reference):
            referenceCard(reference)
        case .editProposal(let proposal):
            editProposalCard(proposal)
        case .status(let status):
            Label(status, systemImage: "checkmark.circle")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        case .error(let error):
            errorView(error)
        }
    }

    private func referenceCard(_ reference: DocumentReference) -> some View {
        ReferenceCard(reference: reference) {
            onNavigateToLocation?(reference.location)
        }
    }

    private var thinkingView: some View {
        ThinkingRow(reduceMotion: reduceMotion)
            .padding(.vertical, 10)
            .transition(.opacity)
    }

    private var streamingView: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 7) {
                if aiService.streamingPreview.isEmpty {
                    ThinkingRow(reduceMotion: reduceMotion)
                } else {
                    StreamingTextView(fullText: aiService.streamingPreview, isGenerating: true)
                }

                // A rewrite streams the whole document into the envelope, which
                // can't be shown raw. Report the work instead of stalling on a
                // motionless "Thinking…".
                if let note = aiService.streamingProgressNote {
                    Label(note, systemImage: "square.and.pencil")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 10)
        .transition(.opacity)
    }

    private func errorView(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Couldn’t complete that request", systemImage: "exclamationmark.triangle")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(.primary)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            if !lastPrompt.isEmpty {
                Button("Try Again") { submitPrompt(lastPrompt) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.red.opacity(0.24), lineWidth: 0.7)
        )
        .padding(.vertical, 8)
    }

    // MARK: - Pending action and composer

    private func pendingActionView(_ proposal: AIEditProposal) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.badge.gearshape")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(MarkViewDesign.accent)
            Text("Edit ready to review")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
            Button("Review") { onReviewEdit?(proposal) }
                .buttonStyle(.bordered)
                .controlSize(.small)
            Button("Apply") { applyProposal(proposal) }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.thinMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(MarkViewDesign.subtleBorder)
                .frame(height: 0.7)
        }
    }

    @discardableResult
    private func pinContext(from text: String?, source: PromptContext.Source) -> PromptContext? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        let context = PromptContext(source: source, text: trimmed)
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
            pinnedContext = context
        }
        return context
    }

    private func handle(_ request: PreviewSelectionRequest) {
        // Pass the context along explicitly rather than reading the `@State`
        // back in the same event.
        let context = pinContext(from: request.text, source: .document)

        switch request.action {
        case .ask:
            // Hand the user a pinned selection and a live caret; don't guess
            // the question for them.
            composerFocusToken = UUID()
        case .explain:
            submitPrompt("Explain this part of the document.", using: context)
        case .improve:
            submitPrompt("Improve the writing in this part of the document, keeping its meaning.", using: context)
        }
    }

    private var composerView: some View {
        VStack(spacing: 8) {
            if let context = pinnedContext {
                promptContextView(context)
                    .transition(.opacity.combined(with: .offset(y: reduceMotion ? 0 : 4)))
            }

            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    if !attachments.isEmpty {
                        attachmentStrip
                    }

                    PromptEditor(
                        text: $inputPrompt,
                        focusToken: composerFocusToken,
                        onSubmit: submitCurrentPrompt,
                        onPasteLongText: capturePastedText,
                        onPasteImage: { image in
                            loadImage(from: image, fileName: "Pasted image.png")
                        }
                    )
                    .frame(height: promptFieldHeight, alignment: .top)
                    .frame(height: promptFieldHeight, alignment: .topLeading)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)

                HStack(spacing: 9) {
                    modelPickerButton

                    Menu {
                        Button {
                            attachImage()
                        } label: {
                            Label("Image…", systemImage: "photo")
                        }
                        .disabled(!supportsImageInput)

                        Button {
                            attachTextFile()
                        } label: {
                            Label("Document…", systemImage: "doc.text")
                        }
                        .help("Attach a PDF, Word document, spreadsheet, or text file — its text is read out and sent with your prompt")

                        if !supportsImageInput {
                            Divider()
                            Text("\(aiService.selectedModel?.inspectorDisplayName ?? "This model") can’t read images")
                        }
                    } label: {
                        Label("Attach", systemImage: "paperclip")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .foregroundStyle(.primary)
                    .font(.system(size: 12.5, weight: .medium))
                    .help("Attach an image, or a document — PDF, Word, spreadsheet, or text")

                    Spacer(minLength: 0)

                    if aiService.isRequestInFlight {
                        Button {
                            aiService.cancelRequest()
                        } label: {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 10, weight: .bold))
                                .frame(width: 24, height: 24)
                                .background(MarkViewDesign.accent)
                                .foregroundStyle(.white)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Stop response")
                        .help("Stop response")
                    } else {
                        sendButton
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .background(isComposerHovered ? MarkViewDesign.composerHoverSurface : MarkViewDesign.composerSurface)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(MarkViewDesign.strongBorder, lineWidth: 0.8)
                    .allowsHitTesting(false)
            }
            .shadow(color: MarkViewDesign.shadow.opacity(0.55), radius: 12, y: 4)
            .animation(.easeOut(duration: 0.16), value: isComposerHovered)
            .onHover { isComposerHovered = $0 }
            .overlay {
                if isDropTargeted {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(MarkViewDesign.accent, style: StrokeStyle(lineWidth: 1.6, dash: [5, 4]))
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(MarkViewDesign.accent.opacity(0.09))
                        )
                        .overlay {
                            Label("Drop image to attach", systemImage: "photo.badge.plus")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(MarkViewDesign.accent)
                        }
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isDropTargeted)
            .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                loadDroppedImages(from: providers)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(MarkViewDesign.sidebarSurface)
        .animation(reduceMotion ? nil : .spring(response: 0.30, dampingFraction: 0.84), value: promptFieldHeight)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: pinnedContext)
    }

    /// Attachments sit above the text field as a horizontally scrolling strip,
    /// so any number of them can be pending without pushing the composer
    /// off-screen.
    private var attachmentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(attachments) { attachment in
                    attachmentChip(attachment)
                        .transition(
                            reduceMotion
                                ? .opacity
                                : .asymmetric(
                                    insertion: .scale(scale: 0.72, anchor: .bottomLeading)
                                        .combined(with: .opacity),
                                    removal: .scale(scale: 0.82).combined(with: .opacity)
                                )
                        )
                }
            }
            .padding(.vertical, 1)
        }
        .frame(height: 58)
    }

    @ViewBuilder
    private func attachmentChip(_ attachment: ComposerAttachment) -> some View {
        switch attachment {
        case .loadingImage(_, let fileName):
            ComposerImageLoadingChip(fileName: fileName)

        case .image(let image):
            ComposerImageChip(
                attachment: image,
                onRemove: { removeAttachment(id: image.id) },
                onOpen: { previewingImage = image }
            )

        case .failed(let id, let fileName, let message):
            ComposerFailedChip(fileName: fileName, message: message) {
                removeAttachment(id: id)
            }

        case .pastedText(let item):
            PastedTextChip(
                item: item,
                onOpen: { editingPastedItem = item },
                onRemove: { removeAttachment(id: item.id) }
            )

        case .textFile(let id, let name, let contents):
            ComposerDocumentChip(
                document: ExtractedDocument(
                    id: id,
                    fileName: name,
                    kind: .plainText,
                    text: contents,
                    byteCount: contents.utf8.count
                ),
                onOpen: { previewingDocument = attachment.extractedDocument ?? nil },
                onRemove: { removeAttachment(id: id) }
            )

        case .loadingDocument(_, let fileName):
            ComposerDocumentLoadingChip(fileName: fileName)

        case .document(let document):
            ComposerDocumentChip(
                document: document,
                onOpen: { previewingDocument = document },
                onRemove: { removeAttachment(id: document.id) }
            )
        }
    }

    private var promptFieldHeight: CGFloat {
        let lines = inputPrompt
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { max(1, Int(ceil(Double($0.count) / 42.0))) }
            .reduce(0, +)
        let growth = CGFloat(max(0, lines - 1)) * promptLineHeight
        return min(promptFieldMaxHeight, max(promptFieldBaseHeight, promptFieldBaseHeight + growth))
    }

    private var canSubmitPrompt: Bool {
        // A half-decoded image would be sent as nothing, so hold the send
        // button until every attachment has resolved.
        guard !isPreparingAttachment else { return false }
        let hasSendableAttachment = attachments.contains { attachment in
            switch attachment {
            case .image, .pastedText, .textFile, .document: return true
            case .loadingImage, .loadingDocument, .failed: return false
            }
        }
        return !inputPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || hasSendableAttachment
    }

    private var sendButton: some View {
        Button {
            submitCurrentPrompt()
        } label: {
            Image(systemName: "arrow.up")
                .font(.system(size: 12, weight: .bold))
                .frame(width: 28, height: 28)
                .background(
                    canSubmitPrompt
                        ? (isSendHovered ? MarkViewDesign.accent.opacity(0.82) : MarkViewDesign.accent)
                        : (isSendHovered ? MarkViewDesign.controlHoverSurface : MarkViewDesign.controlSurface)
                )
                .foregroundStyle(canSubmitPrompt ? Color.white : MarkViewDesign.textSecondary)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(MarkViewDesign.strongBorder.opacity(canSubmitPrompt ? 0.58 : 0.72), lineWidth: 0.7))
                .shadow(color: canSubmitPrompt ? MarkViewDesign.shadow : .clear, radius: 7, y: 2)
        }
        .buttonStyle(.plain)
        .disabled(!canSubmitPrompt)
        .animation(.easeOut(duration: 0.14), value: isSendHovered)
        .onHover { isSendHovered = $0 }
        .accessibilityLabel("Send prompt")
        .help("Send prompt")
    }

    // MARK: - Attachments

    private var attachedImages: [AIImageAttachment] {
        attachments.compactMap(\.imageAttachment)
    }

    private var isPreparingAttachment: Bool {
        attachments.contains(where: \.isLoading)
    }

    private var supportsImageInput: Bool {
        guard let model = aiService.selectedModel else { return false }
        return AIModelCatalog.supportsImages(model)
    }

    private func attachImage() {
        let panel = NSOpenPanel()
        panel.title = "Attach an image"
        panel.allowedContentTypes = ImageAttachmentLoader.supportedTypes
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            loadImage(from: url)
        }
    }

    /// Every image path — panel, drag, clipboard — goes through here so the
    /// loading chip, the failure chip, and ordering behave identically.
    private func loadImage(from url: URL) {
        let placeholderID = UUID()
        let name = url.lastPathComponent
        appendAttachment(.loadingImage(id: placeholderID, fileName: name))

        Task {
            do {
                let attachment = try await ImageAttachmentLoader.load(from: url)
                replaceAttachment(id: placeholderID, with: .image(attachment))
            } catch {
                replaceAttachment(
                    id: placeholderID,
                    with: .failed(
                        id: placeholderID,
                        fileName: name,
                        message: (error as? LocalizedError)?.errorDescription ?? "Couldn’t attach"
                    )
                )
            }
        }
    }

    private func loadImage(from image: NSImage, fileName: String) {
        let placeholderID = UUID()
        appendAttachment(.loadingImage(id: placeholderID, fileName: fileName))

        Task {
            do {
                let attachment = try await ImageAttachmentLoader.load(from: image, fileName: fileName)
                replaceAttachment(id: placeholderID, with: .image(attachment))
            } catch {
                replaceAttachment(
                    id: placeholderID,
                    with: .failed(
                        id: placeholderID,
                        fileName: fileName,
                        message: (error as? LocalizedError)?.errorDescription ?? "Couldn’t attach"
                    )
                )
            }
        }
    }

    private func appendAttachment(_ attachment: ComposerAttachment) {
        withAnimation(attachmentAnimation) {
            attachments.append(attachment)
        }
    }

    private func replaceAttachment(id: UUID, with attachment: ComposerAttachment) {
        guard let index = attachments.firstIndex(where: { $0.id == id }) else { return }
        withAnimation(attachmentAnimation) {
            attachments[index] = attachment
        }
    }

    private func removeAttachment(id: UUID) {
        withAnimation(attachmentAnimation) {
            attachments.removeAll { $0.id == id }
        }
    }

    private var attachmentAnimation: Animation? {
        reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.82)
    }

    private func attachTextFile() {
        let panel = NSOpenPanel()
        panel.title = "Attach a document"
        panel.message = "PDFs, Word documents, spreadsheets, and text files."
        panel.allowedContentTypes = DocumentTextExtractor.supportedTypes
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            loadDocument(from: url)
        }
    }

    /// Every document path — panel, drag — goes through here, so the loading
    /// chip, the failure chip, and ordering behave identically.
    private func loadDocument(from url: URL) {
        let placeholderID = UUID()
        let name = url.lastPathComponent
        appendAttachment(.loadingDocument(id: placeholderID, fileName: name))

        Task {
            do {
                let extracted = try await DocumentTextExtractor.extract(from: url)
                replaceAttachment(
                    id: placeholderID,
                    with: .document(ExtractedDocument(
                        id: placeholderID,
                        fileName: extracted.fileName,
                        kind: extracted.kind,
                        text: extracted.text,
                        byteCount: extracted.byteCount,
                        structureSummary: extracted.structureSummary,
                        isTruncated: extracted.isTruncated
                    ))
                )
            } catch {
                replaceAttachment(
                    id: placeholderID,
                    with: .failed(
                        id: placeholderID,
                        fileName: name,
                        message: (error as? LocalizedError)?.errorDescription ?? "Couldn’t read this file"
                    )
                )
            }
        }
    }

    /// A long paste becomes a numbered chip rather than burying the question
    /// under thousands of characters of prose.
    private func capturePastedText(_ text: String) {
        pasteCounter += 1
        appendAttachment(.pastedText(PastedTextItem(number: pasteCounter, text: text)))
    }

    private func updatePastedItem(_ item: PastedTextItem, to newText: String) {
        guard let index = attachments.firstIndex(where: { $0.id == item.id }) else { return }
        var updated = item
        updated.text = newText
        attachments[index] = .pastedText(updated)
    }

    /// Anything droppable onto the composer: an image goes down the image
    /// path, a document down the extraction path. A file that is neither is
    /// reported rather than ignored, so a drag never just does nothing.
    private func loadDroppedImages(from providers: [NSItemProvider]) -> Bool {
        var acceptedAny = false
        for provider in providers where provider.canLoadObject(ofClass: URL.self) {
            acceptedAny = true
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in
                    if ImageAttachmentLoader.isSupported(url: url) {
                        loadImage(from: url)
                    } else if DocumentTextExtractor.isSupported(url: url) {
                        loadDocument(from: url)
                    } else {
                        appendAttachment(.failed(
                            id: UUID(),
                            fileName: url.lastPathComponent,
                            message: "That file type can’t be read as text."
                        ))
                    }
                }
            }
        }
        return acceptedAny
    }

    private func promptContextView(_ context: PromptContext) -> some View {
        HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(MarkViewDesign.accent.opacity(0.55))
                .frame(width: 2.5)
                .frame(height: 46)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Image(systemName: context.source.symbol)
                        .font(.system(size: 9.5, weight: .semibold))
                    Text(context.source.label)
                        .font(.system(size: 10.5, weight: .semibold))
                    Text("· \(context.characterCount) chars")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(MarkViewDesign.accent)

                Text(context.text)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.primary)
                    .lineLimit(6)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 2) {
                Button {
                    pinnedContext = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove pinned context")
                .help("Remove this context")

                if context.source == .document {
                    Button {
                        let location = DocumentLocation(
                            heading: nil,
                            quote: context.text,
                            startLine: nil,
                            endLine: nil,
                            blockId: nil
                        )
                        onNavigateToLocation?(location)
                    } label: {
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 20, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Show pinned context in document")
                    .help("Show in document")
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(MarkViewDesign.referenceSurface)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(MarkViewDesign.strongBorder.opacity(0.72), lineWidth: 0.7)
        )
        .shadow(color: MarkViewDesign.shadow.opacity(0.35), radius: 6, y: 2)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Pinned context: \(context.source.label)")
    }

    private func editProposalCard(_ proposal: AIEditProposal) -> some View {
        let diff = DiffEngine.computeDiff(original: documentText, modified: proposal.updatedDocument)

        return VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                Image(systemName: proposalStatusSymbol(proposal.status))
                    .foregroundStyle(proposal.status == .applied ? .green : MarkViewDesign.accent)
                Text(proposalStatusTitle(proposal.status))
                    .font(.system(size: 12.5, weight: .semibold))
                Spacer()
            }

            if proposal.status == .pending {
                Text(proposal.summary)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)

                // A scoped edit can say what it touches before showing a
                // single character of diff.
                if !proposal.changes.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(proposal.changes.prefix(5).enumerated()), id: \.offset) { _, change in
                            HStack(alignment: .top, spacing: 5) {
                                Image(systemName: "arrow.turn.down.right")
                                    .font(.system(size: 8.5, weight: .semibold))
                                    .foregroundStyle(MarkViewDesign.accent.opacity(0.8))
                                    .padding(.top, 2)
                                Text(change)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                            }
                        }
                        if proposal.changes.count > 5 {
                            Text("and \(proposal.changes.count - 5) more")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.tertiary)
                                .padding(.leading, 14)
                        }
                    }
                    .padding(.top, 1)
                }

                HStack(spacing: 10) {
                    Text("+\(diff.additions)")
                        .foregroundStyle(.green)
                    Text("−\(diff.deletions)")
                        .foregroundStyle(.red)
                    Spacer()
                    Button("Review Changes") { onReviewEdit?(proposal) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    Button("Discard") { aiService.discardProposal() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    Button("Apply") { applyProposal(proposal) }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
                .font(.system(size: 11.5, weight: .medium))
            } else {
                Text(proposalStatusDetail(proposal.status))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                if proposal.status == .applied && proposal.id == latestAppliedProposalID {
                    HStack(spacing: 8) {
                        Spacer()
                        Button {
                            onUndoLastEdit?()
                            aiService.markProposalReverted(proposal)
                        } label: {
                            Label("Undo", systemImage: "arrow.uturn.backward")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button {
                            revertProposal(proposal)
                        } label: {
                            Label("Revert", systemImage: "arrow.counterclockwise")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
        }
        .padding(12)
        .background(MarkViewDesign.secondarySurface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(MarkViewDesign.strongBorder.opacity(0.72), lineWidth: 0.8)
        )
        .shadow(color: MarkViewDesign.shadow.opacity(0.28), radius: 7, y: 2)
        .padding(.vertical, 5)
    }

    // MARK: - Actions

    private var latestAppliedProposalID: UUID? {
        for message in aiService.conversation.reversed() {
            for block in message.contentBlocks.reversed() {
                if case .editProposal(let proposal) = block, proposal.status == .applied {
                    return proposal.id
                }
            }
        }
        return nil
    }

    private func proposalStatusTitle(_ status: AIEditProposal.EditStatus) -> String {
        switch status {
        case .pending: return "Proposed changes"
        case .applied: return "Applied"
        case .discarded: return "Discarded"
        case .reverted: return "Reverted"
        }
    }

    private func proposalStatusDetail(_ status: AIEditProposal.EditStatus) -> String {
        switch status {
        case .pending: return "Review the proposed document update."
        case .applied: return "The source and preview are up to date."
        case .discarded: return "No changes were made to the document."
        case .reverted: return "The document was restored to its previous version."
        }
    }

    private func proposalStatusSymbol(_ status: AIEditProposal.EditStatus) -> String {
        switch status {
        case .pending: return "sparkles"
        case .applied: return "checkmark.circle.fill"
        case .discarded: return "xmark.circle"
        case .reverted: return "arrow.counterclockwise.circle.fill"
        }
    }

    private func revertProposal(_ proposal: AIEditProposal) {
        guard let originalDocument = proposal.originalDocument else { return }
        onApplyEdit?(originalDocument)
        aiService.markProposalReverted(proposal)
    }

    private func submitCurrentPrompt() {
        guard canSubmitPrompt else { return }

        let typedPrompt = inputPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        var sections: [String] = typedPrompt.isEmpty ? [] : [typedPrompt]

        // Text-shaped attachments are expanded into the prompt under their own
        // heading, so the model can tell them apart from the question.
        for attachment in attachments {
            switch attachment {
            case .pastedText(let item):
                sections.append("--- \(item.title) ---\n\(item.text)")
            case .textFile(_, let name, let contents):
                sections.append("--- Attached file: \(name) ---\n\(contents)")
            case .document(let document):
                sections.append(document.promptRepresentation)
            case .image, .loadingImage, .loadingDocument, .failed:
                continue
            }
        }

        submitPrompt(sections.joined(separator: "\n\n"), images: attachedImages)
        inputPrompt = ""
        withAnimation(attachmentAnimation) {
            attachments.removeAll()
        }
        pasteCounter = 0
    }

    private func submitPrompt(
        _ prompt: String,
        using context: PromptContext? = nil,
        images: [AIImageAttachment] = []
    ) {
        lastPrompt = prompt
        let effectiveContext = context ?? pinnedContext

        // Only a *document* selection may be handed over as `selectedText`:
        // that parameter tells the model to confine its edit to that passage,
        // and text quoted from a reply isn't in the document at all. Reply
        // context travels as a quote inside the prompt instead.
        var outgoingPrompt = prompt
        var documentSelection: String?

        switch effectiveContext?.source {
        case .document:
            documentSelection = effectiveContext?.text
        case .reply:
            if let quoted = effectiveContext?.text {
                outgoingPrompt = """
                About this part of your previous reply:

                \(quoted.split(separator: "\n", omittingEmptySubsequences: false).map { "> \($0)" }.joined(separator: "\n"))

                \(prompt)
                """
            }
        case nil:
            break
        }

        aiService.sendMessage(
            prompt: outgoingPrompt,
            documentText: documentText,
            selectedText: documentSelection,
            documentType: fileExtension,
            fileURL: fileURL,
            images: images
        )
    }

    private func applyProposal(_ proposal: AIEditProposal) {
        if DocumentSafetyService.hasFileChangedExternally(fileURL: fileURL, originalHash: proposal.originalHash) {
            conflictError = "The file on disk changed after this proposal was prepared. Review it before applying."
            return
        }
        forceApplyProposal(proposal)
    }

    private func forceApplyProposal(_ proposal: AIEditProposal) {
        aiService.currentState = .applying
        onApplyEdit?(proposal.updatedDocument)
        aiService.markProposalApplied(proposal)
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        if animated && !reduceMotion {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo("conversation-bottom", anchor: .bottom)
            }
        } else {
            proxy.scrollTo("conversation-bottom", anchor: .bottom)
        }
    }

    private func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

private struct PromptEditor: NSViewRepresentable {
    @Binding var text: String
    /// Changes whenever something outside the composer wants the caret here,
    /// e.g. "Ask Markowski" on a preview selection.
    var focusToken: UUID?
    let onSubmit: () -> Void
    /// Called instead of inserting, when a paste is long enough to bury the
    /// prompt. Returning the text to the composer keeps it out of the field.
    var onPasteLongText: ((String) -> Void)?
    var onPasteImage: ((NSImage) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = PromptScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = false
        scrollView.scrollerStyle = .legacy
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let textView = PromptTextView()
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textColor = .labelColor
        textView.font = .systemFont(ofSize: 15)
        textView.textContainerInset = NSSize(width: 5, height: 5)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(
            width: max(scrollView.contentSize.width, 1),
            height: .greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = true
        textView.delegate = context.coordinator
        textView.onSubmit = { [weak coordinator = context.coordinator, weak textView] in
            textView?.window?.makeFirstResponder(nil)
            coordinator?.parent.onSubmit()
        }
        textView.onPasteLongText = { [weak coordinator = context.coordinator] text in
            coordinator?.parent.onPasteLongText?(text)
        }
        textView.onPasteImage = { [weak coordinator = context.coordinator] image in
            coordinator?.parent.onPasteImage?(image)
        }
        textView.placeholder = "Ask me anything…"
        textView.setAccessibilityLabel("Ask Markowski")

        if #available(macOS 15.0, *) {
            textView.writingToolsBehavior = .none
        }

        scrollView.documentView = textView
        context.coordinator.textView = textView
        updateTextView(textView, with: text)
        applyTypography(to: textView)
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.parent = self

        guard let textView = nsView.documentView as? PromptTextView else { return }
        textView.onSubmit = { [weak coordinator = context.coordinator, weak textView] in
            textView?.window?.makeFirstResponder(nil)
            coordinator?.parent.onSubmit()
        }
        textView.onPasteLongText = { [weak coordinator = context.coordinator] pasted in
            coordinator?.parent.onPasteLongText?(pasted)
        }
        textView.onPasteImage = { [weak coordinator = context.coordinator] image in
            coordinator?.parent.onPasteImage?(image)
        }

        if textView.string != text {
            updateTextView(textView, with: text)
        }
        applyTypography(to: textView)

        if let focusToken, context.coordinator.lastFocusToken != focusToken {
            context.coordinator.lastFocusToken = focusToken
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
                textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))
            }
        }
    }

    private func updateTextView(_ textView: NSTextView, with text: String) {
        guard textView.string != text else { return }

        let selectedRange = textView.selectedRange()
        if let coordinator = textView.delegate as? Coordinator {
            coordinator.isUpdatingText = true
        }
        textView.string = text
        let location = min(selectedRange.location, text.utf16.count)
        textView.setSelectedRange(NSRange(location: location, length: 0))
        if let coordinator = textView.delegate as? Coordinator {
            coordinator.isUpdatingText = false
        }
        textView.scrollRangeToVisible(textView.selectedRange())
    }

    private func applyTypography(to textView: NSTextView) {
        let isRTL = TextDirection.isRightToLeft(textView.string)
        let font = MarkowskiTypography.font(size: 15, weight: .regular, for: textView.string)
        let paragraph = NSMutableParagraphStyle()
        paragraph.baseWritingDirection = isRTL ? .rightToLeft : .leftToRight
        paragraph.alignment = isRTL ? .right : .left
        paragraph.lineSpacing = 2

        textView.font = font
        textView.defaultParagraphStyle = paragraph
        textView.alignment = isRTL ? .right : .left
        textView.typingAttributes = [
            .font: font,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph
        ]
        if let storage = textView.textStorage, storage.length > 0 {
            storage.addAttributes([
                .font: font,
                .paragraphStyle: paragraph
            ], range: NSRange(location: 0, length: storage.length))
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PromptEditor
        weak var textView: NSTextView?
        var isUpdatingText = false
        var lastFocusToken: UUID?

        init(_ parent: PromptEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard !isUpdatingText, let textView else { return }
            parent.text = textView.string
            parent.applyTypography(to: textView)
            textView.scrollRangeToVisible(textView.selectedRange())
        }

    }
}

private final class PromptTextView: NSTextView {
    var onSubmit: (() -> Void)?
    var onPasteLongText: ((String) -> Void)?
    var onPasteImage: ((NSImage) -> Void)?
    var placeholder = "" {
        didSet { needsDisplay = true }
    }
    private var placeholderOpacity: CGFloat = 1 {
        didSet { needsDisplay = true }
    }
    private var placeholderAnimationGeneration = 0

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { animatePlaceholder(to: 0) }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned, string.isEmpty { animatePlaceholder(to: 1) }
        return resigned
    }

    /// Pasting an image or a long block of text is not a text edit — the first
    /// becomes an attachment, the second a numbered chip. Both are intercepted
    /// here so ⌘V, the Edit menu, and a right-click paste all behave the same.
    override func paste(_ sender: Any?) {
        let pasteboard = NSPasteboard.general

        if let image = pastedImage(from: pasteboard), let onPasteImage {
            onPasteImage(image)
            return
        }

        if let pasted = pasteboard.string(forType: .string),
           PromptAttachmentLimits.shouldBecomeChip(pasted),
           let onPasteLongText {
            onPasteLongText(pasted)
            return
        }

        super.paste(sender)
    }

    override func pasteAsPlainText(_ sender: Any?) {
        paste(sender)
    }

    private func pastedImage(from pasteboard: NSPasteboard) -> NSImage? {
        // A file copied in Finder arrives as a URL, not as image data.
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL],
           let url = urls.first(where: { ImageAttachmentLoader.isSupported(url: $0) }),
           let image = NSImage(contentsOf: url) {
            return image
        }
        guard pasteboard.canReadItem(withDataConformingToTypes: [
            NSPasteboard.PasteboardType.png.rawValue,
            NSPasteboard.PasteboardType.tiff.rawValue
        ]) else {
            return nil
        }
        return NSImage(pasteboard: pasteboard)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        super.mouseDown(with: event)
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        let isReturn = event.keyCode == 36 || event.keyCode == 76
        guard isReturn else {
            super.keyDown(with: event)
            return
        }

        if event.modifierFlags.contains(.shift) {
            super.keyDown(with: event)
        } else {
            onSubmit?()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard string.isEmpty, !placeholder.isEmpty else { return }

        let placeholderFont = font ?? NSFont.systemFont(ofSize: 15)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: placeholderFont,
            .foregroundColor: NSColor.secondaryLabelColor.withAlphaComponent(placeholderOpacity)
        ]
        let rect = NSRect(
            x: textContainerInset.width,
            y: textContainerInset.height,
            width: max(0, bounds.width - (textContainerInset.width * 2)),
            height: placeholderFont.ascender - placeholderFont.descender + placeholderFont.leading
        )
        placeholder.draw(in: rect, withAttributes: attributes)
    }

    override func didChangeText() {
        super.didChangeText()
        placeholderOpacity = string.isEmpty && window?.firstResponder !== self ? 1 : 0
        needsDisplay = true
    }

    private func animatePlaceholder(to value: CGFloat) {
        placeholderAnimationGeneration += 1
        let generation = placeholderAnimationGeneration
        let start = placeholderOpacity
        let steps = 8
        for step in 1...steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + (0.018 * Double(step))) { [weak self] in
                guard let self, self.placeholderAnimationGeneration == generation else { return }
                let progress = CGFloat(step) / CGFloat(steps)
                let eased = 1 - pow(1 - progress, 3)
                self.placeholderOpacity = start + ((value - start) * eased)
            }
        }
    }
}

private final class PromptScrollView: NSScrollView {
    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        super.mouseDown(with: event)
        if let textView = documentView as? PromptTextView {
            window?.makeFirstResponder(textView)
        }
    }
}

private struct ReferenceCard: View {
    let reference: DocumentReference
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(MarkViewDesign.accent)
                    .frame(width: 16, height: 18)

                VStack(alignment: .leading, spacing: 3) {
                    Text(reference.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if let preview = reference.preview, !preview.isEmpty {
                        Text(preview)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }

                Spacer(minLength: 4)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(isHovered ? Color.white.opacity(0.38) : MarkViewDesign.referenceSurface)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(MarkViewDesign.strongBorder.opacity(0.72), lineWidth: 0.7)
            )
            .shadow(color: MarkViewDesign.shadow.opacity(0.28), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovered = hovering }
        }
        .accessibilityLabel("Show \(reference.title) in document")
        .contextMenu {
            Button("Show in Document", action: action)
            Button("Copy Text") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(reference.preview ?? reference.title, forType: .string)
            }
        }
    }
}

private struct ThinkingRow: View {
    let reduceMotion: Bool
    @State private var isPulsing = false

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(MarkViewDesign.accent)
                .opacity(reduceMotion ? 0.85 : (isPulsing ? 1 : 0.45))
            Text("Thinking…")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
    }
}

private struct ModelProviderLogo: View {
    let provider: AIProviderType
    let size: CGFloat

    var body: some View {
        Image(provider.assetName)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
    }
}
