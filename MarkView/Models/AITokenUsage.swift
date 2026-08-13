import Foundation

struct AITokenUsage: Codable, Equatable, Sendable {
    var inputTokens: Int
    var outputTokens: Int
    var isEstimated: Bool = false

    var totalTokens: Int { inputTokens + outputTokens }
}

enum AIStreamEvent: Sendable {
    case text(String)
    case usage(AITokenUsage)
}

enum AITokenResetPeriod: String, CaseIterable, Codable, Identifiable {
    case manual = "Manual"
    case daily = "Daily"

    var id: String { rawValue }

    var detail: String {
        switch self {
        case .manual: return "Only when you press Reset now"
        case .daily: return "Automatically at local midnight"
        }
    }

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        // Keep policies saved by the earlier “Never” wording working.
        self = value == "Daily" ? .daily : .manual
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum AIReasoningEffort: Int, CaseIterable, Codable, Identifiable {
    case low
    case medium
    case high

    var id: Int { rawValue }
    var label: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }

    var apiValue: String { label.lowercased() }
}

struct AIModelTokenPolicy: Codable, Equatable {
    var provider: AIProviderType
    var modelID: String
    var tokenLimit: Int?
    var resetPeriod: AITokenResetPeriod = .daily
    var reasoningEffort: AIReasoningEffort?

    var hasLimit: Bool { tokenLimit != nil }
}

struct AIModelUsageSnapshot: Codable, Equatable {
    var inputTokens = 0
    var outputTokens = 0
    var containsEstimate = false
    var periodStamp: String?

    var totalTokens: Int { inputTokens + outputTokens }
}

@MainActor
final class AITokenUsageStore: ObservableObject {
    static let shared = AITokenUsageStore()

    @Published private(set) var usageByModel: [String: AIModelUsageSnapshot] = [:]
    @Published private(set) var policies: [String: AIModelTokenPolicy] = [:]

    private let defaults = UserDefaults.standard
    private let usageKey = "aiTokenUsage_v2"
    private let policyKey = "aiModelTokenPolicies_v1"

    private init() {
        if let data = defaults.data(forKey: usageKey),
           let decoded = try? JSONDecoder().decode([String: AIModelUsageSnapshot].self, from: data) {
            usageByModel = decoded
        }
        if let data = defaults.data(forKey: policyKey),
           let decoded = try? JSONDecoder().decode([String: AIModelTokenPolicy].self, from: data) {
            policies = decoded
        }

        // Pool-based defaults from the earlier design are intentionally not
        // migrated: limits now belong to individual models and start unset.
        defaults.removeObject(forKey: "aiTokenLimitRules_v1")
        defaults.removeObject(forKey: "aiTokenUsageDay_v1")
        defaults.removeObject(forKey: "aiTokenUsage_v1")
    }

    func policy(for model: AIModel) -> AIModelTokenPolicy {
        policies[modelKey(model)] ?? AIModelTokenPolicy(
            provider: model.provider,
            modelID: model.id,
            tokenLimit: nil,
            resetPeriod: .daily,
            reasoningEffort: AIModelCatalog.supportsReasoningEffort(model) ? .medium : nil
        )
    }

    func usage(for model: AIModel) -> AIModelUsageSnapshot {
        resetIfNeeded(model)
        return usageByModel[modelKey(model), default: AIModelUsageSnapshot(periodStamp: Self.dayStamp())]
    }

    func remainingTokens(for model: AIModel) -> Int? {
        let policy = policy(for: model)
        guard let limit = policy.tokenLimit else { return nil }
        return max(0, limit - usage(for: model).totalTokens)
    }

    func updatePolicy(_ policy: AIModelTokenPolicy) {
        var sanitized = policy
        if let limit = policy.tokenLimit { sanitized.tokenLimit = max(1, limit) }
        if !AIModelCatalog.supportsReasoningEffort(
            AIModel(id: policy.modelID, displayName: policy.modelID, provider: policy.provider)
        ) {
            sanitized.reasoningEffort = nil
        }
        policies[modelKey(provider: policy.provider, modelID: policy.modelID)] = sanitized
        savePolicies()
        if sanitized.resetPeriod == .daily {
            resetIfNeeded(provider: sanitized.provider, modelID: sanitized.modelID)
        }
    }

    func record(_ usage: AITokenUsage, for model: AIModel) {
        resetIfNeeded(model)
        let key = modelKey(model)
        var value = usageByModel[key, default: AIModelUsageSnapshot(periodStamp: Self.dayStamp())]
        value.inputTokens += max(0, usage.inputTokens)
        value.outputTokens += max(0, usage.outputTokens)
        value.containsEstimate = value.containsEstimate || usage.isEstimated
        value.periodStamp = Self.dayStamp()
        usageByModel[key] = value
        saveUsage()
    }

    func reset(_ model: AIModel) {
        usageByModel[modelKey(model)] = AIModelUsageSnapshot(periodStamp: Self.dayStamp())
        saveUsage()
    }

    private func resetIfNeeded(_ model: AIModel) {
        resetIfNeeded(provider: model.provider, modelID: model.id)
    }

    private func resetIfNeeded(provider: AIProviderType, modelID: String) {
        let key = modelKey(provider: provider, modelID: modelID)
        let policy = policies[key]
        guard policy?.resetPeriod == .daily,
              let snapshot = usageByModel[key],
              snapshot.periodStamp != Self.dayStamp() else { return }
        usageByModel[key] = AIModelUsageSnapshot(periodStamp: Self.dayStamp())
        saveUsage()
    }

    private func saveUsage() {
        defaults.set(try? JSONEncoder().encode(usageByModel), forKey: usageKey)
    }

    private func savePolicies() {
        defaults.set(try? JSONEncoder().encode(policies), forKey: policyKey)
    }

    private func modelKey(_ model: AIModel) -> String {
        modelKey(provider: model.provider, modelID: model.id)
    }

    private func modelKey(provider: AIProviderType, modelID: String) -> String {
        "\(provider.rawValue)::\(modelID)"
    }

    private static func dayStamp() -> String {
        let formatter = DateFormatter()
        formatter.calendar = .current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}

enum AITokenEstimator {
    static func inputTokens(
        prompt: String,
        documentText: String,
        selectedText: String?,
        history: [AIMessage],
        images: [AIImageAttachment]
    ) -> Int {
        let historyText = history.suffix(6).map(\.content).joined(separator: "\n")
        let characters = prompt.count + documentText.count + (selectedText?.count ?? 0) + historyText.count
        return max(1, Int(ceil(Double(characters) / 3.2))) + images.count * 1_200
    }
}

enum AITokenLimitError: LocalizedError {
    case exhausted(modelName: String, limit: Int)

    var errorDescription: String? {
        switch self {
        case .exhausted(let name, let limit):
            return "The token limit for \(name) has been reached (\(limit.formatted()) tokens). Change or reset it in AI Settings."
        }
    }
}
