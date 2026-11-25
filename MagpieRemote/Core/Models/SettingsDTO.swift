import Foundation

/// magpie `settings.Settings` 的核心与扩展模型：1:1 对齐官方设置项。
/// 具备高度健壮的容错解码设计，对任意未知或类型变动字段平滑兜底，杜绝解析崩溃。
struct SettingsDTO: Codable, Sendable, Hashable {
    // 通用外观与偏好
    var name: String?
    var nameEnv: String?
    var theme: String?
    var lang: String?
    var currency: String?
    var tray: String?
    var sessionTerminal: String?
    var updateEvery: Int?
    var updateChannel: String?
    var textSize: Int?
    var dayStart: Int?
    var quotaLeft: Bool?
    var chineseUnits: Bool?

    // 网络与共享
    var lan: Bool?
    var lanKeyId: String?
    var gatewayConversations: Bool?
    var proxyNow: String?
    var proxySource: String?
    var proxies: [SavedProxyDTO]?

    // 隐私与脱敏
    var redact: Bool?
    var redactPersonal: Bool?
    var redactModel: Bool?
    var redactShape: Bool?
    var redactModelName: String?
    var redactModelDir: String?
    var redactWordsAnyCase: Bool?

    // 专属优化与状态
    var claudeCacheEnabled: Bool?
    var claudeCacheKnobs: [ClaudeCacheKnobDTO]?
    var claudeAttributionOff: Bool?
    var claudeAttributionRaw: String?
    var claudeNoExtraUsage: Bool?
    var claudeRegionHold: Bool?
    var visionAutoModel: String?
    var imageResolution: String?
    var bareModelIDs: Bool?
    var bareModelIDsOnly: Bool?
    var codexSuggestions: String?
    var routerAllTools: Bool?
    var routerNoCode: Bool?
    var requestArchiveMB: Int?
    var trayAnthropicMark: Bool?
    var version: String?
    var gateway: String?
    var dir: String?

    // 官方设置页其余可确认的开关
    var awake: Bool?
    var fullContext: Bool?
    var codexAgentsV1: Bool?
    var trayUsageEvery: Int?
    var quotaReads: String?
    var plainNames: Bool?

    // 可观测性（OTLP 导出，官方 otel 插件）
    var otel: OtelSettingsDTO?

    init(
        theme: String? = nil,
        lang: String? = nil,
        currency: String? = nil,
        tray: String? = nil,
        sessionTerminal: String? = nil,
        updateEvery: Int? = nil,
        textSize: Int? = nil,
        lan: Bool? = nil,
        lanKeyId: String? = nil,
        gatewayConversations: Bool? = nil,
        redact: Bool? = nil,
        redactPersonal: Bool? = nil,
        redactModel: Bool? = nil,
        claudeCacheEnabled: Bool? = nil,
        claudeAttributionOff: Bool? = nil,
        visionAutoModel: String? = nil,
        version: String? = nil,
        gateway: String? = nil,
        dir: String? = nil
    ) {
        self.theme = theme
        self.lang = lang
        self.currency = currency
        self.tray = tray
        self.sessionTerminal = sessionTerminal
        self.updateEvery = updateEvery
        self.textSize = textSize
        self.dayStart = nil
        self.quotaLeft = nil
        self.chineseUnits = nil
        self.lan = lan
        self.lanKeyId = lanKeyId
        self.gatewayConversations = gatewayConversations
        self.redact = redact
        self.redactPersonal = redactPersonal
        self.redactModel = redactModel
        self.redactShape = nil
        self.redactModelName = nil
        self.claudeCacheEnabled = claudeCacheEnabled
        self.claudeAttributionOff = claudeAttributionOff
        self.claudeAttributionRaw = nil
        self.visionAutoModel = visionAutoModel
        self.version = version
        self.gateway = gateway
        self.dir = dir
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.name = try? container.decodeIfPresent(String.self, forKey: .name)
        self.nameEnv = try? container.decodeIfPresent(String.self, forKey: .nameEnv)
        self.theme = try? container.decodeIfPresent(String.self, forKey: .theme)
        self.lang = try? container.decodeIfPresent(String.self, forKey: .lang)
        self.currency = try? container.decodeIfPresent(String.self, forKey: .currency)
        self.sessionTerminal = try? container.decodeIfPresent(String.self, forKey: .sessionTerminal)
        self.updateChannel = try? container.decodeIfPresent(String.self, forKey: .updateChannel)
        self.lan = try? container.decodeIfPresent(Bool.self, forKey: .lan)
        self.lanKeyId = try? container.decodeIfPresent(String.self, forKey: .lanKeyId)
        self.gatewayConversations = try? container.decodeIfPresent(Bool.self, forKey: .gatewayConversations)
        self.proxyNow = try? container.decodeIfPresent(String.self, forKey: .proxyNow)
        self.proxySource = try? container.decodeIfPresent(String.self, forKey: .proxySource)
        self.proxies = try? container.decodeIfPresent([SavedProxyDTO].self, forKey: .proxies)
        self.redact = try? container.decodeIfPresent(Bool.self, forKey: .redact)
        self.redactPersonal = try? container.decodeIfPresent(Bool.self, forKey: .redactPersonal)
        self.redactModel = try? container.decodeIfPresent(Bool.self, forKey: .redactModel)
        self.redactShape = try? container.decodeIfPresent(Bool.self, forKey: .redactShape)
        self.redactModelName = try? container.decodeIfPresent(String.self, forKey: .redactModelName)
        self.redactModelDir = try? container.decodeIfPresent(String.self, forKey: .redactModelDir)
        self.redactWordsAnyCase = try? container.decodeIfPresent(Bool.self, forKey: .redactWordsAnyCase)
        self.claudeNoExtraUsage = try? container.decodeIfPresent(Bool.self, forKey: .claudeNoExtraUsage)
        self.claudeRegionHold = try? container.decodeIfPresent(Bool.self, forKey: .claudeRegionHold)
        self.imageResolution = try? container.decodeIfPresent(String.self, forKey: .imageResolution)
        self.bareModelIDs = try? container.decodeIfPresent(Bool.self, forKey: .bareModelIDs)
        self.bareModelIDsOnly = try? container.decodeIfPresent(Bool.self, forKey: .bareModelIDsOnly)
        self.codexSuggestions = try? container.decodeIfPresent(String.self, forKey: .codexSuggestions)
        self.routerAllTools = try? container.decodeIfPresent(Bool.self, forKey: .routerAllTools)
        self.routerNoCode = try? container.decodeIfPresent(Bool.self, forKey: .routerNoCode)
        self.requestArchiveMB = try? container.decodeIfPresent(Int.self, forKey: .requestArchiveMB)
        self.trayAnthropicMark = try? container.decodeIfPresent(Bool.self, forKey: .trayAnthropicMark)
        self.version = try? container.decodeIfPresent(String.self, forKey: .version)
        self.gateway = try? container.decodeIfPresent(String.self, forKey: .gateway)
        self.dir = try? container.decodeIfPresent(String.self, forKey: .dir)
        self.textSize = try? container.decodeIfPresent(Int.self, forKey: .textSize)
        self.dayStart = try? container.decodeIfPresent(Int.self, forKey: .dayStart)
        self.quotaLeft = try? container.decodeIfPresent(Bool.self, forKey: .quotaLeft)
        self.chineseUnits = try? container.decodeIfPresent(Bool.self, forKey: .chineseUnits)

        // tray: 支持 String 或 Bool
        if let str = try? container.decodeIfPresent(String.self, forKey: .tray) {
            self.tray = str
        } else if let b = try? container.decodeIfPresent(Bool.self, forKey: .tray) {
            self.tray = b ? "true" : "false"
        }

        // updateEvery: 支持 Int 或 String
        if let i = try? container.decodeIfPresent(Int.self, forKey: .updateEvery) {
            self.updateEvery = i
        } else if let str = try? container.decodeIfPresent(String.self, forKey: .updateEvery), let i = Int(str) {
            self.updateEvery = i
        }

        // claudeCache: 在服务端可能是 list，也可能是 bool
        if let b = try? container.decodeIfPresent(Bool.self, forKey: .claudeCacheEnabled) {
            self.claudeCacheEnabled = b
        } else if let knobs = try? container.decodeIfPresent([ClaudeCacheKnobDTO].self, forKey: .claudeCacheEnabled) {
            self.claudeCacheKnobs = knobs
            self.claudeCacheEnabled = !knobs.isEmpty
        }

        // claudeAttribution: 在服务端可能是 "off" 或 bool
        self.claudeAttributionRaw = try? container.decodeIfPresent(String.self, forKey: .claudeAttributionOff)
        if let str = try? container.decodeIfPresent(String.self, forKey: .claudeAttributionOff) {
            self.claudeAttributionOff = (str != "off")
        } else if let b = try? container.decodeIfPresent(Bool.self, forKey: .claudeAttributionOff) {
            self.claudeAttributionOff = b
        }

        // visionAuto: 服务端为模型字符串 (如 "codex/gpt-6-luna")
        self.visionAutoModel = try? container.decodeIfPresent(String.self, forKey: .visionAutoModel)

        self.awake = try? container.decodeIfPresent(Bool.self, forKey: .awake)
        self.fullContext = try? container.decodeIfPresent(Bool.self, forKey: .fullContext)
        self.codexAgentsV1 = try? container.decodeIfPresent(Bool.self, forKey: .codexAgentsV1)
        self.trayUsageEvery = try? container.decodeIfPresent(Int.self, forKey: .trayUsageEvery)
        self.quotaReads = try? container.decodeIfPresent(String.self, forKey: .quotaReads)
        self.plainNames = try? container.decodeIfPresent(Bool.self, forKey: .plainNames)
        self.otel = try? container.decodeIfPresent(OtelSettingsDTO.self, forKey: .otel)
    }

    enum CodingKeys: String, CodingKey {
        case name, nameEnv, theme, lang, currency, tray, sessionTerminal, updateEvery, updateChannel, textSize
        case dayStart, quotaLeft, chineseUnits
        case lan, lanKeyId, gatewayConversations, proxyNow, proxySource, proxies
        case redact, redactPersonal, redactModel
        case redactShape, redactModelName, redactModelDir, redactWordsAnyCase
        case claudeCacheEnabled = "claudeCache"
        case claudeAttributionOff = "claudeAttribution"
        case claudeAttributionRaw
        case claudeNoExtraUsage, claudeRegionHold
        case visionAutoModel = "visionAuto"
        case imageResolution, bareModelIDs, bareModelIDsOnly, codexSuggestions
        case routerAllTools, routerNoCode, requestArchiveMB, trayAnthropicMark
        case version, gateway, dir
        case awake = "\u{6B}\u{65}\u{65}\u{70}\u{41}\u{77}\u{61}\u{6B}\u{65}"
        case fullContext, codexAgentsV1, trayUsageEvery, quotaReads, plainNames
        case otel
    }
}

/// 命名代理（支持 HTTP / SOCKS5 / SSH，`savedProxyJSON`）。
struct SavedProxyDTO: Codable, Sendable, Identifiable, Hashable {
    var id: String
    var name: String
    var url: String
    var user: String?
    var hasPass: Bool?
    var hasKey: Bool?
    var hostKey: String?
    var uses: [ProxyUseDTO]?
    /// 服务端 `savedProxyJSON.check`（上次连通性检测结果）。
    var test: ProxyTestResultDTO?

    var isSSH: Bool {
        url.lowercased().hasPrefix("ssh://")
    }

    enum CodingKeys: String, CodingKey {
        case id, name, url, user, hasPass, hasKey, hostKey, uses
        case test = "check"
    }
}

struct ProxyUseDTO: Codable, Sendable, Hashable {
    var whereUsed: String?
    var provider: String?
    var account: String?

    var displayLabel: String? {
        if let whereUsed, !whereUsed.isEmpty {
            switch whereUsed {
            case "global": return String(localized: "全局代理")
            case "plugins": return String(localized: "插件下载")
            case "updates": return String(localized: "更新检查")
            default: return whereUsed
            }
        }
        if let provider, !provider.isEmpty {
            if let account, !account.isEmpty {
                return "\(provider) (\(account))"
            }
            return provider
        }
        return account?.isEmpty == false ? account : nil
    }

    enum CodingKeys: String, CodingKey {
        case whereUsed = "where"
        case provider, account
    }
}

struct ProxyTestResultDTO: Codable, Sendable, Hashable {
    var ok: Bool
    var ms: Int64?
    var ip: String?
    var loc: String?
    var error: String?
    var why: String?
    var addr: String?
    var was: String?
    var now: String?
    var at: Int64?
}

/// `GET /api/update`：服务器 magpie 的更新状态与频道信息（对齐 upstream `updateJSON`）。
struct UpdateStatusDTO: Codable, Sendable, Hashable {
    var state: String?
    var current: String?
    var latest: String?
    var channel: String?
    var newest: String?
    var ahead: Bool?
    var run: Int64?
    var stuck: String?
    var retry: Bool?
    var error: String?
    var notes: String?
    var url: String?
    var image: String?
    var done: Int64?
    var total: Int64?

    var hasUpdate: Bool {
        state == "available" || state == "found" || state == "ready" || state == "downloading"
    }
}

/// 官方 Settings › Observability（OTLP 导出）配置。
struct OtelSettingsDTO: Codable, Sendable, Hashable {
    var enabled: Bool?
    var endpoint: String?
    var headers: [String: String]?
    var metrics: Bool?
    var sessions: Bool?
    var bodies: Bool?
    var bodiesWhole: Bool?

    init(
        enabled: Bool? = nil,
        endpoint: String? = nil,
        headers: [String: String]? = nil,
        metrics: Bool? = nil,
        sessions: Bool? = nil,
        bodies: Bool? = nil,
        bodiesWhole: Bool? = nil
    ) {
        self.enabled = enabled
        self.endpoint = endpoint
        self.headers = headers
        self.metrics = metrics
        self.sessions = sessions
        self.bodies = bodies
        self.bodiesWhole = bodiesWhole
    }
}

/// `POST /api/backup/export` 的返回：服务器 Downloads 里的备份文件。
struct BackupExportResultDTO: Codable, Sendable {
    var path: String?
    var providers: Int?
    var profiles: Int?
    var agents: Int?
    var library: Bool?
    var signIns: Int?
    var usage: Int?
}

/// Claude Code 提示词缓存的一个 knob（cache_ttl / subagent_cache_ttl）。
struct ClaudeCacheKnobDTO: Codable, Sendable, Hashable, Identifiable {
    var knob: String?
    var value: String?

    var id: String { knob ?? "knob" }
}

/// 泛型宽容包装器，用于安全吞掉任意类型的未知数组元素
private struct AnyCodableWrapper: Codable, Sendable {
    init(from decoder: Decoder) throws {}
    func encode(to encoder: Encoder) throws {}
}
