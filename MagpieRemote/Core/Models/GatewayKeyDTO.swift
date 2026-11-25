import Foundation

/// magpie 网关调用密钥 (Caller / Gateway Key)
struct GatewayKeyDTO: Codable, Sendable, Identifiable, Hashable {
    var id: String
    var name: String?
    var masked: String?
    var off: Bool?
    var admin: String?
    var models: [String]?
    var accounts: [String]?
    var mcp: [String]?
    var readOnly: Bool?
    var browser: Bool?
    var lan: Bool?
    var quotas: Bool?
    var issues: Bool?
    var maxConcurrency: Int?
    var serviceTier: String?
    var redact: String?
    var memory: Bool?
    var routing: String?
    var expires: String?
    var limit: GatewayLimitDTO?
    var moreLimits: [GatewayLimitDTO]?
    /// 第一个限额已用量（`budget.Status`，旧字段）。
    var used: GatewayLimitUsageDTO?
    /// 每个限额的已用量，顺序与 `limits` 一致。
    var usedAll: [GatewayLimitUsageDTO]?

    var displayName: String {
        if let name, !name.isEmpty { return name }
        return masked ?? id
    }

    var isOff: Bool { off ?? false }
    var isAdmin: Bool { admin != nil && !(admin?.isEmpty ?? true) }
    var isReadOnly: Bool { readOnly ?? false }

    var limits: [GatewayLimitDTO] {
        var out: [GatewayLimitDTO] = []
        if let limit { out.append(limit) }
        if let moreLimits { out.append(contentsOf: moreLimits) }
        return out
    }

    var limitUsages: [GatewayLimitUsageDTO] {
        if let usedAll, !usedAll.isEmpty { return usedAll }
        if let used { return [used] }
        return []
    }

    /// 卡片上优先展示的限额：已用尽的里最晚重置的那个，否则第一个。
    var bindingLimitIndex: Int {
        let usages = limitUsages
        guard !usages.isEmpty else { return 0 }
        let spent = usages.indices.filter { usages[$0].isSpent }
        guard !spent.isEmpty else { return 0 }
        return spent.max {
            (usages[$0].resetDate ?? .distantPast) < (usages[$1].resetDate ?? .distantPast)
        } ?? 0
    }
}

/// 网关 Key 的预算窗口（access.Limit）。
struct GatewayLimitDTO: Codable, Sendable, Hashable, Identifiable {
    var period: String
    var days: Int?
    var hours: Int?
    var tokens: Int64?
    var cost: Double?
    var cacheReads: Bool?
    var since: String?
    var models: [String]?
    var account: String?
    var accountWindow: String?

    var id: String {
        "\(period)-\(days ?? 0)-\(hours ?? 0)-\(account ?? "")-\(accountWindow ?? "")-\(tokens ?? 0)-\(cost ?? 0)-\((models ?? []).joined(separator: "|"))"
    }

    var periodName: String {
        switch period {
        case "day": return String(localized: "每天")
        case "week": return String(localized: "每周")
        case "month": return String(localized: "每月")
        case "days": return String(localized: "每 \(days ?? 1) 天")
        case "hours": return String(localized: "每 \(hours ?? 1) 小时")
        case "account":
            let acc = account ?? ""
            let win = accountWindow ?? ""
            if !acc.isEmpty, !win.isEmpty { return "\(acc) · \(win)" }
            return String(localized: "跟随账号窗口")
        case "total": return String(localized: "累计")
        default: return period
        }
    }

    var hasCaps: Bool { (tokens ?? 0) > 0 || (cost ?? 0) > 0 }

    var capDescription: String {
        var parts: [String] = []
        if let tokens, tokens > 0 {
            parts.append(UsageDTO.formatTokens(Int(clamping: tokens)))
        }
        if let cost, cost > 0 {
            parts.append(String(format: "$%.2f", cost))
        }
        return parts.isEmpty ? String(localized: "无上限") : parts.joined(separator: " + ")
    }
}

/// `budget.Status`：某个限额窗口的已用量。GET `/api/caller-keys` 的
/// `used` / `usedAll` 字段，顺序与 `limit` / `moreLimits` 一致。
struct GatewayLimitUsageDTO: Codable, Sendable, Hashable {
    var period: String
    var days: Int?
    var hours: Int?
    var start: String?
    var reset: String?
    var calls: Int?
    var tokens: Int64?
    var cost: Double?
    var unpriced: Int?
    var inFlight: Int?
    var reserved: Int64?
    var reservedCost: Double?
    var tokenLimit: Int64?
    var costLimit: Double?
    var cacheReads: Bool?
    var models: [String]?
    var account: String?
    var accountWindow: String?
    var tokensLeft: Int64?
    var costLeft: Double?
    var spent: Bool?

    var isSpent: Bool { spent ?? false }

    var periodName: String {
        switch period {
        case "day": return String(localized: "每天")
        case "week": return String(localized: "每周")
        case "month": return String(localized: "每月")
        case "days": return String(localized: "每 \(days ?? 1) 天")
        case "hours": return String(localized: "每 \(hours ?? 1) 小时")
        case "account":
            if let account, !account.isEmpty, let accountWindow, !accountWindow.isEmpty {
                return "\(account) · \(accountWindow)"
            }
            return String(localized: "跟随账号窗口")
        case "total": return String(localized: "累计")
        default: return period
        }
    }

    /// 卡片上的紧凑用量，例如 `1.2 K / 2.00 K`、`$0.30 / $1.50`。
    var compactDescription: String {
        var parts: [String] = []
        if let tokenLimit, tokenLimit > 0 {
            parts.append("\(UsageDTO.formatTokens(Int(clamping: tokens ?? 0))) / \(UsageDTO.formatTokens(Int(clamping: tokenLimit)))")
        }
        if let costLimit, costLimit > 0 {
            parts.append(String(format: "$%.2f / $%.2f", cost ?? 0, costLimit))
        }
        if parts.isEmpty { return String(localized: "无上限") }
        let caps = parts.joined(separator: " · ")
        return isSpent ? String(localized: "已用尽 · \(caps)") : caps
    }

    var tokensLeftDescription: String? {
        guard let tokenLimit, tokenLimit > 0 else { return nil }
        return "\(UsageDTO.formatTokens(Int(clamping: tokensLeft ?? 0))) / \(UsageDTO.formatTokens(Int(clamping: tokenLimit)))"
    }

    var costLeftDescription: String? {
        guard let costLimit, costLimit > 0 else { return nil }
        return String(format: "$%.2f / $%.2f", costLeft ?? 0, costLimit)
    }

    var resetDate: Date? {
        Self.parseDate(reset)
    }

    var startDate: Date? {
        Self.parseDate(start)
    }

    static func parseDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: raw) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: raw)
    }
}

/// `GET /api/caller-keys` 响应体
struct GatewayKeysResponseDTO: Codable, Sendable {
    var keys: [GatewayKeyDTO]
    var secret: String?
    var accountNames: [String: String]?

    enum CodingKeys: String, CodingKey { case keys, secret, accountNames }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.keys = (try? c.decode([GatewayKeyDTO].self, forKey: .keys)) ?? []
        self.secret = try? c.decodeIfPresent(String.self, forKey: .secret)
        self.accountNames = try? c.decodeIfPresent([String: String].self, forKey: .accountNames)
    }
}

// MARK: - 网关状态
/// `/api/providers` 顶层 `gateway` 对象。
struct GatewayStateEnvelope: Codable, Sendable {
    var gateway: GatewayStateDTO?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.gateway = try? c.decodeIfPresent(GatewayStateDTO.self, forKey: .gateway)
    }

    enum CodingKeys: String, CodingKey { case gateway }
}

struct GatewayStateDTO: Codable, Sendable {
    var url: String?
    var lan: Bool?
    var lanURLs: [String]?
    var publicURL: String?
    var publicKind: String?
    var onNetwork: Bool?
    var running: Bool?
    var mine: Bool?
    var paused: Bool?
    var version: String?
    var older: Bool?
    var models: Int?
    var calls: [GatewayCallDTO]?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.url = try? c.decodeIfPresent(String.self, forKey: .url)
        self.lan = try? c.decodeIfPresent(Bool.self, forKey: .lan)
        self.lanURLs = try? c.decodeIfPresent([String].self, forKey: .lanURLs)
        self.publicURL = try? c.decodeIfPresent(String.self, forKey: .publicURL)
        self.publicKind = try? c.decodeIfPresent(String.self, forKey: .publicKind)
        self.onNetwork = try? c.decodeIfPresent(Bool.self, forKey: .onNetwork)
        self.running = try? c.decodeIfPresent(Bool.self, forKey: .running)
        self.mine = try? c.decodeIfPresent(Bool.self, forKey: .mine)
        self.paused = try? c.decodeIfPresent(Bool.self, forKey: .paused)
        self.version = try? c.decodeIfPresent(String.self, forKey: .version)
        self.older = try? c.decodeIfPresent(Bool.self, forKey: .older)
        self.models = try? c.decodeIfPresent(Int.self, forKey: .models)
        self.calls = (try? c.decode([GatewayCallDTO].self, forKey: .calls)) ?? []
    }

    enum CodingKeys: String, CodingKey {
        case url, lan, lanURLs, publicURL, publicKind, onNetwork, running, mine
        case paused, version, older, models, calls
    }
}

struct GatewayCallDTO: Codable, Sendable, Identifiable, Hashable {
    var id: Int64
    var time: String?
    var agent: String?
    var model: String?
    var provider: String?
    var status: Int?
    var ms: Int64?
    var error: String?
    var kind: String?
    var tokens: Int?
    var out: Int?
    var callerKeyName: String?

    var isError: Bool {
        !(error ?? "").isEmpty || ((status ?? 0) >= 400)
    }

    enum CodingKeys: String, CodingKey {
        case id, time, agent, model, provider, status, ms, error, kind, tokens
        case out
        case callerKeyName
    }
}

struct GatewayCallDetailDTO: Codable, Sendable {
    var requestBody: String?
    var responseBody: String?
    var requestTruncated: Bool?
    var responseTruncated: Bool?
}

/// `GET /api/account-groups` 的账户组：账号集合，供 Key 的 accounts 以 "@id" 引用。
struct GatewayAccountGroupDTO: Codable, Sendable, Identifiable, Hashable {
    var id: String
    var name: String
    var accounts: [String]

    var displayName: String { name.isEmpty ? id : name }
}

/// `GET /api/caller-keys/models`：网关可提供的模型与账号/分组。
struct GatewayModelsResponseDTO: Codable, Sendable {
    var models: [GatewayModelDTO]?
    var accounts: [GatewayModelDTO]?
    var providers: [GatewayModelDTO]?
    var groups: [GatewayModelDTO]?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.models = (try? c.decode([GatewayModelDTO].self, forKey: .models)) ?? []
        self.accounts = (try? c.decode([GatewayModelDTO].self, forKey: .accounts)) ?? []
        self.providers = (try? c.decode([GatewayModelDTO].self, forKey: .providers)) ?? []
        self.groups = (try? c.decode([GatewayModelDTO].self, forKey: .groups)) ?? []
    }

    enum CodingKeys: String, CodingKey { case models, accounts, providers, groups }
}

struct GatewayModelDTO: Codable, Sendable, Identifiable, Hashable {
    var id: String
    var name: String?
    var provider: String?
    var providerName: String?
    var group: Bool?
    var decides: Bool?
    var account: Bool?
    var key: Bool?
    var plan: String?

    var displayName: String { (name?.isEmpty == false ? name! : id) }
}

/// `GET /api/caller-keys/account-windows`：订阅账号的配额窗口，供 Key 限额跟随重置。
struct GatewayAccountWindowsResponseDTO: Codable, Sendable {
    var windows: [GatewayAccountWindowDTO]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.windows = (try? c.decode([GatewayAccountWindowDTO].self, forKey: .windows)) ?? []
    }

    enum CodingKeys: String, CodingKey { case windows }
}

struct GatewayAccountWindowDTO: Codable, Sendable, Identifiable, Hashable {
    var account: String
    var window: String
    var provider: String?
    var user: String?
    var alias: String?
    var start: String?
    var reset: String?

    var id: String { "\(account)|\(window)" }

    var displayLabel: String {
        let who = (alias?.isEmpty == false ? alias! : (user?.isEmpty == false ? user! : account))
        let head = (provider?.isEmpty == false) ? "\(provider!) · \(who)" : who
        return "\(head) (\(window))"
    }
}
