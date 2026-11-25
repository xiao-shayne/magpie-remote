import Foundation

/// 整体用量统计摘要
struct UsageDTO: Codable, Sendable {
    var period: String?
    var since: String?
    var calls: Int?
    var errors: Int?
    var retried: Int?
    var canceled: Int?
    var input: Int?
    var output: Int?
    var cache_read: Int?
    var cache_write: Int?
    var reasoning: Int?
    var cost: Double?
    var unpriced: Int?
    var agents: [UsageGroupDTO]?
    var models: [UsageGroupDTO]?
    var accounts: [UsageGroupDTO]?
    var callerKeys: [UsageGroupDTO]?
    var path: String?

    var totalTokens: Int {
        (input ?? 0) + (output ?? 0) + (cache_read ?? 0)
    }

    var formattedCost: String {
        guard let cost else { return "$0.00" }
        return String(format: "$%.2f", cost)
    }

    var formattedCalls: String {
        guard let calls else { return "0" }
        return NumberFormatter.localizedString(from: NSNumber(value: calls), number: .decimal)
    }

    static func formatTokens(_ count: Int) -> String {
        if count >= 1_000_000_000 {
            return String(format: "%.2f B", Double(count) / 1_000_000_000.0)
        } else if count >= 1_000_000 {
            return String(format: "%.2f M", Double(count) / 1_000_000.0)
        } else if count >= 1_000 {
            return String(format: "%.1f K", Double(count) / 1_000.0)
        }
        return "\(count)"
    }
}

/// `GET /api/usage/traffic`：网关累计收发字节与进行中的请求数。
struct UsageTrafficDTO: Codable, Sendable {
    var up: Int64?
    var down: Int64?
    var requests: Int?
}

/// `POST /api/usage/requests/export` 的返回：服务器 Downloads 里的 CSV 路径。
struct UsageExportResultDTO: Codable, Sendable {
    var path: String?
    var rows: Int?
}

/// 配额项详情
struct QuotaItemDTO: Codable, Sendable, Identifiable, Hashable {
    var provider: String
    var name: String
    var user: String?
    var icon: String?
    var balance: String?
    var readError: String?
    var windows: [QuotaWindowDTO]?

    /// 同一 Provider 可能有多个账号，账号名必须参与标识，否则 ForEach 会收到重复 ID。
    var id: String { "\(provider)-\(name)-\(user ?? "")" }

    struct QuotaWindowDTO: Codable, Sendable, Identifiable, Hashable {
        var name: String
        var used: Double?
        var remaining: Double?
        var resetsAt: String?
        var limit: Double?
        var unit: String?

        var id: String { name }

        var percentUsed: Double {
            guard let used else { return 0.0 }
            if used <= 1.0 {
                return used * 100.0
            }
            return min(used, 100.0)
        }
    }
}

// MARK: - Overview 分组
/// `/api/usage` 的 agents / models / accounts / callerKeys 行。
/// upstream `usage.Rates`：2% 步长对数直方图，用于计算中位输出速度（`Totals.Speed`）。
struct UsageRatesDTO: Codable, Sendable, Hashable {
    var s: [String: Int]?
    var f: [String: Int]?

    /// 对齐 upstream `speedHist.median()`（`histStep = 1.02`, `histZero = 400`）。
    static func median(of hist: [String: Int]?) -> Double? {
        guard let hist, !hist.isEmpty else { return nil }
        let bins = hist.compactMap { (k, v) -> (bin: Int, count: Int)? in
            guard let b = Int(k), v > 0 else { return nil }
            return (b, v)
        }.sorted { $0.bin < $1.bin }
        let total = bins.reduce(0) { $0 + $1.count }
        guard total > 0 else { return nil }
        let lo = (total - 1) / 2
        let hi = total / 2
        let histLog = log(1.02)
        var seen = 0
        var sum = 0.0
        var got = 0
        for item in bins {
            let next = seen + item.count
            let val = exp((Double(item.bin) - 400.0 + 0.5) * histLog)
            if lo >= seen && lo < next {
                sum += val
                got += 1
            }
            if hi >= seen && hi < next {
                sum += val
                got += 1
            }
            seen = next
        }
        return got > 0 ? sum / Double(got) : nil
    }
}

struct UsageGroupDTO: Codable, Sendable, Identifiable {
    var rawID: String?
    var name: String?
    var sub: String?
    var icon: String?
    var model: String?
    var provider: String?
    var account: String?
    var callerKeyId: String?
    var calls: Int?
    var input: Int?
    var output: Int?
    var cacheRead: Int?
    var cacheWrite: Int?
    var cost: Double?
    var unpriced: Int?
    var tokens: Int?
    var tps: Double?
    var decodeMs: Int64?
    var decodeOut: Int?
    var decodeN: Int?
    var rates: UsageRatesDTO?
    var last: String?

    var id: String {
        [rawID, name, model, account, callerKeyId, provider]
            .compactMap { $0 }
            .joined(separator: "|")
    }

    var totalTokens: Int {
        tokens ?? ((input ?? 0) + (output ?? 0) + (cacheRead ?? 0) + (cacheWrite ?? 0))
    }

    /// 对齐 upstream `usage.Totals.Speed()`：优先使用单条精确值或 2% 直方图中位速度。
    var effectiveTPS: Double? {
        if let tps, tps > 0 { return tps }
        if decodeN == 1, let ms = decodeMs, ms > 0, let out = decodeOut, out > 0 {
            return Double(out) / (Double(ms) / 1000.0)
        }
        if let med = UsageRatesDTO.median(of: rates?.s), med > 0 {
            return med
        }
        if let ms = decodeMs, ms > 0, let out = decodeOut, out > 0 {
            return Double(out) / (Double(ms) / 1000.0)
        }
        return nil
    }

    var displayName: String {
        if let name, !name.isEmpty { return name }
        if let model, !model.isEmpty { return model }
        if let account, !account.isEmpty { return account }
        return rawID ?? "—"
    }

    var formattedCost: String {
        guard let cost else { return "—" }
        return cost < 0.01 ? String(format: "$%.4f", cost) : String(format: "$%.2f", cost)
    }

    enum CodingKeys: String, CodingKey {
        case rawID = "id"
        case name, sub, icon, model, provider, account, callerKeyId
        case calls, input, output
        case cacheRead = "cache_read"
        case cacheWrite = "cache_write"
        case cost, unpriced, tokens, tps, rates, last
        case decodeMs = "decode_ms"
        case decodeOut = "decode_out"
        case decodeN = "decode_n"
    }
}

// MARK: - Requests 账本
struct UsageModelSpeedDTO: Codable, Sendable, Identifiable, Hashable {
    var model: String
    var name: String?
    var requests: Int?
    var tps: Double?
    var tpsN: Int?
    var ttftMs: Int64?

    var id: String { model }
    var displayName: String { (name?.isEmpty == false) ? name! : model }

    enum CodingKeys: String, CodingKey {
        case model, name, requests, tps
        case tpsN = "tps_n"
        case ttftMs = "ttft_ms"
    }
}

struct UsageProviderSpeedDTO: Codable, Sendable, Identifiable, Hashable {
    var model: String
    var name: String?
    var provider: String
    var providerName: String?
    var icon: String?
    var requests: Int?
    var tps: Double?
    var tpsN: Int?
    var ttftMs: Int64?
    var tries: Int?
    var failed: Int?
    var swapped: Int?

    var id: String { "\(model)|\(provider)" }
    var displayName: String { (name?.isEmpty == false) ? name! : model }
    var displayProvider: String { (providerName?.isEmpty == false) ? providerName! : provider }

    enum CodingKeys: String, CodingKey {
        case model, name, provider
        case providerName = "provider_name"
        case icon, requests, tps
        case tpsN = "tps_n"
        case ttftMs = "ttft_ms"
        case tries, failed, swapped
    }
}

struct UsageLedgerDTO: Codable, Sendable {
    var rows: [UsageLedgerRowDTO]?
    var total: Int?
    var offset: Int?
    var bucket: String?
    var day: String?
    var period: String?
    var calls: Int?
    var input: Int?
    var output: Int?
    var cacheRead: Int?
    var cacheWrite: Int?
    var cost: Double?
    var unpriced: Int?
    var agents: [UsageNamedDTO]?
    var providers: [UsageNamedDTO]?
    var accounts: [UsageAccountDTO]?
    var callerKeys: [UsageGroupDTO]?
    var speeds: [UsageModelSpeedDTO]?
    var providerSpeeds: [UsageProviderSpeedDTO]?

    enum CodingKeys: String, CodingKey {
        case rows, total, offset, bucket, day, period
        case calls, input, output
        case cacheRead = "cache_read"
        case cacheWrite = "cache_write"
        case cost, unpriced, agents, providers, accounts, callerKeys
        case speeds
        case providerSpeeds = "provider_speeds"
    }
}

struct UsageLedgerRowDTO: Codable, Sendable, Identifiable {
    var routeId: Int64?
    var time: String?
    var agent: String?
    var agentName: String?
    var icon: String?
    var provider: String?
    var providerName: String?
    var model: String?
    var requested: String?
    /// 实际发往上游厂商的模型 ID（upstream `usage.Record.Wire`）。
    var wire: String?
    var session: String?
    var input: Int?
    var output: Int?
    var cacheRead: Int?
    var cacheWrite: Int?
    var cost: Double?
    var priced: Bool?
    var status: Int?
    var error: String?
    var millis: Int64?
    var ttft: Int64?
    var source: String?
    var callerKeyId: String?
    var callerKeyLabel: String?
    var access: String?
    var canceled: Bool?

    var id: String {
        "\(routeId ?? 0)-\(time ?? "")-\(model ?? "")-\(input ?? 0)"
    }

    var isError: Bool {
        (!(error ?? "").isEmpty && canceled != true)
            || ((status ?? 0) >= 400 && canceled != true)
    }

    var totalTokens: Int {
        (input ?? 0) + (output ?? 0) + (cacheRead ?? 0) + (cacheWrite ?? 0)
    }

    var displayAgent: String { agentName ?? agent ?? "—" }

    var displayProvider: String { providerName ?? provider ?? "—" }

    var formattedCost: String {
        guard let cost else { return "—" }
        return cost < 0.01 ? String(format: "$%.4f", cost) : String(format: "$%.2f", cost)
    }

    enum CodingKeys: String, CodingKey {
        case routeId = "route_id"
        case time = "t"
        case agent, agentName, icon, provider, providerName, model
        case requested = "req"
        case wire
        case session
        case input = "in"
        case output = "out"
        case cacheRead = "cache_read"
        case cacheWrite = "cache_write"
        case cost, priced, status
        case error = "err"
        case millis = "ms"
        case ttft = "ttft_ms"
        case source
        case callerKeyId, callerKeyLabel, access, canceled
    }
}

/// `POST /api/warm-all` 的返回：每个账号的一键预热结果。
struct WarmAllResponseDTO: Codable, Sendable {
    var results: [WarmAllResultDTO]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.results = (try? c.decode([WarmAllResultDTO].self, forKey: .results)) ?? []
    }

    enum CodingKeys: String, CodingKey { case results }
}

struct WarmAllResultDTO: Codable, Sendable, Identifiable, Hashable {
    var user: String
    var skip: String?
    var error: String?

    var id: String { user }

    var isWarmed: Bool { (skip ?? "").isEmpty && (error ?? "").isEmpty }
}

struct UsageNamedDTO: Codable, Sendable, Identifiable {
    var id: String
    var name: String?
    var icon: String?

    var displayName: String { (name?.isEmpty == false ? name! : id) }
}

struct UsageAccountDTO: Codable, Sendable, Identifiable {
    var id: String
    var name: String?
    var providers: [String]?

    var displayName: String { (name?.isEmpty == false ? name! : id) }
}

// MARK: - Heatmap
struct UsageHeatmapDTO: Codable, Sendable {
    var from: String?
    var to: String?
    var days: [UsageHeatDayDTO]?

    enum CodingKeys: String, CodingKey { case from, to, days }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.from = try? c.decodeIfPresent(String.self, forKey: .from)
        self.to = try? c.decodeIfPresent(String.self, forKey: .to)
        self.days = (try? c.decode([UsageHeatDayDTO].self, forKey: .days)) ?? []
    }
}

struct UsageHeatDayDTO: Codable, Sendable, Identifiable {
    var date: String
    var calls: Int?
    var tokens: Int?
    var cost: Double?
    var unpriced: Int?

    var id: String { date }
}

// MARK: - Context
struct UsageContextDTO: Codable, Sendable {
    var days: Int?
    var agents: [UsageContextAgentDTO]?

    enum CodingKeys: String, CodingKey { case days, agents }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.days = try? c.decodeIfPresent(Int.self, forKey: .days)
        self.agents = (try? c.decode([UsageContextAgentDTO].self, forKey: .agents)) ?? []
    }
}

struct UsageContextAgentDTO: Codable, Sendable, Identifiable {
    var agent: String
    var requests: Int?
    var sessions: Int?
    var errors: Int?
    var calls: Int?
    var median: Int?
    var p90: Int?
    var baseline: Int?
    var window: Int?
    var cache: Double?
    var growth: Int?
    var peakFill: Double?
    var compacts: Int?
    var score: Int?
    var models: [String]?
    var tags: [UsageContextTagDTO]?
    var latestId: Int64?

    var id: String { agent }

    enum CodingKeys: String, CodingKey {
        case agent, requests, sessions, errors, calls, median, p90, baseline, window
        case cache, growth, peakFill, compacts, score, models, tags, latestId
    }
}

struct UsageContextTagDTO: Codable, Sendable, Identifiable, Hashable {
    var key: String
    var tone: String?
    var value: Double?

    var id: String { key + (tone ?? "") }
}


