import Foundation
import Observation

@Observable
@MainActor
final class SettingsViewModel {
    var settings: SettingsDTO?
    var updateStatus: UpdateStatusDTO?
    var isLoading = false
    var isSaving = false
    var isCheckingUpdate = false
    var isRestarting = false
    var actionNotice: String?
    var errorMessage: String?

    /// 缓存服务端最近一次 `/api/settings*` 原始 JSON，确保 `POST /api/settings` 合并写入不清空其他字段。
    private var rawSettingsJSON: Data?

    private func applySettingsResponse(_ data: Data) throws {
        let decoded = try JSONDecoder().decode(SettingsDTO.self, from: data)
        self.settings = decoded
        self.rawSettingsJSON = data
    }

    func load(client: MagpieAPIClient) async {
        isLoading = true
        errorMessage = nil
        do {
            let data = try await client.sendData(.get("/api/settings"))
            try applySettingsResponse(data)
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
        await loadUpdate(client: client, fresh: false)
    }

    func loadUpdate(client: MagpieAPIClient, fresh: Bool) async {
        do {
            let query = fresh ? [URLQueryItem(name: "fresh", value: "1")] : []
            self.updateStatus = try await client.send(
                .get("/api/update", query: query),
                as: UpdateStatusDTO.self
            )
        } catch {
            // 更新状态读取失败不阻断设置页
        }
    }

    func checkUpdate(client: MagpieAPIClient) async {
        isCheckingUpdate = true
        errorMessage = nil
        defer { isCheckingUpdate = false }
        do {
            self.updateStatus = try await client.send(
                .post("/api/update/check"),
                as: UpdateStatusDTO.self,
                timeout: 30
            )
            MagpieHaptics.success()
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func installUpdate(client: MagpieAPIClient, when: String = "") async {
        isCheckingUpdate = true
        errorMessage = nil
        actionNotice = nil
        defer { isCheckingUpdate = false }
        do {
            struct Body: Encodable { let when: String }
            let data = try await client.sendData(
                try Endpoint.post("/api/update/install", body: Body(when: when)),
                timeout: 60
            )
            if data.isEmpty {
                // state == "ready" 时服务端立即重启安装并返回 HTTP 204 No Content
                actionNotice = String(localized: "服务端正在重启并应用更新，请稍候重新连接。")
            } else {
                self.updateStatus = try JSONDecoder().decode(UpdateStatusDTO.self, from: data)
                actionNotice = String(localized: "已请求服务端下载/安装更新")
            }
            MagpieHaptics.success()
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func restartServer(client: MagpieAPIClient) async -> Bool {
        isRestarting = true
        errorMessage = nil
        defer { isRestarting = false }
        do {
            struct Body: Encodable { let view: String }
            _ = try await client.sendData(
                try Endpoint.post("/api/restart", body: Body(view: "")),
                timeout: 15
            )
            actionNotice = String(localized: "已发送重启指令，请稍候重新连接。")
            MagpieHaptics.success()
            return true
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    /// Codex 提示词建议模型（`POST /api/settings/codex-suggestions`）。
    func setCodexSuggestions(client: MagpieAPIClient, model: String) async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            struct Body: Encodable { let Model: String }
            let data = try await client.sendData(
                try Endpoint.post("/api/settings/codex-suggestions", body: Body(Model: model))
            )
            try applySettingsResponse(data)
            MagpieHaptics.success()
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// 网关暴露裸模型 ID（`POST /api/settings/bare-ids`）。
    func setBareModelIDs(client: MagpieAPIClient, on: Bool, only: Bool) async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            struct Body: Encodable {
                let On: Bool
                let Only: Bool
            }
            let data = try await client.sendData(
                try Endpoint.post("/api/settings/bare-ids", body: Body(On: on, Only: on ? only : false))
            )
            try applySettingsResponse(data)
            MagpieHaptics.success()
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: - 命名代理（HTTP / SOCKS5 / SSH）

    func saveProxy(
        client: MagpieAPIClient,
        id: String,
        name: String,
        url: String,
        user: String,
        pass: String?,
        key: String?,
        trustNewKey: Bool
    ) async -> Bool {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            struct Body: Encodable {
                let id: String
                let name: String
                let url: String
                let user: String
                let pass: String?
                let key: String?
                let trustNewKey: Bool
            }
            let data = try await client.sendData(
                try Endpoint.post(
                    "/api/proxies/save",
                    body: Body(id: id, name: name, url: url, user: user, pass: pass, key: key, trustNewKey: trustNewKey)
                ),
                timeout: 45
            )
            try applySettingsResponse(data)
            MagpieHaptics.success()
            return true
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    func deleteProxy(client: MagpieAPIClient, id: String) async -> Bool {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            struct Body: Encodable { let id: String }
            let data = try await client.sendData(
                try Endpoint.post("/api/proxies/delete", body: Body(id: id))
            )
            try applySettingsResponse(data)
            MagpieHaptics.success()
            return true
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    func testProxy(
        client: MagpieAPIClient,
        id: String,
        url: String = "",
        user: String = "",
        pass: String? = nil,
        key: String? = nil,
        trustNewKey: Bool = false
    ) async -> ProxyTestResultDTO? {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            struct Body: Encodable {
                let id: String
                let url: String
                let user: String
                let pass: String?
                let key: String?
                let trustNewKey: Bool
            }
            return try await client.send(
                .post(
                    "/api/proxies/test",
                    body: Body(id: id, url: url, user: user, pass: pass, key: key, trustNewKey: trustNewKey)
                ),
                as: ProxyTestResultDTO.self,
                timeout: 45
            )
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            return nil
        }
    }

    /// Claude Code 的提示词缓存时长（knob：cache_ttl / subagent_cache_ttl）。
    func setClaudeCache(client: MagpieAPIClient, knob: String, value: String) async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            struct Body: Encodable {
                let Knob: String
                let Value: String
            }
            let data = try await client.sendData(
                try Endpoint.post("/api/settings/claude-cache", body: Body(Knob: knob, Value: value))
            )
            try applySettingsResponse(data)
            MagpieHaptics.success()
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// WebDAV 同步（官方 `/api/davsync`）：配置、立即同步、关闭、恢复。
    func davsync(client: MagpieAPIClient, action: String, body: [String: Any] = [:]) async -> JSONValue? {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        guard let data = try? JSONSerialization.data(withJSONObject: body) else {
            errorMessage = String(localized: "请求数据无效")
            return nil
        }
        do {
            let resData = try await client.sendData(
                Endpoint(path: "/api/davsync/\(action)", method: .post, body: data),
                timeout: 180
            )
            return try? JSONDecoder().decode(JSONValue.self, from: resData)
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            return nil
        }
    }

    /// 官方 Settings 的「导出备份」：写到 magpie 所在机器的 Downloads。
    func exportBackup(
        client: MagpieAPIClient,
        passphrase: String,
        includeKeys: Bool,
        includeSignIns: Bool,
        includeUsage: Bool = true
    ) async -> BackupExportResultDTO? {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            struct Body: Encodable {
                let Pass: String
                let Keys: Bool
                let SignIns: Bool
                let Usage: Bool
            }
            return try await client.send(
                .post(
                    "/api/backup/export",
                    body: Body(Pass: passphrase, Keys: includeKeys, SignIns: includeSignIns, Usage: includeUsage)
                ),
                as: BackupExportResultDTO.self,
                timeout: 180
            )
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            return nil
        }
    }

    func update<V: Encodable & Sendable>(client: MagpieAPIClient, key: String, value: V) async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            let patched = try await client.patchSettings(key: key, value: value, baseJSON: rawSettingsJSON)
            self.settings = patched.settings
            self.rawSettingsJSON = patched.rawJSON
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}

/// 类型擦除的 Encodable 辅助结构
struct AnyEncodable: Encodable, Sendable {
    private let _encode: @Sendable (Encoder) throws -> Void

    init<T: Encodable & Sendable>(_ wrapped: T) {
        _encode = { encoder in
            try wrapped.encode(to: encoder)
        }
    }

    func encode(to encoder: Encoder) throws {
        try _encode(encoder)
    }
}
