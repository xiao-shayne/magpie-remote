import Foundation

/// `GET /api/tune`：按 Agent 给出的上下文/压缩优化建议。
struct TuneStateDTO: Codable, Sendable {
    var days: Int?
    var agents: [TuneAgentDTO]?
    var gateway: Bool?

    enum CodingKeys: String, CodingKey { case days, agents, gateway }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.days = try? c.decodeIfPresent(Int.self, forKey: .days)
        self.agents = (try? c.decodeIfPresent([TuneAgentDTO].self, forKey: .agents)) ?? []
        self.gateway = try? c.decodeIfPresent(Bool.self, forKey: .gateway)
    }
}

struct TuneAgentDTO: Codable, Sendable, Identifiable {
    var agent: String
    var calls: Int?
    var advice: [TuneAdviceDTO]?

    var id: String { agent }
    var displayName: String {
        switch agent {
        case "claude": return "Claude Code"
        case "codex": return "Codex"
        default: return agent
        }
    }

    enum CodingKeys: String, CodingKey { case agent, calls, advice }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.agent = (try? c.decode(String.self, forKey: .agent)) ?? ""
        self.calls = try? c.decodeIfPresent(Int.self, forKey: .calls)
        self.advice = (try? c.decodeIfPresent([TuneAdviceDTO].self, forKey: .advice)) ?? []
    }
}

/// 一条建议：knob 是 compact / cache / subcache / ttl 等，数值结构全部宽松读取。
struct TuneAdviceDTO: Codable, Sendable, Identifiable {
    var knob: String
    var model: String?
    var why: String?
    var applied: Bool?
    var setting: JSONValue?
    var compact: JSONValue?
    var ttl: JSONValue?
    var few: Bool?

    enum CodingKeys: String, CodingKey { case knob, model, why, applied, setting, compact, ttl, few }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.knob = (try? c.decode(String.self, forKey: .knob)) ?? ""
        self.model = try? c.decodeIfPresent(String.self, forKey: .model)
        self.why = try? c.decodeIfPresent(String.self, forKey: .why)
        self.applied = try? c.decodeIfPresent(Bool.self, forKey: .applied)
        self.setting = try? c.decodeIfPresent(JSONValue.self, forKey: .setting)
        self.compact = try? c.decodeIfPresent(JSONValue.self, forKey: .compact)
        self.ttl = try? c.decodeIfPresent(JSONValue.self, forKey: .ttl)
        self.few = try? c.decodeIfPresent(Bool.self, forKey: .few)
    }

    var id: String { "\(knob)-\(model ?? "")" }

    var title: String {
        switch knob {
        case "compact": return String(localized: "压缩阈值")
        case "cache": return String(localized: "提示词缓存")
        case "subcache": return String(localized: "子代理缓存")
        case "ttl": return String(localized: "缓存时长")
        default: return knob.capitalized
        }
    }

    var icon: String {
        switch knob {
        case "compact": return "arrow.down.right.and.arrow.up.left"
        case "cache": return "bolt.horizontal.circle.fill"
        case "subcache": return "person.2.badge.gearshape"
        case "ttl": return "clock.arrow.circlepath"
        default: return "wand.and.stars"
        }
    }

    /// 当前生效的值（TuneSetting 的宽松读取）。
    var currentValue: String? {
        if let v = setting?.string("value"), !v.isEmpty { return v }
        if let v = setting?.int("value") { return String(v) }
        if let v = setting?.string("now"), !v.isEmpty { return v }
        return nil
    }

    /// 建议采用的值：压缩阈值取 best，缓存时长取 ttl 的 best。
    var proposedValue: String? {
        if let compact {
            if let best = compact.int("best") { return String(best) }
        }
        if let ttl {
            if let best = ttl.string("best"), !best.isEmpty { return best }
            if let best = ttl.int("best") { return String(best) }
        }
        return nil
    }

    var calls: Int? {
        compact?.objectValue?["facts"]?.int("calls")
    }

    var window: Int? {
        compact?.int("window")
    }

    var savedTokens: Int? {
        compact?.objectValue?["facts"]?.int("saved")
    }

    var inUse: Bool {
        guard let currentValue, let proposedValue else { return false }
        return currentValue == proposedValue
    }

    /// Codex `config.toml` 中存在用户自设值且可由 magpie 接管（`POST /api/tune/takeover`）。
    var canTakeOver: Bool {
        setting?.bool("take") == true
    }

    var subtitle: String? {
        var parts: [String] = []
        if let calls { parts.append(String(localized: "\(calls) 次调用")) }
        if let window, window > 0 { parts.append(String(localized: "窗口 \(UsageDTO.formatTokens(window))")) }
        if let savedTokens, savedTokens > 0 { parts.append(String(localized: "预计省 \(UsageDTO.formatTokens(savedTokens))")) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
