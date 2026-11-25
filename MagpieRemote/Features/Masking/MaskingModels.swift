import Foundation
import Observation

// MARK: - 脱敏概览
/// `GET /api/masking/summary?days=`（maskrec.Sum）。
struct MaskingSummaryDTO: Codable, Sendable {
    var days: [MaskingDayDTO] = []
    var requests: Int = 0
    var n: Int = 0
    var distinct: Int = 0
    var warned: Int?
    var blocked: Int?
    var hours: [Int] = []
    var kinds: [MaskingCountDTO] = []
    var by: [String: Int]?
    var agents: [MaskingCountDTO] = []
    var providers: [MaskingCountDTO] = []
    var values: [MaskingSeenDTO] = []
    var since: String?

    enum CodingKeys: String, CodingKey {
        case days, requests, n, distinct, warned, blocked, hours, kinds, by, agents, providers, values, since
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.days = (try? c.decode([MaskingDayDTO].self, forKey: .days)) ?? []
        self.requests = (try? c.decode(Int.self, forKey: .requests)) ?? 0
        self.n = (try? c.decode(Int.self, forKey: .n)) ?? 0
        self.distinct = (try? c.decode(Int.self, forKey: .distinct)) ?? 0
        self.warned = try? c.decodeIfPresent(Int.self, forKey: .warned)
        self.blocked = try? c.decodeIfPresent(Int.self, forKey: .blocked)
        self.hours = (try? c.decode([Int].self, forKey: .hours)) ?? []
        self.kinds = (try? c.decode([MaskingCountDTO].self, forKey: .kinds)) ?? []
        self.by = try? c.decodeIfPresent([String: Int].self, forKey: .by)
        self.agents = (try? c.decode([MaskingCountDTO].self, forKey: .agents)) ?? []
        self.providers = (try? c.decode([MaskingCountDTO].self, forKey: .providers)) ?? []
        self.values = (try? c.decode([MaskingSeenDTO].self, forKey: .values)) ?? []
        self.since = try? c.decodeIfPresent(String.self, forKey: .since)
    }
}

struct MaskingDayDTO: Codable, Sendable, Identifiable {
    var day: String
    var requests: Int
    var n: Int
    var distinct: Int

    var id: String { day }
}

struct MaskingCountDTO: Codable, Sendable, Identifiable {
    var name: String
    var n: Int
    var distinct: Int?

    var id: String { name }
}

struct MaskingSeenDTO: Codable, Sendable, Identifiable {
    var p: String
    var kind: String
    var by: String
    var head: String?
    var len: Int
    var n: Int
    var requests: Int
    var last: String?

    var id: String { p }
}

// MARK: - 脱敏记录
/// `GET /api/masking/records`。
struct MaskingRecordsResponseDTO: Codable, Sendable {
    var records: [MaskingRecordDTO] = []
    var more: Bool = false
    var unknown: Bool?

    enum CodingKeys: String, CodingKey { case records, more, unknown }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.records = (try? c.decode([MaskingRecordDTO].self, forKey: .records)) ?? []
        self.more = (try? c.decode(Bool.self, forKey: .more)) ?? false
        self.unknown = try? c.decodeIfPresent(Bool.self, forKey: .unknown)
    }
}

struct MaskingRecordDTO: Codable, Sendable, Identifiable, Hashable {
    var key: String
    var t: String?
    var route: Int64?
    var what: String?
    var agent: String?
    var session: String?
    var provider: String?
    var model: String?
    var n: Int
    var values: [MaskingValueDTO]?
    var hits: [String]?
    var blocked: Bool?
    var took: Int64?

    var id: String { key }

    var isBlocked: Bool { blocked ?? false }

    var date: Date? {
        guard let t else { return nil }
        // ISO8601DateFormatter 不是 Sendable，不能做成静态共享实例；
        // 只在展示记录时按需创建，避免 Swift 6 的并发检查。
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: t) { return date }

        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: t)
    }
}

struct MaskingValueDTO: Codable, Sendable, Identifiable, Hashable {
    var p: String
    var k: String
    var b: String
    var h: String?
    var l: Int
    var n: Int
    var a: String?
    var known: Bool?

    var id: String { p }

    /// masked（默认）/ warn（明文放行并记录）/ block（拦截请求）。
    var action: String { a ?? "" }
}

// MARK: - 脱敏预览
/// `POST /api/masking/preview`。
struct MaskingPreviewDTO: Codable, Sendable {
    var text: String
    var hits: [MaskingHitDTO] = []
    var off: Bool?

    enum CodingKeys: String, CodingKey { case text, hits, off }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.text = (try? c.decode(String.self, forKey: .text)) ?? ""
        self.hits = (try? c.decode([MaskingHitDTO].self, forKey: .hits)) ?? []
        self.off = try? c.decodeIfPresent(Bool.self, forKey: .off)
    }
}

struct MaskingHitDTO: Codable, Sendable, Identifiable, Hashable {
    var kind: String
    var by: String
    var action: String?
    var placeholder: String
    var head: String?
    var len: Int

    var id: String { placeholder + kind }
}

// MARK: - 格式化辅助
enum MaskingFormat {
    static func kindName(_ kind: String) -> String {
        switch kind.uppercased() {
        case "API_KEY": return String(localized: "API Key")
        case "PRIVATE_KEY": return String(localized: "私钥")
        case "PASSWORD": return String(localized: "密码")
        case "TOKEN": return String(localized: "Token")
        case "EMAIL": return String(localized: "邮箱")
        case "PHONE": return String(localized: "电话")
        case "SSN": return String(localized: "证件号")
        case "CARD": return String(localized: "银行卡")
        case "IP": return String(localized: "IP 地址")
        case "HOME": return String(localized: "住址")
        case "SECRET": return String(localized: "密钥")
        default:
            return kind
                .replacingOccurrences(of: "_", with: " ")
                .capitalized
        }
    }

    static func byName(_ by: String) -> String {
        switch by {
        case "rule": return String(localized: "内置规则")
        case "yours": return String(localized: "自定义规则")
        case "word": return String(localized: "你的词表")
        case "model": return String(localized: "本地模型")
        case "known": return String(localized: "已知密钥")
        default: return by
        }
    }

    static func relative(_ date: Date?) -> String {
        guard let date else { return "—" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - ViewModel
@Observable
@MainActor
final class MaskingViewModel {
    var summary: MaskingSummaryDTO?
    var records: [MaskingRecordDTO] = []
    var hasMore = false
    var isLoading = false
    var isLoadingMore = false
    var isClearing = false
    var errorMessage: String?

    var preview: MaskingPreviewDTO?
    var isPreviewing = false
    var previewError: String?

    var days = 7
    var blockedOnly = false
    var kindFilter = ""
    var agentFilter = ""
    var providerFilter = ""
    var query = ""
    var hasUnknownSearchValues = false

    func load(client: MagpieAPIClient) async {
        isLoading = true
        errorMessage = nil
        async let summaryTask: MaskingSummaryDTO = client.send(
            .get("/api/masking/summary", query: [URLQueryItem(name: "days", value: "\(days)")]),
            as: MaskingSummaryDTO.self
        )
        async let recordsTask: MaskingRecordsResponseDTO = client.send(
            .get("/api/masking/records", query: recordQuery(before: nil)),
            as: MaskingRecordsResponseDTO.self
        )

        do {
            let (s, r) = try await (summaryTask, recordsTask)
            summary = s
            records = r.records
            hasMore = r.more
            hasUnknownSearchValues = r.unknown == true
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
    }

    func reloadRecords(client: MagpieAPIClient) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let r: MaskingRecordsResponseDTO = try await client.send(
                .get("/api/masking/records", query: recordQuery(before: nil)),
                as: MaskingRecordsResponseDTO.self
            )
            records = r.records
            hasMore = r.more
            hasUnknownSearchValues = r.unknown == true
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func loadMore(client: MagpieAPIClient) async {
        guard hasMore, !isLoadingMore, let last = records.last else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let r: MaskingRecordsResponseDTO = try await client.send(
                .get("/api/masking/records", query: recordQuery(before: last.key)),
                as: MaskingRecordsResponseDTO.self
            )
            records.append(contentsOf: r.records)
            hasMore = r.more
            if r.unknown == true { hasUnknownSearchValues = true }
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func runPreview(client: MagpieAPIClient, text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            preview = nil
            return
        }
        isPreviewing = true
        previewError = nil
        defer { isPreviewing = false }
        do {
            struct Body: Encodable { var text: String }
            let result: MaskingPreviewDTO = try await client.send(
                .post("/api/masking/preview", body: Body(text: text)),
                as: MaskingPreviewDTO.self
            )
            preview = result
        } catch {
            previewError = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func clearRecords(client: MagpieAPIClient) async -> Bool {
        isClearing = true
        defer { isClearing = false }
        do {
            _ = try await client.sendData(Endpoint.post("/api/masking/clear"))
            records = []
            hasMore = false
            summary = try await client.send(
                .get("/api/masking/summary", query: [URLQueryItem(name: "days", value: "\(days)")]),
                as: MaskingSummaryDTO.self
            )
            return true
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    /// 某条记录实际发给厂商的请求体（脱敏后，官方 `/api/masking/sent`）。
    func fetchSent(client: MagpieAPIClient, key: String) async -> String? {
        do {
            struct Response: Codable { var body: String? }
            let res: Response = try await client.send(
                .get("/api/masking/sent", query: [URLQueryItem(name: "key", value: key)]),
                as: Response.self
            )
            return res.body
        } catch {
            return nil
        }
    }

    /// 把某个占位符对应的原值加入「永不脱敏」，之后按原文发送。
    func allow(client: MagpieAPIClient, placeholder: String) async -> Bool {
        do {
            struct Body: Encodable { var p: String }
            _ = try await client.sendData(try Endpoint.post("/api/masking/allow", body: Body(p: placeholder)))
            return true
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    private func recordQuery(before: String?) -> [URLQueryItem] {
        var q = [URLQueryItem(name: "limit", value: "40")]
        if let before { q.append(URLQueryItem(name: "before", value: before)) }
        if blockedOnly { q.append(URLQueryItem(name: "blocked", value: "1")) }
        if !kindFilter.isEmpty { q.append(URLQueryItem(name: "kind", value: kindFilter)) }
        if !agentFilter.isEmpty { q.append(URLQueryItem(name: "agent", value: agentFilter)) }
        if !providerFilter.isEmpty { q.append(URLQueryItem(name: "provider", value: providerFilter)) }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { q.append(URLQueryItem(name: "q", value: trimmed)) }
        return q
    }
}
