/// The result of loading one plan entry.
public struct LoadOutcome: Sendable {
    /// Resolve key of the entry.
    public let key: String
    /// Optional name of the entry.
    public let name: String?
    /// Status read right after the plugin was registered; a plugin awaiting services is still `.pending`.
    public let status: Fork.Status
}

extension Context {
    /// Loads the plan in order and returns one outcome per entry.
    /// An invalid plan loads nothing: every entry is reported as failed.
    public func load(_ plan: LoadPlan, registry: PluginRegistry) async -> [LoadOutcome] {
        let errors = plan.validate(against: registry)
        guard errors.isEmpty else {
            return plan.entries.enumerated().map { index, entry in
                let reasons = errors.filter { $0.entry == index }.map(\.description)
                let reason = reasons.isEmpty ? "plan is invalid; nothing was loaded" : reasons
                    .joined(separator: "; ")
                return LoadOutcome(key: entry.key, name: entry.name, status: .failed(reason))
            }
        }

        var outcomes: [LoadOutcome] = []
        for entry in plan.entries {
            let status: Fork.Status
            do {
                guard let loader = try registry.loader(for: entry.key, config: entry.config) else {
                    throw LoaderError.unknownKey(entry.key, entry: outcomes.count)
                }

                status = await loader(self)
            } catch {
                status = .failed(String(describing: error))
            }
            outcomes.append(LoadOutcome(key: entry.key, name: entry.name, status: status))
        }
        return outcomes
    }
}

extension LoaderError {
    var entry: Int {
        switch self {
        case let .unknownKey(_, entry), let .duplicateName(_, entry), let .invalidConfig(_, entry, _): entry
        }
    }
}
