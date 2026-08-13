import SwiftUI

struct AISettingsView: View {
    @State private var selectedProvider: AIProviderType = .gemini
    @State private var keyDraft = ""
    @State private var configuredProviders: Set<AIProviderType> = []
    @State private var editingProviders: Set<AIProviderType> = []
    @State private var testingProvider: AIProviderType?
    @State private var statusByProvider: [AIProviderType: String] = [:]
    @State private var modelsByProvider: [AIProviderType: [AIModel]] = [:]
    @State private var loadingModels: Set<AIProviderType> = []
    @State private var modelSearch = ""
    @State private var enabledModelIDs: [AIProviderType: Set<String>] = [:]
    @State private var expandedModelID: String?
    @ObservedObject private var tokenUsage = AITokenUsageStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    private var visibleProviders: [AIProviderType] {
        AIProviderType.allCases.filter { $0 != .mock }
    }

    var body: some View {
        HStack(spacing: 12) {
            providerRail
            detailPane
        }
        .padding(12)
        .frame(width: 980, height: 720)
        .background(settingsBackdrop)
        .onAppear {
            loadKeys()
        }
        .task(id: selectedProvider) { await loadModels(for: selectedProvider) }
        .onReceive(NotificationCenter.default.publisher(for: AIModelPreferences.didChange)) { _ in
            enabledModelIDs[selectedProvider] = AIModelPreferences.enabledIDs(for: selectedProvider)
        }
    }

    private var providerRail: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image("MarkowskiToolbar")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 34, height: 34)
                    .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.10 : 0.075), radius: 4.5, x: 0, y: 1.5)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Markowski")
                        .font(.system(size: 15, weight: .semibold))
                    Text("AI providers")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)

            ScrollView {
                LazyVStack(spacing: 5) {
                    ForEach(visibleProviders) { provider in
                        Button {
                            withAnimation(.easeOut(duration: 0.16)) {
                                selectedProvider = provider
                                keyDraft = ""
                                modelSearch = ""
                            }
                        } label: {
                            HStack(spacing: 10) {
                                ProviderLogo(provider: provider, size: 28)
                                Text(provider.rawValue)
                                    .font(.system(size: 12.5, weight: selectedProvider == provider ? .semibold : .medium))
                                    .foregroundStyle(.primary)
                                Spacer(minLength: 4)
                                Circle()
                                    .fill(configuredProviders.contains(provider) ? successColor : Color.secondary.opacity(0.25))
                                    .frame(width: 7, height: 7)
                                    .shadow(
                                        color: configuredProviders.contains(provider) ? statusGlowColor.opacity(0.34) : .clear,
                                        radius: 3
                                    )
                            }
                            .padding(.horizontal, 10)
                            .frame(height: 42)
                            .background(selectedProvider == provider ? MarkViewDesign.accentSoft : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
            }

            privacyNote
                .padding(12)
        }
        .frame(width: 226)
        .background(settingsPanel)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(panelBorder)
    }

    private var detailPane: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ProviderLogo(provider: selectedProvider, size: 42)
                VStack(alignment: .leading, spacing: 3) {
                    Text(selectedProvider.rawValue)
                        .font(.system(size: 20, weight: .semibold))
                    Text(selectedProvider.settingsSubtitle)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                connectionBadge
            }
            .padding(22)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    connectionCard
                    modelSelectionCard
                    privacyCard
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 22)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(settingsPanel)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(panelBorder)
    }

    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("API connection", systemImage: "key.horizontal")
                .font(.system(size: 14, weight: .semibold))

            Text("Your key is stored in macOS Keychain and is sent only to \(selectedProvider.rawValue).")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)

            if !configuredProviders.contains(selectedProvider) || editingProviders.contains(selectedProvider) {
                SecureField("Paste \(selectedProvider.shortDisplayName) API key", text: $keyDraft)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .frame(height: 38)
                    .background(Color.primary.opacity(colorScheme == .dark ? 0.07 : 0.035))
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(MarkViewDesign.strongBorder, lineWidth: 0.7))

                HStack {
                    Label("Secure Keychain storage", systemImage: "lock.fill")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if editingProviders.contains(selectedProvider) {
                        Button("Cancel") { cancelEditing() }
                            .buttonStyle(.bordered)
                    }
                    Button("Save key") { saveKey() }
                        .buttonStyle(.borderedProminent)
                        .tint(MarkViewDesign.accent)
                        .disabled(keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } else {
                HStack(spacing: 9) {
                    Label("API key securely stored", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(successColor)
                        .font(.system(size: 12.5, weight: .medium))
                    Spacer()
                    Button("Replace") { beginEditing() }
                        .buttonStyle(.bordered)
                    Button("Remove", role: .destructive) { removeKey() }
                        .buttonStyle(.bordered)
                    Button {
                        testConnection()
                    } label: {
                        if testingProvider == selectedProvider {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Test", systemImage: "bolt.horizontal.circle")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(testingProvider != nil)
                }
            }

            if let status = statusByProvider[selectedProvider] {
                Label(status, systemImage: status.localizedCaseInsensitiveContains("failed") ? "exclamationmark.triangle" : "info.circle")
                    .font(.system(size: 11.5))
                    .foregroundStyle(status.localizedCaseInsensitiveContains("failed") ? .red : .secondary)
            }
        }
        .settingsCard()
    }

    private var modelSelectionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Models in the prompt box", systemImage: "checklist")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button {
                    Task { await loadModels(for: selectedProvider, force: true) }
                } label: {
                    if loadingModels.contains(selectedProvider) {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(!configuredProviders.contains(selectedProvider) || loadingModels.contains(selectedProvider))
            }

            Text("Current text-capable models are loaded directly from \(selectedProvider.shortDisplayName). Uncheck any model you do not want in the composer.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            if configuredProviders.contains(selectedProvider) {
                TextField("Search \(selectedProvider.shortDisplayName) models", text: $modelSearch)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 11)
                    .frame(height: 34)
                    .background(Color.primary.opacity(0.045))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                let models = filteredSettingsModels
                if models.isEmpty && !loadingModels.contains(selectedProvider) {
                    Text("No matching text models were returned. Refresh or test the API connection.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(models) { model in
                            VStack(spacing: 0) {
                                HStack(spacing: 9) {
                                    Button { toggleModel(model) } label: {
                                        Image(systemName: isModelEnabled(model) ? "checkmark.square.fill" : "square")
                                            .font(.system(size: 17, weight: .medium))
                                            .foregroundStyle(isModelEnabled(model) ? MarkViewDesign.accent : Color.secondary)
                                            .frame(width: 22, height: 30)
                                            .symbolEffect(.bounce, value: isModelEnabled(model))
                                    }
                                    .buttonStyle(.plain)
                                    .help(isModelEnabled(model) ? "Hide from prompt box" : "Show in prompt box")

                                    ProviderLogo(provider: model.provider, size: 30)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(model.displayName)
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                        if model.displayName != model.id {
                                            Text(model.id)
                                                .font(.system(size: 10.5))
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                                .truncationMode(.middle)
                                        }
                                        tokenUsageLine(for: model)
                                    }
                                    Spacer(minLength: 0)

                                    Button {
                                        withAnimation(reduceMotion ? nil : .spring(response: 0.26, dampingFraction: 0.84)) {
                                            expandedModelID = expandedModelID == model.id ? nil : model.id
                                        }
                                    } label: {
                                        Label(
                                            tokenUsage.policy(for: model).hasLimit ? "Limit set" : "Set limit",
                                            systemImage: "gauge.with.dots.needle.50percent"
                                        )
                                        .font(.system(size: 11.5, weight: .medium))
                                        .padding(.horizontal, 9)
                                        .frame(height: 28)
                                        .background(Color.primary.opacity(0.055))
                                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 12)
                                .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)

                                if expandedModelID == model.id {
                                    Divider().opacity(0.6)
                                    modelPolicyEditor(model)
                                        .transition(.opacity.combined(with: .move(edge: .top)))
                                }
                            }
                            .background(Color.primary.opacity(0.035))
                            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Color.primary.opacity(0.055), lineWidth: 0.6))
                        }
                    }
                }
            } else {
                Label("Add an API key to load this provider’s models.", systemImage: "key")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            }
        }
        .settingsCard()
    }

    @ViewBuilder
    private func tokenUsageLine(for model: AIModel) -> some View {
        let usage = tokenUsage.usage(for: model)
        let policy = tokenUsage.policy(for: model)
        let period = policy.resetPeriod == .daily ? "today" : "used"
        if policy.hasLimit {
            Text("\(compactTokens(usage.totalTokens)) \(period) • \(compactTokens(tokenUsage.remainingTokens(for: model) ?? 0)) left")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(usage.totalTokens == 0 ? Color.secondary : MarkViewDesign.accent)
        } else {
            Text("\(compactTokens(usage.totalTokens)) tokens \(period)\(usage.containsEstimate ? " • estimated" : "")")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private func modelPolicyEditor(_ model: AIModel) -> some View {
        let policy = tokenUsage.policy(for: model)
        let usage = tokenUsage.usage(for: model)
        let progress = policy.tokenLimit.map { min(1, Double(usage.totalTokens) / Double(max(1, $0))) } ?? 0

        return VStack(alignment: .leading, spacing: 14) {
            // Top-aligned: these columns hold different numbers of rows — the
            // schedule carries a caption the limit doesn't — so centring them
            // put their headings at different heights and the row read as
            // misaligned.
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Token limit")
                        .font(.system(size: 11.5, weight: .semibold))
                    HStack(spacing: 7) {
                        Toggle("", isOn: Binding(
                            get: { policy.hasLimit },
                            set: { enabled in
                                var updated = tokenUsage.policy(for: model)
                                updated.tokenLimit = enabled ? (updated.tokenLimit ?? 100_000) : nil
                                tokenUsage.updatePolicy(updated)
                            }
                        ))
                        .labelsHidden()
                        TextField("No limit", value: Binding(
                            get: { tokenUsage.policy(for: model).tokenLimit },
                            set: { value in
                                var updated = tokenUsage.policy(for: model)
                                updated.tokenLimit = value
                                tokenUsage.updatePolicy(updated)
                            }
                        ), format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 118)
                        .disabled(!policy.hasLimit)
                        Text("tokens")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Reset schedule")
                        .font(.system(size: 11.5, weight: .semibold))
                    Picker("Reset schedule", selection: Binding(
                        get: { tokenUsage.policy(for: model).resetPeriod },
                        set: { value in
                            var updated = tokenUsage.policy(for: model)
                            updated.resetPeriod = value
                            tokenUsage.updatePolicy(updated)
                        }
                    )) {
                        ForEach(AITokenResetPeriod.allCases) { period in
                            Text(period.rawValue).tag(period)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 188)

                    // Tied to the control's width and allowed to wrap. At
                    // `lineLimit(1)` this caption ran wider than the segmented
                    // control above it and pushed the column out of line.
                    Text(tokenUsage.policy(for: model).resetPeriod.detail)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: 188, alignment: .leading)
                }

                if AIModelCatalog.supportsReasoningEffort(model) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Reasoning effort")
                            .font(.system(size: 11.5, weight: .semibold))
                        effortControl(model)
                    }
                }

                Spacer(minLength: 0)
            }

            if let limit = policy.tokenLimit {
                ProgressView(value: progress)
                    .tint(progress > 0.9 ? .orange : MarkViewDesign.accent)
                HStack {
                    Text("\(compactTokens(usage.totalTokens)) used")
                    Spacer()
                    Text("\(compactTokens(max(0, limit - usage.totalTokens))) remaining")
                }
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
            }

            HStack {
                Text(usage.containsEstimate ? "Includes estimated usage" : "Usage reported by the provider")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                Spacer()
                Button {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                        tokenUsage.reset(model)
                    }
                } label: {
                    Label("Reset now", systemImage: "arrow.counterclockwise")
                }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(14)
        .background(Color.primary.opacity(0.018))
    }

    private func effortControl(_ model: AIModel) -> some View {
        let effort = tokenUsage.policy(for: model).reasoningEffort ?? .medium
        return HStack(spacing: 8) {
            Text("Low")
            Slider(value: Binding(
                get: { Double(effort.rawValue) },
                set: { value in
                    var updated = tokenUsage.policy(for: model)
                    updated.reasoningEffort = AIReasoningEffort(rawValue: Int(value.rounded())) ?? .medium
                    tokenUsage.updatePolicy(updated)
                }
            ), in: 0...2, step: 1)
            .frame(width: 92)
            Text("High")
        }
        .font(.system(size: 10.5, weight: .medium))
        .foregroundStyle(.secondary)
        .help("Current effort: \(effort.label)")
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

    private var filteredSettingsModels: [AIModel] {
        let models = modelsByProvider[selectedProvider] ?? []
        let query = modelSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return models }
        return models.filter {
            $0.id.localizedCaseInsensitiveContains(query)
                || $0.displayName.localizedCaseInsensitiveContains(query)
        }
    }

    private var privacyCard: some View {
        HStack(alignment: .top, spacing: 12) {
            SettingsGlyph(systemName: "hand.raised.fill", tint: .green)
            VStack(alignment: .leading, spacing: 5) {
                Text("Private until you send")
                    .font(.system(size: 13.5, weight: .semibold))
                Text("Opening a document or configuring a key sends nothing. Document content reaches only the provider selected for a prompt.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .settingsCard()
    }

    private var privacyNote: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lock.shield.fill")
                .foregroundStyle(.green)
            Text("Keys stay in Keychain")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private var connectionBadge: some View {
        Text(configuredProviders.contains(selectedProvider) ? "Connected" : "Not connected")
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(configuredProviders.contains(selectedProvider) ? successColor : Color.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background((configuredProviders.contains(selectedProvider) ? Color.green : Color.secondary).opacity(0.11))
            .clipShape(Capsule())
    }

    private var successColor: Color {
        colorScheme == .dark ? .green : Color(red: 0.04, green: 0.52, blue: 0.19)
    }

    private var statusGlowColor: Color {
        colorScheme == .dark ? .green : Color(red: 0.12, green: 0.72, blue: 0.28)
    }

    private var settingsBackdrop: some View {
        LinearGradient(
            colors: colorScheme == .dark
                ? [Color(nsColor: .windowBackgroundColor), Color.black.opacity(0.22)]
                : [Color(red: 0.965, green: 0.958, blue: 0.947), Color(red: 0.935, green: 0.925, blue: 0.910)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var settingsPanel: some ShapeStyle {
        colorScheme == .dark
            ? AnyShapeStyle(Color(nsColor: .controlBackgroundColor))
            : AnyShapeStyle(Color.white.opacity(0.88))
    }

    private var panelBorder: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.09), lineWidth: 0.8)
            .allowsHitTesting(false)
    }

    private func loadKeys() {
        configuredProviders = Set(visibleProviders.filter { provider in
            !(KeychainService.shared.getKey(forAccount: provider.keychainAccount) ?? "").isEmpty
        })
    }

    private func beginEditing() {
        keyDraft = ""
        editingProviders.insert(selectedProvider)
        statusByProvider[selectedProvider] = nil
    }

    private func cancelEditing() {
        keyDraft = ""
        editingProviders.remove(selectedProvider)
    }

    private func saveKey() {
        let provider = selectedProvider
        let trimmed = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try KeychainService.shared.saveKey(trimmed, forAccount: provider.keychainAccount)
            configuredProviders.insert(provider)
            editingProviders.remove(provider)
            keyDraft = ""
            statusByProvider[provider] = "Key saved securely. Test the connection when ready."
            Task { await loadModels(for: provider, force: true) }
        } catch {
            statusByProvider[provider] = "Save failed: \(error.localizedDescription)"
        }
    }

    private func removeKey() {
        let provider = selectedProvider
        try? KeychainService.shared.deleteKey(forAccount: provider.keychainAccount)
        configuredProviders.remove(provider)
        editingProviders.remove(provider)
        keyDraft = ""
        statusByProvider[provider] = "Key removed."
        modelsByProvider[provider] = []
    }

    private func testConnection() {
        let provider = selectedProvider
        guard let key = KeychainService.shared.getKey(forAccount: provider.keychainAccount), !key.isEmpty else { return }
        testingProvider = provider
        statusByProvider[provider] = "Testing connection…"
        Task {
            do {
                let success = try await SettingsProviderFactory.provider(for: provider).testConnection(apiKey: key)
                await MainActor.run {
                    testingProvider = nil
                    statusByProvider[provider] = success ? "Connection successful." : "Connection failed: no usable text models found."
                }
            } catch {
                await MainActor.run {
                    testingProvider = nil
                    statusByProvider[provider] = "Connection failed: \(error.localizedDescription)"
                }
            }
        }
    }

    @MainActor
    private func loadModels(for provider: AIProviderType, force: Bool = false) async {
        guard configuredProviders.contains(provider),
              let key = KeychainService.shared.getKey(forAccount: provider.keychainAccount),
              !key.isEmpty else { return }
        if !force, modelsByProvider[provider] != nil { return }

        loadingModels.insert(provider)
        defer { loadingModels.remove(provider) }
        do {
            let models = try await SettingsProviderFactory.provider(for: provider).fetchModels(apiKey: key)
            AIModelPreferences.installDefaultsIfNeeded(for: provider, models: models)
            modelsByProvider[provider] = models
            enabledModelIDs[provider] = AIModelPreferences.enabledIDs(for: provider)
        } catch {
            modelsByProvider[provider] = []
            statusByProvider[provider] = "Model refresh failed: \(error.localizedDescription)"
        }
    }

    private func isModelEnabled(_ model: AIModel) -> Bool {
        enabledModelIDs[model.provider, default: []].contains(model.id)
    }

    private func toggleModel(_ model: AIModel) {
        let enabled = !isModelEnabled(model)
        withAnimation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.72)) {
            var ids = enabledModelIDs[model.provider, default: []]
            if enabled { ids.insert(model.id) } else { ids.remove(model.id) }
            enabledModelIDs[model.provider] = ids
        }
        AIModelPreferences.setEnabled(enabled, for: model)
    }
}

private enum SettingsProviderFactory {
    static func provider(for type: AIProviderType) -> AIProvider {
        switch type {
        case .gemini: return GeminiProvider()
        case .openAI: return OpenAIProvider()
        case .anthropic: return AnthropicProvider()
        case .openRouter: return compatible(.openRouter, "https://openrouter.ai/api/v1")
        case .mistral: return compatible(.mistral, "https://api.mistral.ai/v1")
        case .groq: return compatible(.groq, "https://api.groq.com/openai/v1")
        case .xAI: return compatible(.xAI, "https://api.x.ai/v1")
        case .deepSeek: return compatible(.deepSeek, "https://api.deepseek.com/v1")
        case .mock: return MockAIProvider()
        }
    }

    private static func compatible(_ type: AIProviderType, _ url: String) -> AIProvider {
        OpenAICompatibleProvider(providerType: type, baseURL: URL(string: url)!)
    }
}

private struct ProviderLogo: View {
    let provider: AIProviderType
    let size: CGFloat

    var body: some View {
        Image(provider.assetName)
            .resizable()
            .scaledToFit()
            .padding(logoPadding)
            .frame(width: size, height: size)
            .background(logoBackground)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.27, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: size * 0.27).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.6))
    }

    private var logoPadding: CGFloat {
        switch provider {
        case .gemini: return size * 0.10
        case .openAI: return size * 0.02
        default: return size * 0.16
        }
    }

    private var logoBackground: Color {
        provider == .gemini ? Color.white : Color.primary.opacity(0.045)
    }
}

private struct SettingsGlyph: View {
    let systemName: String
    let tint: Color
    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 34, height: 34)
            .background(tint.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

private extension View {
    func settingsCard() -> some View {
        padding(16)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.7))
            .shadow(color: Color.black.opacity(0.035), radius: 7, y: 2)
    }
}
