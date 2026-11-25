import Foundation
import SwiftUI
import Observation

// MARK: - 网关路由模型 (与 Go 后端 traceJSON / routeJSON / gateway.Route 1:1 对齐)

/// `GET /api/gateway/history` 历史响应
struct GatewayHistoryDTO: Decodable, Sendable {
    var days: [String]?
    var routes: [GatewayRouteDTO]?
    var cut: Bool?
    var tallies: GatewayTalliesDTO?

    enum CodingKeys: String, CodingKey { case days, routes, cut, tallies }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.days = try? c.decodeIfPresent([String].self, forKey: .days)
        self.routes = try? c.decodeIfPresent([GatewayRouteDTO].self, forKey: .routes)
        self.cut = try? c.decodeIfPresent(Bool.self, forKey: .cut)
        self.tallies = try? c.decodeIfPresent(GatewayTalliesDTO.self, forKey: .tallies)
    }
}

struct GatewayTalliesDTO: Codable, Sendable, Equatable {
    var requests: Int?
    var rerouted: Int?
    var errors: Int?
    var tokens: Int?
}

/// `GET /api/gateway/trace` 实时长轮询响应
struct GatewayTraceDTO: Decodable, Sendable {
    var routes: [GatewayRouteDTO]?
    var mine: Bool?
    var now: String?
    var seq: Int64?
    var ids: [Int64]?
    var totals: GatewayTalliesDTO?

    enum CodingKeys: String, CodingKey { case routes, mine, now, seq, ids, totals }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.routes = (try? c.decodeIfPresent([GatewayRouteDTO].self, forKey: .routes)) ?? []
        self.mine = try? c.decodeIfPresent(Bool.self, forKey: .mine)
        self.now = try? c.decodeIfPresent(String.self, forKey: .now)
        self.seq = try? c.decodeIfPresent(Int64.self, forKey: .seq)
        self.ids = try? c.decodeIfPresent([Int64].self, forKey: .ids)
        self.totals = try? c.decodeIfPresent(GatewayTalliesDTO.self, forKey: .totals)
    }
}

/// 路由组引用元数据
struct GatewayGroupRefDTO: Codable, Sendable, Hashable {
    var id: String
    var ref: String?
    var name: String?
    var routing: String?
    var affinity: String?
    var auto: Bool?
    var members: [String]?
    var via: [String]?

    var displayName: String {
        if let name, !name.isEmpty { return name }
        if let ref, !ref.isEmpty { return ref }
        return id
    }
}

/// Token 及缓存使用明细
struct GatewayUsageItemDTO: Codable, Sendable, Hashable {
    var provider: String?
    var input: Int?
    var output: Int?
    var cacheRead: Int?
    var cacheWrite: Int?
    var cacheUnknown: Bool?

    enum CodingKeys: String, CodingKey {
        case provider
        case input
        case output
        case cacheRead = "cache_read"
        case cacheWrite = "cache_write"
        case cacheUnknown = "cache_unknown"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.provider = try? c.decodeIfPresent(String.self, forKey: .provider)
        self.input = try? c.decodeIfPresent(Int.self, forKey: .input)
        self.output = try? c.decodeIfPresent(Int.self, forKey: .output)
        self.cacheRead = try? c.decodeIfPresent(Int.self, forKey: .cacheRead)
        self.cacheWrite = try? c.decodeIfPresent(Int.self, forKey: .cacheWrite)
        self.cacheUnknown = try? c.decodeIfPresent(Bool.self, forKey: .cacheUnknown)
    }
}

/// 单次路由决策的完整实体（原版 routeJSON / gateway.Route）
struct GatewayRouteDTO: Decodable, Sendable, Identifiable, Hashable {
    var id: Int64
    var seq: Int64?
    var time: String?
    var agent: String?
    var model: String?
    var provider: String?
    var group: GatewayGroupRefDTO?
    var order: [GatewayWeighedDTO]?
    var done: Bool?
    var status: Int?
    var error: String?
    var canceled: Bool?
    var millis: Int64?
    var ttft: Int64?
    var tokens: Int?
    var out: Int?
    var cost: Double?
    var priced: Bool?
    var kind: String?
    var callerKeyName: String?
    var session: String?
    var sessionTitle: String?
    var parentSession: String?
    var moved: GatewayMoveDTO?
    var served: String?
    var firstReasoning: Int64?
    var reasoningHidden: Bool?
    var tries: [GatewayTryDTO]?
    var usage: [GatewayUsageItemDTO]?

    /// 解码时解析一次的时间，供排序、分组与渲染复用，避免反复创建 ISO8601 formatter。
    private(set) var parsedDate: Date?

    enum CodingKeys: String, CodingKey {
        case id, seq, time, agent, model, provider, group, order, done, status
        case error, canceled, millis, ttft, tokens, out, cost, priced, kind
        case callerKeyName = "caller_key_name"
        case session
        case sessionTitle
        case parentSession = "parent_session"
        case moved, served, firstReasoning, reasoningHidden, tries, usage
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? c.decode(Int64.self, forKey: .id)) ?? 0
        self.seq = try? c.decodeIfPresent(Int64.self, forKey: .seq)
        self.time = try? c.decodeIfPresent(String.self, forKey: .time)
        self.parsedDate = Self.parseISO8601(self.time)
        self.agent = try? c.decodeIfPresent(String.self, forKey: .agent)
        self.model = try? c.decodeIfPresent(String.self, forKey: .model)
        self.provider = try? c.decodeIfPresent(String.self, forKey: .provider)
        self.group = try? c.decodeIfPresent(GatewayGroupRefDTO.self, forKey: .group)
        self.order = try? c.decodeIfPresent([GatewayWeighedDTO].self, forKey: .order)
        self.done = try? c.decodeIfPresent(Bool.self, forKey: .done)
        self.status = try? c.decodeIfPresent(Int.self, forKey: .status)
        self.error = try? c.decodeIfPresent(String.self, forKey: .error)
        self.canceled = try? c.decodeIfPresent(Bool.self, forKey: .canceled)
        self.millis = try? c.decodeIfPresent(Int64.self, forKey: .millis)
        self.ttft = try? c.decodeIfPresent(Int64.self, forKey: .ttft)
        self.tokens = try? c.decodeIfPresent(Int.self, forKey: .tokens)
        self.out = try? c.decodeIfPresent(Int.self, forKey: .out)
        self.cost = try? c.decodeIfPresent(Double.self, forKey: .cost)
        self.priced = try? c.decodeIfPresent(Bool.self, forKey: .priced)
        self.kind = try? c.decodeIfPresent(String.self, forKey: .kind)
        self.callerKeyName = try? c.decodeIfPresent(String.self, forKey: .callerKeyName)
        self.session = try? c.decodeIfPresent(String.self, forKey: .session)
        self.sessionTitle = try? c.decodeIfPresent(String.self, forKey: .sessionTitle)
        self.parentSession = try? c.decodeIfPresent(String.self, forKey: .parentSession)
        self.moved = try? c.decodeIfPresent(GatewayMoveDTO.self, forKey: .moved)
        self.served = try? c.decodeIfPresent(String.self, forKey: .served)
        self.firstReasoning = try? c.decodeIfPresent(Int64.self, forKey: .firstReasoning)
        self.reasoningHidden = try? c.decodeIfPresent(Bool.self, forKey: .reasoningHidden)
        self.tries = try? c.decodeIfPresent([GatewayTryDTO].self, forKey: .tries)
        self.usage = try? c.decodeIfPresent([GatewayUsageItemDTO].self, forKey: .usage)
    }

    /// 实际发往上游厂商的模型 ID（当与 `model` 不同时展示，upstream `Try.Wire`）。
    var effectiveWireModel: String? {
        guard let wire = tries?.last(where: { !($0.wire ?? "").isEmpty })?.wire,
              !wire.isEmpty, wire != model else { return nil }
        return wire
    }

    var isError: Bool { !(error ?? "").isEmpty || ((status ?? 0) >= 400) }
    var isPending: Bool { done != true }
    var isSuccess: Bool { !isPending && !isError && canceled != true }

    var date: Date? { parsedDate }

    private static func parseISO8601(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: raw) { return date }

        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: raw)
    }

    /// 有效会话标识（合并 parentSession）
    var effectiveSessionID: String {
        if let parentSession, !parentSession.isEmpty { return parentSession }
        if let session, !session.isEmpty { return session }
        return ""
    }

    /// 计算总输入 Token 与缓存命中比例
    var cacheStats: (read: Int, write: Int, rate: Double?) {
        guard let usage, !usage.isEmpty else { return (0, 0, nil) }
        var totalRead = 0
        var totalWrite = 0
        var totalInput = 0
        for item in usage {
            let r = item.cacheRead ?? 0
            let w = item.cacheWrite ?? 0
            let inp = item.input ?? 0
            totalRead += r
            totalWrite += w
            totalInput += inp
        }
        let total = totalRead + totalInput
        let rate = total > 0 ? (Double(totalRead) / Double(total)) : nil
        return (totalRead, totalWrite, rate)
    }

    /// 输出速率（tokens/s）
    var outputSpeed: Double? {
        guard let outTokens = out, outTokens > 0, let ms = millis, ms > 0 else { return nil }
        return Double(outTokens) / (Double(ms) / 1000.0)
    }
}

struct GatewayMoveDTO: Codable, Sendable, Hashable {
    var to: String?
    var why: String?
}

/// 单次尝试上游的详细记录（`gateway.Try`）。
struct GatewayTryDTO: Codable, Sendable, Hashable {
    var id: String?
    var provider: String?
    var model: String?
    var wire: String?
    var served: String?
    var swapped: Bool?
    var routed: Bool?
    var upstream: String?
    var status: Int?
    var error: String?
    var millis: Int64?
    var ttft: Int64?
    var firstReasoning: Int64?
    var reasoningHidden: Bool?

    enum CodingKeys: String, CodingKey {
        case id, provider, model, wire, served, swapped, routed, upstream, status, error
        case millis = "ms"
        case ttft, firstReasoning, reasoningHidden
    }
}

struct GatewaySeatPriceDTO: Codable, Sendable, Hashable {
    var input: Double?
    var output: Double?
    var cacheRead: Double?
    var peak: Bool?
}

/// 决策权衡链路中的每个候选账号/席位
struct GatewayWeighedDTO: Codable, Sendable, Identifiable, Hashable {
    var id: String
    var provider: String?
    var name: String?
    var icon: String?
    var who: String?
    var kind: String?
    var model: String?
    var fixed: String?
    var fast: Bool?
    var ultra: Bool?
    var fallback: Bool?
    /// 网关的休息记录：可能是 true，也可能是一个带 why / status / until 的对象。
    var rest: JSONValue?
    var balance: String?
    var routing: String?
    var why: String?
    var used: Double?
    var known: Bool?
    var reserve: Bool?
    var aside: Bool?
    var agent: String?
    var plan: String?
    var amount: Double?
    var limit: Double?
    var unit: String?
    var due: String?
    var renews: [String]?
    var soon: [String]?
    var lapse: String?
    var rank: Int?
    var shared: Bool?
    var context: Int?
    var lateTtft: Double?
    var lateTps: Double?
    var credits: Bool?
    var creditsLast: Bool?
    var price: GatewaySeatPriceDTO?

    enum CodingKeys: String, CodingKey {
        case id, provider, name, icon, who, kind, model, fixed, fast, ultra, fallback
        case rest, balance, routing, why, used, known, reserve, aside, agent
        case plan, amount, limit, unit, due, renews, soon, lapse, rank, shared
        case context, lateTtft, lateTps, credits, creditsLast, price
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? c.decode(String.self, forKey: .id)) ?? ""
        self.provider = try? c.decodeIfPresent(String.self, forKey: .provider)
        self.name = try? c.decodeIfPresent(String.self, forKey: .name)
        self.icon = try? c.decodeIfPresent(String.self, forKey: .icon)
        self.who = try? c.decodeIfPresent(String.self, forKey: .who)
        self.kind = try? c.decodeIfPresent(String.self, forKey: .kind)
        self.model = try? c.decodeIfPresent(String.self, forKey: .model)
        self.fixed = try? c.decodeIfPresent(String.self, forKey: .fixed)
        self.fast = try? c.decodeIfPresent(Bool.self, forKey: .fast)
        self.ultra = try? c.decodeIfPresent(Bool.self, forKey: .ultra)
        self.fallback = try? c.decodeIfPresent(Bool.self, forKey: .fallback)
        self.rest = try? c.decodeIfPresent(JSONValue.self, forKey: .rest)
        self.balance = try? c.decodeIfPresent(String.self, forKey: .balance)
        self.routing = try? c.decodeIfPresent(String.self, forKey: .routing)
        self.why = try? c.decodeIfPresent(String.self, forKey: .why)
        self.used = try? c.decodeIfPresent(Double.self, forKey: .used)
        self.known = try? c.decodeIfPresent(Bool.self, forKey: .known)
        self.reserve = try? c.decodeIfPresent(Bool.self, forKey: .reserve)
        self.aside = try? c.decodeIfPresent(Bool.self, forKey: .aside)
        self.agent = try? c.decodeIfPresent(String.self, forKey: .agent)
        self.plan = try? c.decodeIfPresent(String.self, forKey: .plan)
        self.amount = try? c.decodeIfPresent(Double.self, forKey: .amount)
        self.limit = try? c.decodeIfPresent(Double.self, forKey: .limit)
        self.unit = try? c.decodeIfPresent(String.self, forKey: .unit)
        self.due = try? c.decodeIfPresent(String.self, forKey: .due)
        self.renews = try? c.decodeIfPresent([String].self, forKey: .renews)
        self.soon = try? c.decodeIfPresent([String].self, forKey: .soon)
        self.lapse = try? c.decodeIfPresent(String.self, forKey: .lapse)
        self.rank = try? c.decodeIfPresent(Int.self, forKey: .rank)
        self.shared = try? c.decodeIfPresent(Bool.self, forKey: .shared)
        self.context = try? c.decodeIfPresent(Int.self, forKey: .context)
        self.lateTtft = try? c.decodeIfPresent(Double.self, forKey: .lateTtft)
        self.lateTps = try? c.decodeIfPresent(Double.self, forKey: .lateTps)
        self.credits = try? c.decodeIfPresent(Bool.self, forKey: .credits)
        self.creditsLast = try? c.decodeIfPresent(Bool.self, forKey: .creditsLast)
        self.price = try? c.decodeIfPresent(GatewaySeatPriceDTO.self, forKey: .price)
    }

    var usedPercent: Int? {
        guard let used else { return nil }
        return Int((used * 100).rounded())
    }

    var isResting: Bool {
        guard let rest else { return false }
        switch rest {
        case .null: return false
        case .bool(let value): return value
        default: return true
        }
    }

    var restReason: String? {
        if let why = rest?.string("why"), !why.isEmpty {
            switch why {
            case "quota": return String(localized: "额度用尽")
            case "error", "failed": return String(localized: "调用失败")
            default: return why
            }
        }
        return nil
    }

    var displayLabel: String {
        if let who, !who.isEmpty { return who }
        if let name, !name.isEmpty { return name }
        return id
    }
}

// MARK: - 聚合视图模型（By Session & By Key）

/// 按会话分组
struct SessionRouteGroup: Identifiable, Sendable {
    var id: String
    var title: String
    var agent: String
    var routes: [GatewayRouteDTO]
    var totalCost: Double
    var totalTokens: Int
    var hasPending: Bool
    var hasError: Bool
    var latestDate: Date?

    init(sessionID: String, routes: [GatewayRouteDTO]) {
        self.id = sessionID
        self.routes = routes.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        let first = self.routes.first
        self.title = first?.sessionTitle ?? (sessionID.isEmpty ? String(localized: "无会话 ID") : sessionID)
        self.agent = first?.agent ?? "agent"
        self.totalCost = routes.compactMap(\.cost).reduce(0, +)
        self.totalTokens = routes.compactMap(\.tokens).reduce(0, +)
        self.hasPending = routes.contains(where: \.isPending)
        self.hasError = routes.contains(where: \.isError)
        self.latestDate = first?.date
    }
}

/// 按网关密钥分组
struct KeyRouteGroup: Identifiable, Sendable {
    var id: String
    var routes: [GatewayRouteDTO]
    var totalCost: Double
    var totalTokens: Int
    var hasPending: Bool
    var hasError: Bool
    var latestDate: Date?

    init(keyName: String, routes: [GatewayRouteDTO]) {
        self.id = keyName.isEmpty ? String(localized: "无网关密钥 (本地调用)") : keyName
        self.routes = routes.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        self.totalCost = routes.compactMap(\.cost).reduce(0, +)
        self.totalTokens = routes.compactMap(\.tokens).reduce(0, +)
        self.hasPending = routes.contains(where: \.isPending)
        self.hasError = routes.contains(where: \.isError)
        self.latestDate = self.routes.first?.date
    }
}

/// 路由查看模式
enum RoutingViewMode: String, CaseIterable, Identifiable {
    case byRequest = "request"
    case bySession = "session"
    case byKey = "key"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .byRequest: return String(localized: "按请求")
        case .bySession: return String(localized: "按会话")
        case .byKey: return String(localized: "按密钥")
        }
    }

    var icon: String {
        switch self {
        case .byRequest: return "list.bullet"
        case .bySession: return "bubble.left.and.bubble.right"
        case .byKey: return "key.horizontal"
        }
    }
}

/// 路由状态快捷筛选
enum RouteFilterStatus: String, CaseIterable, Identifiable {
    case all
    case errors
    case rerouted
    case pending

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return String(localized: "全部")
        case .errors: return String(localized: "失败报错")
        case .rerouted: return String(localized: "故障转移")
        case .pending: return String(localized: "调度中")
        }
    }

    var icon: String {
        switch self {
        case .all: return "line.3.horizontal.decrease.circle"
        case .errors: return "xmark.octagon.fill"
        case .rerouted: return "arrow.triangle.swap"
        case .pending: return "waveform.path"
        }
    }
}

// MARK: - 路由控制中心 ViewModel（真正支持 1:1 毫秒级长轮询与历史回溯）
@Observable
@MainActor
final class RoutingViewModel {
    /// 完整路由列表（实时流或当前选定日期的历史记录，时间倒序）
    var routes: [GatewayRouteDTO] = []

    /// 当前选中的日期（nil 表示 Live 实时流；非空如 "2026-11-15" 表示查看历史归档）
    var selectedDay: String? = nil

    /// 可查看的历史日期列表（从 /api/gateway/history 获取）
    var availableDays: [String] = []

    /// 当前分组模式
    var viewMode: RoutingViewMode = .byRequest

    /// 状态过滤条件
    var filterStatus: RouteFilterStatus = .all

    /// 实时是否正常服务
    var isLiveMine = true
    var isLoading = false
    var isLongPollingActive = false
    var errorMessage: String?
    var lastUpdated: Date?

    /// 网关对当前日期的总请求 / 改写 / 错误统计（原版 rt-stats）
    var totals: GatewayTalliesDTO?

    /// 内存路由池（按 ID 增量合并，最多保留 100 条）
    private var livePool: [Int64: GatewayRouteDTO] = [:]
    private var lastSeq: Int64 = 0

    /// 后台长轮询任务
    private var pollingTask: Task<Void, Never>?
    private var daysRefreshTask: Task<Void, Never>?

    /// 高频路由事件合并到最多 5Hz 刷新，避免每个事件都重建整页 SwiftUI 视图。
    private var pendingRouteList: [GatewayRouteDTO]?
    private var pendingTotals: GatewayTalliesDTO?
    private var publishTask: Task<Void, Never>?
    private var lastPublishAt: Date = .distantPast

    // MARK: - 实时长轮询核心引擎

    /// 启动真正的长轮询（Long-polling）监听
    func startRealtimeTrace(client: MagpieAPIClient) {
        stopPolling()
        cancelPendingPublish()
        selectedDay = nil
        totals = nil

        // 异步启动长轮询任务
        pollingTask = Task { [weak self] in
            guard let self else { return }
            await self.runLongPollingLoop(client: client)
        }

        // 异步定期拉取历史天数
        daysRefreshTask = Task { [weak self] in
            guard let self else { return }
            await self.loadAvailableDays(client: client)
        }
    }

    /// 长轮询主循环（对齐原版 JS poll 逻辑）
    private func runLongPollingLoop(client: MagpieAPIClient) async {
        isLongPollingActive = true
        var initial = true

        while !Task.isCancelled {
            do {
                // 首次请求 after=0 获取当前内存状态全集；后续带 &wait=1 挂起最多 25 秒
                let urlPath: String
                if initial {
                    urlPath = "/api/gateway/trace?after=0"
                } else {
                    urlPath = "/api/gateway/trace?after=\(lastSeq)&wait=1"
                }

                let trace: GatewayTraceDTO = try await client.send(
                    .get(urlPath),
                    as: GatewayTraceDTO.self
                )

                if Task.isCancelled { break }

                isLiveMine = trace.mine ?? true
                if let newTotals = trace.totals { pendingTotals = newTotals }
                if let newSeq = trace.seq {
                    if newSeq < lastSeq {
                        // 网关重置，清空内存池
                        livePool.removeAll()
                    }
                    lastSeq = newSeq
                }

                // 合并增量路由更新
                if let receivedRoutes = trace.routes {
                    for r in receivedRoutes {
                        livePool[r.id] = r
                    }
                }

                // 移除失效悬挂项
                if let keptIds = trace.ids {
                    let set = Set(keptIds)
                    for (id, r) in livePool where !r.isPending && !set.contains(id) {
                        livePool.removeValue(forKey: id)
                    }
                }

                // 内存保留最近 100 条记录
                let sortedList = livePool.values.sorted {
                    if let d1 = $0.date, let d2 = $1.date {
                        return d1 > d2
                    }
                    return $0.id > $1.id
                }
                if sortedList.count > 100 {
                    for stale in sortedList.suffix(from: 100) {
                        livePool.removeValue(forKey: stale.id)
                    }
                }

                // 仅在 Live 模式下更新展示；多个事件在 200ms 窗口内合并成一次 UI 更新。
                if selectedDay == nil {
                    let newRoutes = Array(sortedList.prefix(100))
                    if self.routes != newRoutes || (pendingTotals != nil && pendingTotals != totals) {
                        schedulePublish(newRoutes)
                    }
                }

                initial = false
            } catch {
                if Task.isCancelled { break }
                // 发生网络闪断，稍作退避重试
                try? await Task.sleep(for: .seconds(2))
            }
        }
        isLongPollingActive = false
    }

    /// 停止长轮询
    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
        daysRefreshTask?.cancel()
        daysRefreshTask = nil
        cancelPendingPublish()
        isLongPollingActive = false
    }

    private func schedulePublish(_ routes: [GatewayRouteDTO]) {
        pendingRouteList = routes
        guard publishTask == nil else { return }

        let wait = max(0, 0.2 - Date().timeIntervalSince(lastPublishAt))
        publishTask = Task { [weak self] in
            if wait > 0 {
                try? await Task.sleep(for: .seconds(wait))
            }
            guard let self, !Task.isCancelled else { return }
            self.publishPending()
        }
    }

    private func publishPending() {
        publishTask = nil
        guard let routes = pendingRouteList else { return }
        pendingRouteList = nil
        let newTotals = pendingTotals
        pendingTotals = nil

        var didChange = false
        if self.routes != routes {
            self.routes = routes
            didChange = true
        }
        if let newTotals, newTotals != totals {
            totals = newTotals
            didChange = true
        }
        if errorMessage != nil {
            errorMessage = nil
            didChange = true
        }
        if didChange {
            lastUpdated = Date()
        }
        lastPublishAt = Date()
    }

    private func cancelPendingPublish() {
        publishTask?.cancel()
        publishTask = nil
        pendingRouteList = nil
        pendingTotals = nil
    }

    // MARK: - 历史模式切换

    /// 切换查看历史某一天
    func selectDay(_ day: String?, client: MagpieAPIClient) async {
        let liveTotals = pendingTotals
        cancelPendingPublish()
        if day == nil {
            // 切回 Live 实时流
            selectedDay = nil
            let sortedList = livePool.values.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
            self.routes = Array(sortedList.prefix(100))
            if pollingTask == nil {
                startRealtimeTrace(client: client)
            }
            self.totals = liveTotals
            self.errorMessage = nil
            return
        }

        // 切换到特定历史日期
        selectedDay = day
        isLoading = true
        do {
            let history: GatewayHistoryDTO = try await client.send(
                .get("/api/gateway/history?day=\(day!)"),
                as: GatewayHistoryDTO.self
            )
            self.routes = (history.routes ?? []).sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
            self.totals = history.tallies
            self.lastUpdated = Date()
            self.errorMessage = nil
            if let fetchedDays = history.days, !fetchedDays.isEmpty {
                self.availableDays = fetchedDays
            }
        } catch {
            self.errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
    }

    /// 拉取可用的历史日期列表
    func loadAvailableDays(client: MagpieAPIClient) async {
        do {
            let history: GatewayHistoryDTO = try await client.send(
                .get("/api/gateway/history"),
                as: GatewayHistoryDTO.self
            )
            if let days = history.days {
                self.availableDays = days
            }
        } catch {}
    }

    /// 手动刷新
    func refresh(client: MagpieAPIClient) async {
        cancelPendingPublish()
        if let day = selectedDay {
            await selectDay(day, client: client)
        } else {
            // 实时模式下强制拉取一次 after=0
            do {
                let trace: GatewayTraceDTO = try await client.send(
                    .get("/api/gateway/trace?after=0"),
                    as: GatewayTraceDTO.self
                )
                if let receivedRoutes = trace.routes {
                    for r in receivedRoutes {
                        livePool[r.id] = r
                    }
                }
                if let newTotals = trace.totals { totals = newTotals }
                let sortedList = livePool.values.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
                self.routes = Array(sortedList.prefix(100))
                self.lastUpdated = Date()
                self.errorMessage = nil
            } catch {
                self.errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    // MARK: - 计算指标

    /// 正在进行中的活跃请求
    var pendingRoutes: [GatewayRouteDTO] {
        routes.filter { $0.isPending }
    }

    /// 发生重新路由/故障转移的次数
    var reroutedCount: Int {
        routes.filter { ($0.order?.count ?? 0) > 1 || $0.moved != nil }.count
    }

    /// 客户端报错数
    var errorCount: Int {
        routes.filter { $0.isError }.count
    }

    /// 成功请求数
    var successCount: Int {
        routes.filter { $0.isSuccess }.count
    }

    /// 累计花费估算
    var totalCost: Double {
        routes.compactMap(\.cost).reduce(0, +)
    }

    /// 平均耗时毫秒
    var averageLatency: Int64 {
        let completed = routes.filter { $0.millis != nil && $0.millis! > 0 }
        guard !completed.isEmpty else { return 0 }
        let sum = completed.compactMap(\.millis).reduce(0, +)
        return sum / Int64(completed.count)
    }

    /// 活跃的 Agent 列表（取前 4 个供流动舞台展示）
    var stageAgents: [String] {
        let list = routes.compactMap(\.agent).filter { !$0.isEmpty }
        var counts: [String: Int] = [:]
        for a in list { counts[a, default: 0] += 1 }
        let sorted = counts.sorted { $0.value > $1.value }.map(\.key)
        return Array(sorted.prefix(4))
    }

    /// 活跃的 Provider 列表（取前 4 个供流动舞台展示）
    var stageProviders: [String] {
        let list = routes.compactMap(\.provider).filter { !$0.isEmpty }
        var counts: [String: Int] = [:]
        for p in list { counts[p, default: 0] += 1 }
        let sorted = counts.sorted { $0.value > $1.value }.map(\.key)
        return Array(sorted.prefix(4))
    }

    /// 按会话分组列表
    var sessionGroups: [SessionRouteGroup] {
        let grouped = Dictionary(grouping: routes) { $0.effectiveSessionID }
        return grouped.map { sessionID, items in
            SessionRouteGroup(sessionID: sessionID, routes: items)
        }.sorted { ($0.latestDate ?? .distantPast) > ($1.latestDate ?? .distantPast) }
    }

    /// 按网关密钥分组列表
    var keyGroups: [KeyRouteGroup] {
        let grouped = Dictionary(grouping: routes) { $0.callerKeyName ?? "" }
        return grouped.map { keyName, items in
            KeyRouteGroup(keyName: keyName, routes: items)
        }.sorted { ($0.latestDate ?? .distantPast) > ($1.latestDate ?? .distantPast) }
    }
}

// MARK: - 格式化辅助
enum RoutingFormat {
    static func latency(_ millis: Int64?) -> String {
        guard let millis, millis > 0 else { return "—" }
        if millis >= 1000 {
            return String(format: "%.2fs", Double(millis) / 1000)
        }
        return "\(millis)ms"
    }

    static func tokens(_ count: Int?) -> String {
        guard let count, count > 0 else { return "—" }
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        }
        if count >= 1_000 {
            return String(format: "%.1fk", Double(count) / 1_000)
        }
        return "\(count)"
    }

    static func cost(_ value: Double?) -> String {
        guard let value else { return "—" }
        if value == 0 { return "$0" }
        if value < 0.001 { return String(format: "$%.5f", value) }
        if value < 0.01 { return String(format: "$%.4f", value) }
        return String(format: "$%.3f", value)
    }

    static func time(_ date: Date?) -> String {
        guard let date else { return "—" }
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: date)
    }

    static func dateShort(_ date: Date?) -> String {
        guard let date else { return "" }
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return f.string(from: date)
    }

    static func statusText(_ route: GatewayRouteDTO) -> String {
        if route.canceled == true { return String(localized: "已取消") }
        if let status = route.status, status >= 400 { return "\(status)" }
        if route.isPending { return String(localized: "进行中") }
        return String(localized: "成功")
    }

    static func strategyName(_ value: String?) -> String {
        switch value {
        case "smart": return String(localized: "智能 (Smart)")
        case "order": return String(localized: "按序 (Order)")
        case "rotate": return String(localized: "轮询 (Rotate)")
        case "usage": return String(localized: "少用优先 (Usage)")
        case "pace": return String(localized: "节奏优先 (Pace)")
        case "weight": return String(localized: "加权 (Weight)")
        case "fast", "fastest", "speed": return String(localized: "测速优先 (Fast)")
        default: return value ?? "—"
        }
    }

    /// 账号与名称脱敏掩码处理（用于一键 Hide accounts 隐私截图分享）
    static func maskString(_ text: String, isMasked: Bool) -> String {
        guard isMasked, !text.isEmpty else { return text }
        if text.contains("@") {
            // 邮箱格式脱敏：abc***@domain.com
            let parts = text.split(separator: "@", maxSplits: 1)
            if parts.count == 2 {
                let user = String(parts[0])
                let domain = String(parts[1])
                let prefix = user.prefix(2)
                return "\(prefix)•••@\(domain)"
            }
        }
        if text.count > 5 {
            let start = text.prefix(2)
            let end = text.suffix(2)
            return "\(start)•••\(end)"
        }
        return "••••••"
    }

    /// 1:1 对齐官方 Web 的动态决策自然语言解说（rt-cap）
    static func decisionCaption(for route: GatewayRouteDTO?) -> String {
        guard let route else {
            return String(localized: "网关调度引擎就绪，等待 Agent 发起请求…")
        }

        let agentName = route.agent ?? "Agent"
        let modelName = route.model ?? "Model"
        let groupName = route.group?.displayName

        if route.isPending {
            if let group = groupName {
                return String(localized: "\(agentName) 发起请求 \(modelName)，正通过「\(group)」路由组评估各候选席位…")
            }
            return String(localized: "\(agentName) 正在请求 \(modelName)，网关正在智能权衡最佳可用账户…")
        }

        if let moved = route.moved {
            let to = moved.to ?? String(localized: "备用账户")
            let why = moved.why ?? String(localized: "首选席位异常")
            return String(localized: "\(agentName) 请求 \(modelName)：首选席位遭遇「\(why)」，已自动重路由转交至 \(to) 完成应答。")
        }

        if (route.order?.count ?? 0) > 1 {
            let target = route.provider ?? String(localized: "备用席位")
            return String(localized: "\(agentName) 请求 \(modelName)：经历首轮故障转移，最终由 \(target) 成功接单，耗时 \(latency(route.millis))。")
        }

        if route.isError {
            let err = route.error ?? "HTTP \(route.status ?? 500)"
            return String(localized: "\(agentName) 请求 \(modelName) 失败：\(err)。没有候选席位能完成本次调用。")
        }

        if route.canceled == true {
            return String(localized: "\(agentName) 请求 \(modelName) 已由客户端主动取消。")
        }

        let prov = route.provider ?? "Provider"
        let ms = latency(route.millis)
        if let group = groupName {
            return String(localized: "\(agentName) 请求 \(modelName)，由「\(group)」命中 \(prov)，耗时 \(ms) 完成。")
        }
        return String(localized: "\(agentName) 请求 \(modelName)，由 \(prov) 成功应答，耗时 \(ms)。")
    }
}
