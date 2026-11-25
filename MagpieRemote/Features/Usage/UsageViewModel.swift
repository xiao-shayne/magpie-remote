import Foundation
import Observation

@Observable
@MainActor
final class UsageViewModel {
    enum UsageTab: String, CaseIterable, Identifiable {
        case overview
        case requests
        case sessions
        case context

        var id: String { rawValue }

        var title: String {
            switch self {
            case .overview: return String(localized: "总览")
            case .requests: return String(localized: "请求")
            case .sessions: return String(localized: "会话")
            case .context: return String(localized: "上下文")
            }
        }

        var icon: String {
            switch self {
            case .overview: return "square.grid.2x2.fill"
            case .requests: return "list.bullet.rectangle"
            case .sessions: return "bubble.left.and.bubble.right.fill"
            case .context: return "rectangle.split.3x1.fill"
            }
        }
    }

    var usage: UsageDTO?
    var quotas: [QuotaItemDTO] = []
    var heatmap: UsageHeatmapDTO?
    var ledger: UsageLedgerDTO?
    var sessions: [SessionDTO] = []
    var context: UsageContextDTO?
    var tune: TuneStateDTO?

    var period = "today"
    var tab: UsageTab = .overview
    var isLoading = false
    var isLedgerLoading = false
    var isHeatmapLoading = false
    var isContextLoading = false
    var isSessionsLoading = false
    var errorMessage: String?

    // 请求筛选
    var ledgerQuery = ""
    var ledgerFailedOnly = false
    var ledgerRetriedOnly = false
    var ledgerProvider = ""
    var ledgerAgent = ""
    var ledgerOffset = 0
    var ledgerTotal = 0
    var ledgerHasMore = false

    let pageSize = 50

    func load(client: MagpieAPIClient, resetLedger: Bool = false) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let usage: UsageDTO = try await client.send(
                .get("/api/usage", query: [
                    URLQueryItem(name: "period", value: period),
                    URLQueryItem(name: "tz", value: TimeZone.current.identifier)
                ]),
                as: UsageDTO.self,
                timeout: 60
            )
            self.usage = usage
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
        do {
            quotas = try await client.send(.get("/api/usage/quotas"), as: [QuotaItemDTO].self, timeout: 60)
        } catch {
            // 配额失败不覆盖主统计
        }
        if resetLedger {
            await loadLedger(client: client, reset: true)
        }
    }

    func loadLedger(client: MagpieAPIClient, reset: Bool) async {
        if reset {
            ledgerOffset = 0
            ledgerHasMore = false
        } else if !ledgerHasMore {
            return
        }
        isLedgerLoading = true
        defer { isLedgerLoading = false }
        do {
            var query = [
                URLQueryItem(name: "period", value: period),
                URLQueryItem(name: "offset", value: "\(ledgerOffset)"),
                URLQueryItem(name: "limit", value: "\(pageSize)"),
                URLQueryItem(name: "tz", value: TimeZone.current.identifier)
            ]
            let q = ledgerQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            if !q.isEmpty { query.append(URLQueryItem(name: "q", value: q)) }
            if ledgerFailedOnly { query.append(URLQueryItem(name: "failed", value: "1")) }
            if !ledgerProvider.isEmpty { query.append(URLQueryItem(name: "provider", value: ledgerProvider)) }
            if !ledgerAgent.isEmpty { query.append(URLQueryItem(name: "agent", value: ledgerAgent)) }

            let response: UsageLedgerDTO = try await client.send(
                .get("/api/usage/requests", query: query),
                as: UsageLedgerDTO.self,
                timeout: 60
            )
            let rows = response.rows ?? []
            if reset || ledger == nil {
                self.ledger = response
            } else if var existing = self.ledger {
                existing.rows = (existing.rows ?? []) + rows
                self.ledger = existing
            }
            ledgerOffset += rows.count
            ledgerTotal = response.total ?? ledgerTotal
            ledgerHasMore = rows.count >= pageSize && ledgerOffset < (response.total ?? 0)
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func loadHeatmap(client: MagpieAPIClient) async {
        isHeatmapLoading = true
        defer { isHeatmapLoading = false }
        do {
            var query: [URLQueryItem] = [
                URLQueryItem(name: "tz", value: TimeZone.current.identifier)
            ]
            let q = ledgerQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            if !q.isEmpty { query.append(URLQueryItem(name: "q", value: q)) }
            if ledgerFailedOnly { query.append(URLQueryItem(name: "failed", value: "1")) }
            if !ledgerProvider.isEmpty { query.append(URLQueryItem(name: "provider", value: ledgerProvider)) }
            if !ledgerAgent.isEmpty { query.append(URLQueryItem(name: "agent", value: ledgerAgent)) }
            heatmap = try await client.send(
                .get("/api/usage/heatmap", query: query),
                as: UsageHeatmapDTO.self,
                timeout: 60
            )
        } catch {
            // 热力图失败不覆盖其他数据
        }
    }

    func loadSessions(client: MagpieAPIClient) async {
        isSessionsLoading = true
        defer { isSessionsLoading = false }
        do {
            let response: SessionsResponseDTO = try await client.send(
                .get("/api/sessions"),
                as: SessionsResponseDTO.self,
                timeout: 60
            )
            sessions = response.sessions
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func loadContext(client: MagpieAPIClient) async {
        isContextLoading = true
        defer { isContextLoading = false }
        do {
            context = try await client.send(
                .get("/api/context", query: [URLQueryItem(name: "days", value: "30")]),
                as: UsageContextDTO.self,
                timeout: 60
            )
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// 官方的上下文优化建议（`GET /api/tune?days=`）。
    func loadTune(client: MagpieAPIClient, days: Int = 30) async {
        do {
            tune = try await client.send(
                .get("/api/tune", query: [URLQueryItem(name: "days", value: "\(days)")]),
                as: TuneStateDTO.self,
                timeout: 60
            )
        } catch {
            // 建议失败不覆盖上下文卡片
        }
    }

    /// 采用一条建议（`POST /api/tune/apply`）。
    func applyTune(client: MagpieAPIClient, agent: String, advice: TuneAdviceDTO) async -> Bool {
        guard let value = advice.proposedValue else { return false }
        return await tuneChange(
            client: client,
            path: "/api/tune/apply",
            agent: agent,
            advice: advice,
            value: value
        )
    }

    /// 撤销一条建议（`POST /api/tune/undo`）。
    func undoTune(client: MagpieAPIClient, agent: String, advice: TuneAdviceDTO) async -> Bool {
        await tuneChange(client: client, path: "/api/tune/undo", agent: agent, advice: advice, value: "")
    }

    /// 接管 Codex `config.toml` 中原有的压缩阈值（`POST /api/tune/takeover`）。
    func takeOverTune(client: MagpieAPIClient, agent: String) async -> Bool {
        isOperating = true
        errorMessage = nil
        defer { isOperating = false }
        do {
            struct Body: Encodable { let Agent: String }
            _ = try await client.sendData(
                try Endpoint.post("/api/tune/takeover", body: Body(Agent: agent))
            )
            await loadTune(client: client)
            MagpieHaptics.success()
            return true
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    var isWarmingAll = false
    var warmAllMessage: String?

    /// 一键预热指定订阅类型（`"codex"` / `"claude"`）的所有待预热账号（`POST /api/warm-all`）。
    func warmAll(client: MagpieAPIClient, agents: [String]) async {
        let targets = agents.filter { $0 == "codex" || $0 == "claude" }
        guard !targets.isEmpty else {
            warmAllMessage = String(localized: "当前没有支持预热的订阅账号")
            return
        }
        isWarmingAll = true
        warmAllMessage = nil
        errorMessage = nil
        defer { isWarmingAll = false }

        struct Body: Encodable { let Agent: String }
        var allResults: [WarmAllResultDTO] = []
        var requestErrors: [String] = []

        for agent in targets {
            do {
                let res: WarmAllResponseDTO = try await client.send(
                    .post("/api/warm-all", body: Body(Agent: agent)),
                    as: WarmAllResponseDTO.self,
                    timeout: 120
                )
                allResults.append(contentsOf: res.results)
            } catch {
                let msg = (error as? APIError)?.errorDescription ?? error.localizedDescription
                requestErrors.append("\(agent): \(msg)")
            }
        }

        if allResults.isEmpty, !requestErrors.isEmpty {
            errorMessage = requestErrors.joined(separator: "；")
            return
        }

        let okCount = allResults.filter(\.isWarmed).count
        let errCount = allResults.filter { !($0.error ?? "").isEmpty }.count + requestErrors.count
        let skipCount = allResults.filter { !($0.skip ?? "").isEmpty && ($0.error ?? "").isEmpty }.count
        if okCount == 0 && errCount == 0 {
            warmAllMessage = skipCount > 0
                ? String(localized: "全部 \(skipCount) 个账号窗口均已运行中")
                : String(localized: "当前没有需要预热的账号")
        } else if errCount == 0 {
            warmAllMessage = String(localized: "已预热 \(okCount) 个账号")
            MagpieHaptics.success()
        } else {
            warmAllMessage = String(localized: "预热完成：\(okCount) 成功，\(errCount) 失败")
        }
        if let updated = try? await client.send(.get("/api/usage/quotas"), as: [QuotaItemDTO].self, timeout: 60) {
            quotas = updated
        }
    }

    private func tuneChange(
        client: MagpieAPIClient,
        path: String,
        agent: String,
        advice: TuneAdviceDTO,
        value: String
    ) async -> Bool {
        isOperating = true
        errorMessage = nil
        defer { isOperating = false }
        do {
            struct Body: Encodable {
                let Agent: String
                let Knob: String
                let Model: String
                let Value: String
            }
            _ = try await client.sendData(
                try Endpoint.post(
                    path,
                    body: Body(Agent: agent, Knob: advice.knob, Model: advice.model ?? "", Value: value)
                )
            )
            await loadTune(client: client)
            MagpieHaptics.success()
            return true
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    /// 刷新单张配额卡（官方 `POST /api/usage/quotas/refresh?provider=`）。
    func refreshQuota(client: MagpieAPIClient, provider: String) async {
        isRefreshingQuota = true
        defer { isRefreshingQuota = false }
        do {
            quotas = try await client.send(
                Endpoint(
                    path: "/api/usage/quotas/refresh",
                    method: .post,
                    query: [URLQueryItem(name: "provider", value: provider)]
                ),
                as: [QuotaItemDTO].self,
                timeout: 45
            )
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    var isRefreshingQuota = false

    /// 官方「清除用量」：此前计入的调用不再出现在用量页（记录仍在磁盘上）。
    func clearUsage(client: MagpieAPIClient, provider: String = "", model: String = "") async -> Bool {
        isOperating = true
        errorMessage = nil
        defer { isOperating = false }
        do {
            struct Body: Encodable {
                let Provider: String
                let Model: String
            }
            _ = try await client.sendData(
                try Endpoint.post("/api/usage/clear", body: Body(Provider: provider, Model: model))
            )
            await load(client: client, resetLedger: true)
            return true
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    /// 官方「导出账本 CSV 到服务器 Downloads」。
    func exportLedger(client: MagpieAPIClient) async -> UsageExportResultDTO? {
        isOperating = true
        errorMessage = nil
        defer { isOperating = false }
        var query = [
            URLQueryItem(name: "period", value: period),
            URLQueryItem(name: "tz", value: TimeZone.current.identifier)
        ]
        let q = ledgerQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty { query.append(URLQueryItem(name: "q", value: q)) }
        if ledgerFailedOnly { query.append(URLQueryItem(name: "failed", value: "1")) }
        if ledgerRetriedOnly { query.append(URLQueryItem(name: "retried", value: "1")) }
        if !ledgerProvider.isEmpty { query.append(URLQueryItem(name: "provider", value: ledgerProvider)) }
        if !ledgerAgent.isEmpty { query.append(URLQueryItem(name: "agent", value: ledgerAgent)) }
        do {
            return try await client.send(
                Endpoint(path: "/api/usage/requests/export", method: .post, query: query),
                as: UsageExportResultDTO.self,
                timeout: 120
            )
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            return nil
        }
    }

    /// 官方账本 CSV（`/api/usage/requests.csv`），按当前筛选。
    func fetchLedgerCSV(client: MagpieAPIClient) async -> String? {
        isOperating = true
        errorMessage = nil
        defer { isOperating = false }
        var query = [
            URLQueryItem(name: "period", value: period),
            URLQueryItem(name: "tz", value: TimeZone.current.identifier)
        ]
        let q = ledgerQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty { query.append(URLQueryItem(name: "q", value: q)) }
        if ledgerFailedOnly { query.append(URLQueryItem(name: "failed", value: "1")) }
        if ledgerRetriedOnly { query.append(URLQueryItem(name: "retried", value: "1")) }
        if !ledgerProvider.isEmpty { query.append(URLQueryItem(name: "provider", value: ledgerProvider)) }
        if !ledgerAgent.isEmpty { query.append(URLQueryItem(name: "agent", value: ledgerAgent)) }
        do {
            let data = try await client.sendData(
                Endpoint(path: "/api/usage/requests.csv", method: .get, query: query),
                timeout: 120
            )
            return String(data: data, encoding: .utf8)
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            return nil
        }
    }

    var isOperating = false

    // MARK: - 实时流量（官方 `/api/usage/traffic`）
    var trafficText = ""
    private var trafficTask: Task<Void, Never>?
    private var trafficSamples: [(at: Date, up: Int64, down: Int64)] = []

    func startTraffic(client: MagpieAPIClient) {
        stopTraffic()
        trafficTask = Task { [weak self] in
            guard let self else { return }
            await self.tickTraffic(client: client)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { break }
                await self.tickTraffic(client: client)
            }
        }
    }

    func stopTraffic() {
        trafficTask?.cancel()
        trafficTask = nil
        trafficSamples = []
        trafficText = ""
    }

    private func tickTraffic(client: MagpieAPIClient) async {
        do {
            let traffic: UsageTrafficDTO = try await client.send(
                .get("/api/usage/traffic"),
                as: UsageTrafficDTO.self
            )
            guard let up = traffic.up, let down = traffic.down else {
                trafficText = ""
                return
            }
            let now = Date()
            if let last = trafficSamples.last, up < last.up || down < last.down {
                // 网关重启后计数从头开始
                trafficSamples = []
            }
            trafficSamples.append((now, up, down))
            while trafficSamples.count > 2,
                  now.timeIntervalSince(trafficSamples[1].at) >= 3 {
                trafficSamples.removeFirst()
            }
            guard let first = trafficSamples.first else { return }
            let dt = now.timeIntervalSince(first.at)
            let upRate = dt > 0 ? Double(up - first.up) / dt : 0
            let downRate = dt > 0 ? Double(down - first.down) / dt : 0
            if (traffic.requests ?? 0) == 0 && upRate <= 0 && downRate <= 0 {
                trafficText = ""
            } else if dt > 0 {
                trafficText = "↑ \(Self.byteRate(upRate))/s · ↓ \(Self.byteRate(downRate))/s"
            } else {
                trafficText = ""
            }
        } catch {
            trafficText = ""
        }
    }

    private static func byteRate(_ value: Double) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1f MB", value / 1_000_000)
        }
        if value >= 1_000 {
            return String(format: "%.0f KB", value / 1_000)
        }
        return String(format: "%.0f B", value)
    }

    func reloadForTab(client: MagpieAPIClient) async {
        switch tab {
        case .overview:
            await load(client: client)
        case .requests:
            await load(client: client)
            await loadHeatmap(client: client)
            await loadLedger(client: client, reset: true)
        case .sessions:
            await loadSessions(client: client)
        case .context:
            await loadContext(client: client)
            await loadTune(client: client)
        }
    }

    var ledgerRows: [UsageLedgerRowDTO] { ledger?.rows ?? [] }
    var ledgerProviders: [UsageNamedDTO] { ledger?.providers ?? [] }
    var ledgerAgents: [UsageNamedDTO] { ledger?.agents ?? [] }

    // MARK: - Web 1:1 对齐的核心 KPI 辅助指标
    var ledgerTotalTokens: Int {
        (ledger?.input ?? usage?.input ?? 0) + (ledger?.output ?? usage?.output ?? 0) + (ledger?.cacheRead ?? usage?.cache_read ?? 0)
    }

    var ledgerInputTokens: Int {
        ledger?.input ?? usage?.input ?? 0
    }

    var ledgerOutputTokens: Int {
        ledger?.output ?? usage?.output ?? 0
    }

    var ledgerCacheTokens: Int {
        (ledger?.cacheRead ?? usage?.cache_read ?? 0) + (ledger?.cacheWrite ?? usage?.cache_write ?? 0)
    }

    var ledgerTotalCalls: Int {
        ledger?.calls ?? usage?.calls ?? 0
    }

    var ledgerErrorCalls: Int {
        usage?.errors ?? 0
    }

    var ledgerRetriedCalls: Int {
        usage?.retried ?? 0
    }

    var ledgerSuccessRate: Double? {
        let total = ledgerTotalCalls
        guard total > 0 else { return nil }
        let errors = ledgerErrorCalls
        let rate = 1.0 - (Double(errors) / Double(total))
        return max(0.0, min(1.0, rate))
    }

    var ledgerCacheHitRate: Double? {
        let read = ledger?.cacheRead ?? usage?.cache_read ?? 0
        let inp = ledger?.input ?? usage?.input ?? 0
        let sum = read + inp
        guard sum > 0 else { return nil }
        return Double(read) / Double(sum)
    }

    var sessionTokenTotal: Int {
        sessions.reduce(0) { $0 + ($1.input ?? 0) + ($1.output ?? 0) }
    }

    var sessionCostTotal: Double {
        sessions.reduce(0) { $0 + ($1.cost ?? 0) }
    }

    var periodTitle: String {
        switch period {
        case "today": return String(localized: "今天")
        case "last:24h": return String(localized: "24 小时")
        case "7d": return String(localized: "7 天")
        case "30d": return String(localized: "30 天")
        case "all": return String(localized: "全部")
        default: return period
        }
    }
}
