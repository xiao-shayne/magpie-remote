import Foundation

/// 单个支持的模型描述（兼容从对象 {"id": "...", "name": "..."} 或纯模型 ID 字符串解码）
struct ProviderModelDTO: Codable, Sendable, Identifiable, Hashable, CustomStringConvertible {
    var id: String
    var name: String?
    var on: Bool?
    var context: Int?
    var output: Int?
    var efforts: [String]?
    /// 用户保留的推理档；缺省表示全部保留。
    var kept: [String]?
    var images: Bool?
    /// 若命中 Settings 的禁用模型规则，这里记录匹配的规则串。
    var disabled: String?

    init(id: String, name: String? = nil, on: Bool? = nil) {
        self.id = id
        self.name = name
        self.on = on
    }

    var displayName: String {
        if let name, !name.isEmpty, name != id {
            return "\(name) (\(id))"
        }
        return id
    }

    var description: String { displayName }

    init(from decoder: Decoder) throws {
        if let container = try? decoder.singleValueContainer(),
           let stringVal = try? container.decode(String.self) {
            self.id = stringVal
            self.name = stringVal
            self.on = nil
            self.context = nil
            self.output = nil
            self.efforts = nil
            self.kept = nil
            self.images = nil
            self.disabled = nil
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.name = try container.decodeIfPresent(String.self, forKey: .name)
        self.on = try container.decodeIfPresent(Bool.self, forKey: .on)
        self.context = try container.decodeIfPresent(Int.self, forKey: .context)
        self.output = try container.decodeIfPresent(Int.self, forKey: .output)
        self.efforts = try container.decodeIfPresent([String].self, forKey: .efforts)
        self.kept = try container.decodeIfPresent([String].self, forKey: .kept)
        self.images = try container.decodeIfPresent(Bool.self, forKey: .images)
        self.disabled = try container.decodeIfPresent(String.self, forKey: .disabled)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(on, forKey: .on)
        try container.encodeIfPresent(context, forKey: .context)
        try container.encodeIfPresent(output, forKey: .output)
        try container.encodeIfPresent(efforts, forKey: .efforts)
        try container.encodeIfPresent(kept, forKey: .kept)
        try container.encodeIfPresent(images, forKey: .images)
        try container.encodeIfPresent(disabled, forKey: .disabled)
    }

    enum CodingKeys: String, CodingKey {
        case id, name, on, context, output, efforts, kept, images, disabled
    }
}

/// magpie 单个 Provider 详情
struct ProviderDTO: Codable, Sendable, Identifiable, Hashable {
    var id: String
    var name: String
    var icon: String?
    var preset: String?
    var host: String?
    var chat: String?
    var responses: String?
    var anthropic: String?
    var gemini: String?
    var decide: String?
    var catalog: String?
    var website: String?
    var keysUrl: String?
    var baseAPI: String?
    var off: Bool?
    var models: [ProviderModelDTO]?
    var keyList: [KeyItemDTO]?
    var chosen: [String]?
    var exposed: Int?
    var speaks: [String]?
    var searches: Bool?
    var unredacted: Bool?
    // 编辑器中的连接与路由状态
    var key: KeyInfoDTO?
    var proxy: String?
    var routing: String?
    var affinity: String?
    var sink: Bool?
    var useFirst: Bool?
    var noStandIn: Bool?
    var maxConcurrency: Int?
    var queueLimit: Int?
    var queueWait: Int?
    var maxRPM: Int?
    var maxImages: [String: Int]?
    var priceRate: Double?
    /// sub2api 中转美元充值汇率，以及各 Key 的组倍率。
    var topUpRate: Double?
    var keyGroupRates: [String: Double]?
    /// 嵌入与重排模型列表（不参与对话模型勾选）。
    var retrieval: Int?
    var embedIds: [String]?
    var rerankIds: [String]?
    /// Claude 订阅账号的出口地区检测结果。
    var egress: EgressResultDTO?
    /// 所选命名代理已被删除时的提示。
    var proxyGone: String?
    /// Remote magpie：自动在本机连接远端已接入的 Agent。
    var connectAgents: Bool?
    var libraryShared: Bool?
    // 官方编辑器的高级字段
    var fallback: [String]?
    var unlisted: Bool?
    var noModels: Bool?
    var bestInFamily: Bool?
    var listOff: Bool?
    var headers: [String: String]?
    var extraBody: JSONValue?
    var replyHeaders: [String]?
    var passHeaders: [String]?
    var insecureTLS: Bool?
    var takesInsecureTLS: Bool?
    var http1: Bool?
    var socket: String?
    var takesSocket: Bool?
    var limitRestOff: Bool?
    var passUserAgent: Bool?
    var authHeader: String?
    var bothAuth: Bool?
    var nativeCompaction: Bool?
    var carriesCompaction: Bool?
    var passErrors: Bool?
    var takesPassErrors: Bool?
    var modelsURL: String?
    var balanceURL: String?
    var balancePath: String?
    var balanceMethod: String?
    var balanceToken: BalanceTokenDTO?
    var takesOwnBalance: Bool?
    var decidesAPIKind: Bool?
    var takesListOff: Bool?
    var takesModelHeaders: Bool?
    var ready: Bool?
    // 订阅账号（codex / claude / copilot 等登录型 Provider）
    var account: JSONValue?
    var keepLogin: Bool?
    var keepLoginAs: String?
    var switchOnly: Bool?
    var restartApp: Bool?
    /// 用户为模型设置的上下文窗口与回复上限（按模型 id，"*" 表示全部）。
    var contexts: [String: Int]?
    var outputs: [String: Int]?
    /// 每个订阅账号的上限、权重与并发（按账号小写名 / Key id）。
    var accountCaps: [String: Int]?
    var accountWeights: [String: Int]?
    var accountConcurrency: [String: Int]?

    struct BalanceTokenDTO: Codable, Sendable, Hashable {
        var takes: Bool?
        var set: Bool?
    }

    var vertex: VertexDTO?

    struct VertexDTO: Codable, Sendable, Hashable {
        var project: String?
        var location: String?
    }

    /// 是不是订阅登录型 Provider。
    var isSubscription: Bool {
        if case .object = account { return true }
        return false
    }

    /// 订阅账号展示信息（官方 accountJSON 的宽松读取）。
    var accountUser: String? {
        account?.string("user") ?? account?.string("email")
    }

    var accountPlan: String? {
        account?.string("plan")
    }

    var accountAgentName: String? {
        account?.string("agentName")
    }

    var accountAgent: String? {
        account?.string("agent")
    }

    /// 该订阅记住的其它登录账号（官方 account.logins）。
    var accountLogins: [String] {
        guard let items = account?.objectValue?["logins"]?.arrayValue else { return [] }
        return items.compactMap { $0.string("user") ?? $0.string("name") }
    }

    /// 官方编辑器里可选的认证头：""（两者都发）、x-api-key、bearer。
    var authHeaderLabel: String {
        switch authHeader ?? "" {
        case "x-api-key": return "x-api-key"
        case "bearer": return "Bearer"
        default: return String(localized: "默认")
        }
    }

    var isOff: Bool { off ?? false }

    struct KeyInfoDTO: Codable, Sendable, Hashable {
        var isSet: Bool
        var masked: String?
        var isOptional: Bool

        enum CodingKeys: String, CodingKey {
            case isSet = "set"
            case masked
            case isOptional = "optional"
        }
    }

    struct KeyItemDTO: Codable, Sendable, Identifiable, Hashable {
        var id: String
        var name: String?
        var masked: String?
        var active: Bool?
        var on: Bool?
        var protocolName: String?
        var plan: String?
        var weight: Int?
        var rest: KeyRestDTO?

        var displayName: String {
            if let name, !name.isEmpty { return name }
            return masked ?? id
        }

        var protocolLabel: String? {
            guard let protocolName, !protocolName.isEmpty else { return nil }
            switch protocolName {
            case "chat": return "Chat"
            case "responses": return "Responses"
            case "anthropic": return "Anthropic"
            case "gemini": return "Gemini"
            default: return protocolName
            }
        }

        enum CodingKeys: String, CodingKey {
            case id, name, masked, active, on
            case protocolName = "protocol"
            case plan, weight, rest
        }
    }

    struct KeyRestDTO: Codable, Sendable, Hashable {
        var why: String?
        var status: Int?
        var until: String?
        var key: String?
        var probed: Bool?
        var by: String?
        var model: String?
        var error: String?
        var rate: Bool?
        /// 冷却已结束但上游限额仍在生效的提示。
        var notice: Bool?
        var at: String?
    }
}

/// Claude 订阅出口地区检测结果（`egress.Result`）。
struct EgressResultDTO: Codable, Sendable, Hashable {
    var state: String
    var loc: String?
    var at: String?
    var error: String?
    var via: String?

    var isUnsupported: Bool {
        state == "unsupported" || state == "blocked"
    }

    var isSupported: Bool {
        state == "ok" || state == "supported"
    }
}

/// `POST /api/relay-check`：对中转站单模型的准确性、工具调用与速度实测结果。
struct RelayCheckResultDTO: Codable, Sendable, Hashable {
    var provider: String
    var model: String
    var parts: [RelayPartDTO]

    var passedCount: Int { parts.filter { $0.ok && $0.match }.count }
}

struct RelayPartDTO: Codable, Sendable, Identifiable, Hashable {
    var kind: String
    var ask: String?
    var ok: Bool
    var match: Bool
    var status: Int?
    var error: String?
    var want: String?
    var got: String?
    var served: String?
    var by: String?
    var ms: Int64
    var ttftMs: Int64?
    var tps: Double?
    var input: Int?
    var output: Int?
    var promptChars: Int?
    var tries: Int?

    var id: String { "\(kind)-\(ask ?? "")" }

    enum CodingKeys: String, CodingKey {
        case kind, ask, ok, match, status, error, want, got, served, by, ms
        case ttftMs = "ttft_ms"
        case tps, input, output
        case promptChars = "prompt_chars"
        case tries
    }
}

/// 下架但仍在启用的旧插件提醒。
struct WithdrawnPluginDTO: Codable, Sendable, Identifiable, Hashable {
    var id: String
    var name: String?
    var instead: String?
    var insteadId: String?
    var packageName: String?
    var spec: String?
    var off: Bool?
    var beside: Bool?

    enum CodingKeys: String, CodingKey {
        case id, name, instead, insteadId, spec, off, beside
        case packageName = "package"
    }
}

struct UnremovedProviderDTO: Codable, Sendable, Identifiable, Hashable {
    var id: String
    var error: String?
}

/// 预设 Provider 模板
struct PresetDTO: Codable, Sendable, Identifiable {
    var id: String
    var name: String
    var icon: String?
    var kind: String?
    var chat: String?
    var responses: String?
    var anthropic: String?
    var decide: String?
    var catalog: String?
    var website: String?
    var keysUrl: String?
    var note: String?
    var short: String?
    var noKey: Bool?
    var keyHint: String?
    var sponsored: Bool?
    var regions: [PresetRegionDTO]?
    var regionLabel: String?
    var endpoint: String?
    var endpointHint: String?
    var endpointNeeded: String?
    var only: String?
    var models: [String]?
    var noList: Bool?
    var notes: [String: String]?
    var langs: [String]?
    var new: Bool?
    var ownClient: Bool?
    var vertex: Bool?
    var keyPlans: Bool?
    var splitAccounts: Bool?
    var siteHost: String?
    var added: Bool?

    var host: String? {
        chat ?? responses ?? anthropic ?? decide
    }

    var displayName: String {
        if let short, !short.isEmpty { return short }
        return name
    }

    var localizedNote: String? {
        if let zh = notes?["zh"], !zh.isEmpty { return zh }
        if let note, !note.isEmpty { return note }
        if let en = notes?["en"], !en.isEmpty { return en }
        return nil
    }

    var isPartner: Bool { sponsored == true }
}

/// 一个预设的 Base URL 区域/套餐选项（Region）。
struct PresetRegionDTO: Codable, Sendable, Identifiable, Hashable {
    var id: String
    var name: String
    var chat: String?
    var responses: String?
    var anthropic: String?
    var keysUrl: String?
    var website: String?
    var models: [String]?

    var label: String { name.isEmpty ? id : name }
}

/// `GET /api/providers` 响应体
struct ProvidersResponseDTO: Codable, Sendable {
    var providers: [ProviderDTO]
    var presets: [PresetDTO]?
    /// 插件提供的订阅（官方 Add 面板的 plugin subs）。
    var plugins: [PluginSubDTO]?
    var withdrawn: [WithdrawnPluginDTO]?
    var agyMove: [String]?
    var placed: String?
    var unremoved: [UnremovedProviderDTO]?
}

/// 插件提供的一个订阅：登录后成为一个 Provider。
struct PluginSubDTO: Codable, Sendable, Identifiable, Hashable {
    var id: String
    var pid: String?
    var name: String
    var icon: String?
    var spec: String
    var methods: [PluginMethodDTO]?
    var signedIn: Bool?
    var single: Bool?
    var models: Int?

    var displayName: String { name.isEmpty ? id : name }
    var isSignedIn: Bool { signedIn ?? false }
}

/// 插件的登录方式（OpenCode 的 auth method）。
struct PluginMethodDTO: Codable, Sendable, Hashable {
    var type: String?
    var label: String?
    var labels: [String: String]?
    var placeholder: String?
    var keyless: Bool?
    var keyAsked: Bool?

    var isAPI: Bool { type == "api" }

    var displayLabel: String {
        if let labels, let zh = labels["zh"], !zh.isEmpty { return zh }
        if let labels, let en = labels["en"], !en.isEmpty { return en }
        if let label, !label.isEmpty { return label }
        return isAPI ? String(localized: "API Key") : String(localized: "浏览器")
    }
}

/// 插件登录的一次提问（`plugin-signin/prompt` 的 prompt）。
struct PluginPromptDTO: Codable, Sendable, Hashable {
    var key: String?
    var type: String?
    var message: String?
    var messages: [String: String]?
    var placeholder: String?
    var options: [PluginPromptOptionDTO]?

    var isSelect: Bool { type == "select" }

    var displayMessage: String {
        if let messages, let zh = messages["zh"], !zh.isEmpty { return zh }
        if let messages, let en = messages["en"], !en.isEmpty { return en }
        return message ?? ""
    }
}

struct PluginPromptOptionDTO: Codable, Sendable, Hashable, Identifiable {
    var value: String?
    var label: String?
    var labels: [String: String]?
    var hint: String?
    var hints: [String: String]?

    var id: String { value ?? label ?? "option" }

    var displayLabel: String {
        if let labels, let zh = labels["zh"], !zh.isEmpty { return zh }
        if let labels, let en = labels["en"], !en.isEmpty { return en }
        return label ?? value ?? ""
    }

    var displayHint: String? {
        if let hints, let zh = hints["zh"], !zh.isEmpty { return zh }
        if let hints, let en = hints["en"], !en.isEmpty { return en }
        return hint
    }
}

/// `POST /api/plugin-signin/prompt` 的返回。
struct PluginPromptResponseDTO: Codable, Sendable {
    var prompt: PluginPromptDTO?
    var inputs: [String: String]?
    var error: String?
}

/// `POST /api/plugin-signin` 的返回（provider.SignInState 的宽松读取）。
struct PluginSignInStateDTO: Codable, Sendable {
    var id: String?
    var agent: String?
    var url: String?
    var code: String?
    var state: String?
    var pasteCallback: Bool?
    var pasteCode: Bool?
    var pasteKey: Bool?
    var keysURL: String?
    var instructions: String?
    var opened: Bool?
    var installing: Bool?
    var user: String?
    var plan: String?
    var using: Bool?
    var again: Bool?
    var error: String?
    var canceled: Bool?

    enum CodingKeys: String, CodingKey {
        case id, agent, url, code, state
        case pasteCallback, pasteCode, pasteKey, keysURL, instructions
        case opened, installing, user, plan, using, again, error, canceled
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try? c.decodeIfPresent(String.self, forKey: .id)
        self.agent = try? c.decodeIfPresent(String.self, forKey: .agent)
        self.url = try? c.decodeIfPresent(String.self, forKey: .url)
        self.code = try? c.decodeIfPresent(String.self, forKey: .code)
        self.state = try? c.decodeIfPresent(String.self, forKey: .state)
        self.pasteCallback = try? c.decodeIfPresent(Bool.self, forKey: .pasteCallback)
        self.pasteCode = try? c.decodeIfPresent(Bool.self, forKey: .pasteCode)
        self.pasteKey = try? c.decodeIfPresent(Bool.self, forKey: .pasteKey)
        self.keysURL = try? c.decodeIfPresent(String.self, forKey: .keysURL)
        self.instructions = try? c.decodeIfPresent(String.self, forKey: .instructions)
        self.opened = try? c.decodeIfPresent(Bool.self, forKey: .opened)
        self.installing = try? c.decodeIfPresent(Bool.self, forKey: .installing)
        self.user = try? c.decodeIfPresent(String.self, forKey: .user)
        self.plan = try? c.decodeIfPresent(String.self, forKey: .plan)
        self.using = try? c.decodeIfPresent(Bool.self, forKey: .using)
        self.again = try? c.decodeIfPresent(Bool.self, forKey: .again)
        self.error = try? c.decodeIfPresent(String.self, forKey: .error)
        self.canceled = try? c.decodeIfPresent(Bool.self, forKey: .canceled)
    }
}

/// 添加 Provider 的保存请求。`new: true` 是官方 Add 的语义：
/// 分配一个新的 provider id，而不是覆盖同 id 的已有项。
struct ProviderSaveRequest: Encodable, Sendable {
    var id: String?
    var name: String?
    var preset: String?
    var key: String?
    var chat: String?
    var responses: String?
    var anthropic: String?
    var gemini: String?
    var baseAPI: String?
    var isNew: Bool
    var searches: Bool?
    var unredacted: Bool?
    var models: [String]? = nil
    var proxy: String? = nil
    var routing: String? = nil
    var affinity: String? = nil
    var sink: Bool? = nil
    var useFirst: Bool? = nil
    var noStandIn: Bool? = nil
    var maxConcurrency: Int? = nil
    var queueLimit: Int? = nil
    var queueWait: Int? = nil
    var maxRPM: Int? = nil
    var priceRate: Double? = nil
    var topUpRate: Double? = nil
    var connectAgents: Bool? = nil
    var from: String? = nil
    // 官方编辑器的高级字段
    var unlisted: Bool? = nil
    var noModels: Bool? = nil
    var bestInFamily: Bool? = nil
    var listOff: Bool? = nil
    var headers: [String: String]? = nil
    var extraBody: JSONValue? = nil
    var replyHeaders: [String]? = nil
    var passHeaders: [String]? = nil
    var insecureTLS: Bool? = nil
    var http1: Bool? = nil
    var socket: String? = nil
    var limitRestOff: Bool? = nil
    var passUserAgent: Bool? = nil
    var authHeader: String? = nil
    var nativeCompaction: Bool? = nil
    var passErrors: Bool? = nil
    var modelsURL: String? = nil
    var balanceURL: String? = nil
    var balancePath: String? = nil
    var balanceMethod: String? = nil
    var balanceToken: String? = nil
    var keysUrl: String? = nil
    var website: String? = nil
    var fallback: [String]? = nil
    var vertex: ProviderDTO.VertexDTO? = nil
    /// 官方 Add 的「从现有 Provider 复制」：被复制的来源 id。
    var copyOf: String? = nil
    var contexts: [String: Int]? = nil
    var outputs: [String: Int]? = nil

    enum CodingKeys: String, CodingKey {
        case id, name, preset, key, chat, responses, anthropic, gemini, baseAPI
        case isNew = "new"
        case searches, unredacted, models, proxy, routing, affinity, sink
        case useFirst, noStandIn, maxConcurrency, queueLimit, queueWait, maxRPM
        case priceRate, topUpRate, connectAgents, from
        case unlisted, noModels, bestInFamily, listOff
        case headers, extraBody, replyHeaders, passHeaders
        case insecureTLS, http1, socket, limitRestOff
        case passUserAgent, authHeader, nativeCompaction, passErrors
        case modelsURL, balanceURL, balancePath, balanceMethod, balanceToken
        case keysUrl, website, fallback, vertex, copyOf, contexts, outputs
    }

    /// 只发送编辑器里有确切值的键：nil 表示「沿用服务端原值」，
    /// 0 / 空数组等则是明确的清零语义（queue、priceRate、headers、models 等）。
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(id, forKey: .id)
        try c.encodeIfPresent(name, forKey: .name)
        try c.encodeIfPresent(preset, forKey: .preset)
        try c.encodeIfPresent(key, forKey: .key)
        try c.encodeIfPresent(chat, forKey: .chat)
        try c.encodeIfPresent(responses, forKey: .responses)
        try c.encodeIfPresent(anthropic, forKey: .anthropic)
        try c.encodeIfPresent(gemini, forKey: .gemini)
        try c.encodeIfPresent(baseAPI, forKey: .baseAPI)
        try c.encode(isNew, forKey: .isNew)
        try c.encodeIfPresent(searches, forKey: .searches)
        try c.encodeIfPresent(unredacted, forKey: .unredacted)
        try c.encodeIfPresent(models, forKey: .models)
        try c.encodeIfPresent(proxy, forKey: .proxy)
        try c.encodeIfPresent(routing, forKey: .routing)
        try c.encodeIfPresent(affinity, forKey: .affinity)
        try c.encodeIfPresent(sink, forKey: .sink)
        try c.encodeIfPresent(useFirst, forKey: .useFirst)
        try c.encodeIfPresent(noStandIn, forKey: .noStandIn)
        try c.encodeIfPresent(maxConcurrency, forKey: .maxConcurrency)
        try c.encodeIfPresent(queueLimit, forKey: .queueLimit)
        try c.encodeIfPresent(queueWait, forKey: .queueWait)
        try c.encodeIfPresent(maxRPM, forKey: .maxRPM)
        try c.encodeIfPresent(priceRate, forKey: .priceRate)
        try c.encodeIfPresent(topUpRate, forKey: .topUpRate)
        try c.encodeIfPresent(connectAgents, forKey: .connectAgents)
        try c.encodeIfPresent(from, forKey: .from)
        try c.encodeIfPresent(unlisted, forKey: .unlisted)
        try c.encodeIfPresent(noModels, forKey: .noModels)
        try c.encodeIfPresent(bestInFamily, forKey: .bestInFamily)
        try c.encodeIfPresent(listOff, forKey: .listOff)
        try c.encodeIfPresent(headers, forKey: .headers)
        try c.encodeIfPresent(extraBody, forKey: .extraBody)
        try c.encodeIfPresent(replyHeaders, forKey: .replyHeaders)
        try c.encodeIfPresent(passHeaders, forKey: .passHeaders)
        try c.encodeIfPresent(insecureTLS, forKey: .insecureTLS)
        try c.encodeIfPresent(http1, forKey: .http1)
        try c.encodeIfPresent(socket, forKey: .socket)
        try c.encodeIfPresent(limitRestOff, forKey: .limitRestOff)
        try c.encodeIfPresent(passUserAgent, forKey: .passUserAgent)
        try c.encodeIfPresent(authHeader, forKey: .authHeader)
        try c.encodeIfPresent(nativeCompaction, forKey: .nativeCompaction)
        try c.encodeIfPresent(passErrors, forKey: .passErrors)
        try c.encodeIfPresent(modelsURL, forKey: .modelsURL)
        try c.encodeIfPresent(balanceURL, forKey: .balanceURL)
        try c.encodeIfPresent(balancePath, forKey: .balancePath)
        try c.encodeIfPresent(balanceMethod, forKey: .balanceMethod)
        try c.encodeIfPresent(balanceToken, forKey: .balanceToken)
        try c.encodeIfPresent(keysUrl, forKey: .keysUrl)
        try c.encodeIfPresent(website, forKey: .website)
        try c.encodeIfPresent(fallback, forKey: .fallback)
        try c.encodeIfPresent(vertex, forKey: .vertex)
        try c.encodeIfPresent(copyOf, forKey: .copyOf)
        try c.encodeIfPresent(contexts, forKey: .contexts)
        try c.encodeIfPresent(outputs, forKey: .outputs)
    }
}

/// `POST /api/provider/key`：返回已保存的主 Key（仅本机回环可见）。
struct ProviderKeyResponseDTO: Codable, Sendable {
    var key: String?
}

/// 保存前拉取厂商模型目录：`POST /api/provider/list`（不落盘）。
struct ProviderListResponseDTO: Codable, Sendable {
    var models: [ProviderListedModelDTO]?
    var retrieval: Int?
}

struct ProviderListedModelDTO: Codable, Sendable, Identifiable, Hashable {
    var id: String
    var name: String?

    var displayName: String {
        guard let name, !name.isEmpty, name != id else { return id }
        return name
    }
}

/// 从厂商刷新模型列表：`POST /api/provider/models`。
struct ProviderRefreshModelsRequest: Encodable, Sendable {
    var id: String
    var typed: Bool
    var key: String?
    var chat: String?
    var responses: String?
    var anthropic: String?
    var gemini: String?
    var proxy: String?
}

struct ProviderRefreshModelsResponseDTO: Codable, Sendable {
    var count: Int?
    var dropped: [String]?
    var provider: ProviderDTO?
}

/// 模型级测试：`POST /api/provider/test` 带 `test: [...]`。
struct ProviderTestRequest: Encodable, Sendable {
    var id: String
    var account: String?
    var test: [String]?
    /// 本次测试的名字，供 `/api/provider/teststop` 停止。
    var run: String?
}

/// 余额查询：`POST /api/provider/balance`。
struct ProviderBalanceRequest: Encodable, Sendable {
    var id: String
}

struct ProviderBalanceResponseDTO: Codable, Sendable {
    var ok: Bool?
    var amount: String?
    var error: String?
    var looked: Bool?
    var found: String?
    var foundField: String?
    var undetected: Bool?
}

/// 添加表单在保存前检测某个 URL 支持哪些 API。
struct ProviderDetectRequest: Encodable, Sendable {
    var id: String
    var name: String?
    var preset: String?
    var key: String?
    var chat: String?
    var responses: String?
    var anthropic: String?
    var gemini: String?
    var base: String?
    var isNew: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, preset, key, chat, responses, anthropic, gemini, base
        case isNew = "new"
    }
}

/// Provider 操作请求体（开/关/测试/删除/保存）
struct ProviderActionRequest: Encodable, Sendable {
    var id: String
    var name: String?
    var key: String?
    var preset: String?
    var chat: String?
    var responses: String?
    var anthropic: String?
    var gemini: String?
    var baseAPI: String?
    var models: [String]?
    var new: Bool?
    var searches: Bool?
    var unredacted: Bool?
}

// MARK: - Provider 连通性测试
/// `POST /api/provider/test` 的真实返回：
/// `{ results: [{ protocol, ok, status, ms, model, error, queued, v1 }], provider }`。
struct ProviderTestResponseDTO: Codable, Sendable {
    var results: [ProviderTestResultDTO]
    var provider: ProviderDTO?

    enum CodingKeys: String, CodingKey { case results, provider }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.results = (try? c.decode([ProviderTestResultDTO].self, forKey: .results)) ?? []
        self.provider = try? c.decodeIfPresent(ProviderDTO.self, forKey: .provider)
    }
}

struct ProviderTestResultDTO: Codable, Sendable, Identifiable, Hashable {
    var account: String?
    var protocolName: String
    var ok: Bool?
    var status: Int?
    var ms: Int64?
    var model: String?
    var error: String?
    var queued: String?
    var v1: String?

    var id: String { "\(protocolName)-\(account ?? "")-\(model ?? "")" }

    var succeeded: Bool { ok ?? false }

    var protocolLabel: String {
        switch protocolName.lowercased() {
        case "chat": return "Chat Completions"
        case "responses": return "Responses"
        case "anthropic": return "Anthropic Messages"
        case "gemini": return "Gemini"
        case "decide": return "Decision API"
        default: return protocolName.capitalized
        }
    }

    enum CodingKeys: String, CodingKey {
        case account
        case protocolName = "protocol"
        case ok, status, ms, model, error, queued, v1
    }
}

/// `POST /api/provider/detect` 的返回：每种协议能否在这个 URL 上应答。
struct ProviderDetectResponseDTO: Codable, Sendable {
    var results: [ProviderDetectionDTO]

    enum CodingKeys: String, CodingKey { case results }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.results = (try? c.decode([ProviderDetectionDTO].self, forKey: .results)) ?? []
    }
}

struct ProviderDetectionDTO: Codable, Sendable, Identifiable, Hashable {
    var account: String?
    var protocolName: String
    var ok: Bool?
    var status: Int?
    var ms: Int64?
    var model: String?
    var error: String?
    var queued: String?
    var v1: String?
    var base: String?

    var id: String { "\(protocolName)-\(base ?? "")" }

    var succeeded: Bool { ok ?? false }

    var protocolLabel: String {
        switch protocolName.lowercased() {
        case "chat": return "Chat Completions"
        case "responses": return "Responses"
        case "anthropic": return "Anthropic Messages"
        case "gemini": return "Gemini"
        case "decide": return "Decision API"
        default: return protocolName.capitalized
        }
    }

    enum CodingKeys: String, CodingKey {
        case account
        case protocolName = "protocol"
        case ok, status, ms, model, error, queued, v1, base
    }
}
