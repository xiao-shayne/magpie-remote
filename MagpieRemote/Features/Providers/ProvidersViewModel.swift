import Foundation
import Observation

@Observable
@MainActor
final class ProvidersViewModel {
    var providers: [ProviderDTO] = []
    var presets: [PresetDTO] = []
    /// 插件提供的订阅（Add 面板的 plugin subs）。
    var plugins: [PluginSubDTO] = []
    /// 已下架但仍在启用的旧插件迁移提示。
    var withdrawn: [WithdrawnPluginDTO] = []
    var isLoading = false
    var errorMessage: String?
    var testResult: String?
    var isOperating = false

    func load(client: MagpieAPIClient) async {
        isLoading = true
        errorMessage = nil
        do {
            let res = try await client.send(.get("/api/providers"), as: ProvidersResponseDTO.self)
            self.providers = res.providers
            self.presets = res.presets ?? []
            self.plugins = res.plugins ?? []
            self.withdrawn = res.withdrawn ?? []
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
    }

    func toggle(client: MagpieAPIClient, id: String, turnOn: Bool) async {
        isOperating = true
        defer { isOperating = false }
        let action = turnOn ? "on" : "off"
        do {
            struct ActionBody: Encodable {
                let id: String
            }
            _ = try await client.sendData(try .post("/api/provider/\(action)", body: ActionBody(id: id)))
            if let idx = providers.firstIndex(where: { $0.id == id }) {
                providers[idx].off = !turnOn
            }
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func delete(client: MagpieAPIClient, id: String) async -> Bool {
        isOperating = true
        defer { isOperating = false }
        do {
            struct DeleteBody: Encodable {
                let id: String
            }
            _ = try await client.sendData(try .post("/api/provider/delete", body: DeleteBody(id: id)))
            providers.removeAll { $0.id == id }
            return true
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    func testResults(
        client: MagpieAPIClient,
        id: String,
        account: String? = nil,
        models: [String]? = nil,
        run: String? = nil
    ) async -> ProviderTestResponseDTO? {
        isOperating = true
        defer { isOperating = false }
        do {
            let response: ProviderTestResponseDTO = try await client.send(
                .post(
                    "/api/provider/test",
                    body: ProviderTestRequest(id: id, account: account, test: models, run: run)
                ),
                as: ProviderTestResponseDTO.self,
                timeout: 300
            )
            testResult = nil
            return response
        } catch {
            testResult = (error as? APIError)?.errorDescription ?? error.localizedDescription
            return nil
        }
    }

    /// 停止一次进行中的测试（官方 `/api/provider/teststop`）。
    func stopTest(client: MagpieAPIClient, run: String) async {
        guard !run.isEmpty else { return }
        do {
            struct Body: Encodable { let run: String }
            _ = try await client.sendData(
                try Endpoint.post("/api/provider/teststop", body: Body(run: run))
            )
        } catch {
            // 停止失败不覆盖测试结果
        }
    }

    /// 中转站质量实测（官方 `POST /api/relay-check`）：验证准确性、工具调用与输出速度。
    func checkRelay(client: MagpieAPIClient, provider: String, model: String) async -> RelayCheckResultDTO? {
        isOperating = true
        errorMessage = nil
        defer { isOperating = false }
        do {
            struct Body: Encodable { let provider: String; let model: String }
            let result: RelayCheckResultDTO = try await client.send(
                .post("/api/relay-check", body: Body(provider: provider, model: model)),
                as: RelayCheckResultDTO.self,
                timeout: 180
            )
            return result
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            return nil
        }
    }

    /// 重新检测 Claude 订阅账号的出口地区（官方 `POST /api/egress/check`）。
    func checkEgress(client: MagpieAPIClient) async -> EgressResultDTO? {
        isOperating = true
        errorMessage = nil
        defer { isOperating = false }
        do {
            let result: EgressResultDTO = try await client.send(
                .post("/api/egress/check"),
                as: EgressResultDTO.self,
                timeout: 30
            )
            await load(client: client)
            return result
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            return nil
        }
    }

    /// 从厂商重新拉取模型列表（可带编辑中的草稿端点与 Key）。
    func refreshModels(
        client: MagpieAPIClient,
        id: String,
        key: String,
        chat: String,
        responses: String,
        anthropic: String,
        gemini: String,
        proxy: String
    ) async -> ProviderRefreshModelsResponseDTO? {
        isOperating = true
        errorMessage = nil
        defer { isOperating = false }
        do {
            let request = ProviderRefreshModelsRequest(
                id: id,
                typed: true,
                key: key.isEmpty ? nil : key,
                chat: chat.isEmpty ? nil : chat,
                responses: responses.isEmpty ? nil : responses,
                anthropic: anthropic.isEmpty ? nil : anthropic,
                gemini: gemini.isEmpty ? nil : gemini,
                proxy: proxy.isEmpty ? nil : proxy
            )
            let response: ProviderRefreshModelsResponseDTO = try await client.send(
                .post("/api/provider/models", body: request),
                as: ProviderRefreshModelsResponseDTO.self,
                timeout: 180
            )
            await load(client: client)
            return response
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            return nil
        }
    }

    func checkBalance(client: MagpieAPIClient, id: String) async -> ProviderBalanceResponseDTO? {
        isOperating = true
        errorMessage = nil
        defer { isOperating = false }
        do {
            return try await client.send(
                .post("/api/provider/balance", body: ProviderBalanceRequest(id: id)),
                as: ProviderBalanceResponseDTO.self,
                timeout: 30
            )
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            return nil
        }
    }

    func detect(client: MagpieAPIClient, request: ProviderDetectRequest) async -> ProviderDetectResponseDTO? {
        isOperating = true
        errorMessage = nil
        defer { isOperating = false }
        do {
            return try await client.send(
                .post("/api/provider/detect", body: request),
                as: ProviderDetectResponseDTO.self
            )
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            return nil
        }
    }

    func save(client: MagpieAPIClient, request: ProviderSaveRequest) async -> Bool {
        isOperating = true
        errorMessage = nil
        defer { isOperating = false }
        do {
            _ = try await client.sendData(try Endpoint.post("/api/provider/save", body: request))
            await load(client: client)
            return true
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    // MARK: - 插件订阅登录
    /// 插件登录的一步（官方 `/api/plugin-signin/prompt`）。
    func pluginPrompt(
        client: MagpieAPIClient,
        provider: String,
        method: Int,
        inputs: [String: String],
        key: String? = nil,
        value: String? = nil
    ) async -> PluginPromptResponseDTO? {
        var body: [String: Any] = [
            "provider": provider,
            "method": method,
            "inputs": inputs
        ]
        if let key { body["key"] = key }
        if let value { body["value"] = value }
        guard let data = try? JSONSerialization.data(withJSONObject: body) else {
            errorMessage = String(localized: "请求数据无效")
            return nil
        }
        isOperating = true
        errorMessage = nil
        defer { isOperating = false }
        do {
            let resData = try await client.sendData(
                Endpoint(path: "/api/plugin-signin/prompt", method: .post, body: data),
                timeout: 60
            )
            return try? JSONDecoder().decode(PluginPromptResponseDTO.self, from: resData)
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            return nil
        }
    }

    /// 发起插件登录（官方 `/api/plugin-signin`）。
    func pluginSignIn(
        client: MagpieAPIClient,
        provider: String,
        method: Int,
        inputs: [String: String],
        key: String? = nil,
        proxy: String? = nil,
        user: String? = nil
    ) async -> PluginSignInStateDTO? {
        var body: [String: Any] = [
            "provider": provider,
            "method": method,
            "inputs": inputs
        ]
        if let key { body["key"] = key }
        if let proxy { body["proxy"] = proxy }
        if let user { body["user"] = user }
        guard let data = try? JSONSerialization.data(withJSONObject: body) else {
            errorMessage = String(localized: "请求数据无效")
            return nil
        }
        isOperating = true
        errorMessage = nil
        defer { isOperating = false }
        do {
            let resData = try await client.sendData(
                Endpoint(path: "/api/plugin-signin", method: .post, body: data),
                timeout: 120
            )
            return try? JSONDecoder().decode(PluginSignInStateDTO.self, from: resData)
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            return nil
        }
    }

    // MARK: - 多密钥
    func addKey(
        client: MagpieAPIClient,
        id: String,
        name: String,
        key: String,
        protocolName: String? = nil,
        weight: Int? = nil,
        plan: String? = nil
    ) async -> Bool {
        var body: [String: Any] = ["Name": name, "Key": key]
        if let protocolName, !protocolName.isEmpty { body["Protocol"] = protocolName }
        if let weight, weight > 0 { body["Weight"] = weight }
        if let plan, !plan.isEmpty { body["Plan"] = plan }
        return await keyAction(client: client, path: "/api/keys/add", id: id, body: body)
    }

    func importKeys(client: MagpieAPIClient, id: String, keys: String) async -> Bool {
        await keyAction(client: client, path: "/api/keys/import", id: id, body: ["Key": keys])
    }

    /// 保存 Provider 的展示/路由顺序（官方 `/api/providers/arrange`）。
    func arrange(client: MagpieAPIClient, order: [String]) async -> Bool {
        isOperating = true
        errorMessage = nil
        defer { isOperating = false }
        do {
            struct Body: Encodable { let order: [String] }
            _ = try await client.sendData(try Endpoint.post("/api/providers/arrange", body: Body(order: order)))
            await load(client: client)
            MagpieHaptics.success()
            return true
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    /// 保存前向厂商拉取模型列表（官方 Add 表单的 Fetch models），不写入任何配置。
    func previewModels(client: MagpieAPIClient, request: ProviderSaveRequest) async -> ProviderListResponseDTO? {
        isOperating = true
        errorMessage = nil
        defer { isOperating = false }
        do {
            return try await client.send(
                .post("/api/provider/list", body: request),
                as: ProviderListResponseDTO.self,
                timeout: 60
            )
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            return nil
        }
    }

    /// 读取已保存的主 Key（官方编辑器的 Show）。
    func revealKey(client: MagpieAPIClient, id: String) async -> String? {
        isOperating = true
        defer { isOperating = false }
        do {
            let response: ProviderKeyResponseDTO = try await client.send(
                .post("/api/provider/key", body: ProviderKeyRequest(id: id)),
                as: ProviderKeyResponseDTO.self
            )
            return response.key
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            return nil
        }
    }

    private struct ProviderKeyRequest: Encodable {
        let id: String
    }

    /// 忘记厂商模型列表（官方 editor 的 Forget list），下次刷新重新拉取。
    func forgetModelList(client: MagpieAPIClient, id: String) async -> Bool {
        isOperating = true
        errorMessage = nil
        defer { isOperating = false }
        do {
            _ = try await client.sendData(
                try Endpoint.post("/api/provider/unfetch", body: ProviderKeyRequest(id: id))
            )
            await load(client: client)
            return true
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    /// 重命名模型（官方编辑器的模型改名动作）。
    func renameModel(client: MagpieAPIClient, providerID: String, model: String, name: String) async -> Bool {
        isOperating = true
        defer { isOperating = false }
        do {
            _ = try await client.sendData(
                try Endpoint.post(
                    "/api/provider/name",
                    body: RenameModelBody(id: providerID, model: model, modelName: name)
                )
            )
            await load(client: client)
            return true
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    private struct RenameModelBody: Encodable {
        let id: String
        let model: String
        let modelName: String
    }

    func setUseFirst(client: MagpieAPIClient, id: String, on: Bool) async {
        await simpleAction(client: client, path: "/api/provider/usefirst", body: ["id": id, "useFirst": on])
    }

    func setStandIn(client: MagpieAPIClient, id: String, noStandIn: Bool) async {
        await simpleAction(client: client, path: "/api/provider/standin", body: ["id": id, "noStandIn": noStandIn])
    }

    /// 订阅账号：保持登录在固定账号 / 只切换登录 / 自动重启 Codex App。
    func setKeepLogin(client: MagpieAPIClient, id: String, on: Bool, keepAs: String?) async {
        var body: [String: Any] = ["id": id, "keepLogin": on]
        if let keepAs, !keepAs.isEmpty { body["keepLoginAs"] = keepAs }
        await simpleAction(client: client, path: "/api/provider/keeplogin", body: body)
    }

    func setSwitchOnly(client: MagpieAPIClient, id: String, on: Bool) async {
        await simpleAction(client: client, path: "/api/provider/switchonly", body: ["id": id, "switchOnly": on])
    }

    func setRestartApp(client: MagpieAPIClient, id: String, on: Bool) async {
        await simpleAction(client: client, path: "/api/provider/restartapp", body: ["id": id, "restartApp": on])
    }

    /// 账号级设置：用量上限（百分比）、权重与并发上限。
    func setAccountCap(client: MagpieAPIClient, id: String, account: String, cap: Int) async {
        await simpleAction(
            client: client,
            path: "/api/provider/accountcap",
            body: ["id": id, "account": account, "cap": cap]
        )
    }

    func setAccountWeight(client: MagpieAPIClient, id: String, account: String, weight: Int) async {
        await simpleAction(
            client: client,
            path: "/api/provider/accountweight",
            body: ["id": id, "account": account, "weight": weight]
        )
    }

    func setAccountConcurrency(client: MagpieAPIClient, id: String, account: String, limit: Int) async {
        await simpleAction(
            client: client,
            path: "/api/provider/accountconcurrency",
            body: ["id": id, "account": account, "limit": limit]
        )
    }

    /// 在订阅记住的多个登录之间切换（官方 `/api/login/switch`）。
    func switchLogin(client: MagpieAPIClient, agent: String, user: String) async {
        isOperating = true
        errorMessage = nil
        defer { isOperating = false }
        do {
            _ = try await client.sendData(
                try Endpoint.post("/api/login/switch", body: LoginBody(Agent: agent, User: user))
            )
            await load(client: client)
            MagpieHaptics.success()
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    private struct LoginBody: Encodable {
        let Agent: String
        let User: String
    }

    /// 单个模型的推理档（官方 `efforts`）。
    func setModelEfforts(client: MagpieAPIClient, id: String, model: String, efforts: [String]) async -> Bool {
        await simpleActionResult(
            client: client,
            path: "/api/provider/efforts",
            body: ["id": id, "model": model, "efforts": efforts]
        )
    }

    /// 单个模型的图片能力（官方 `images`）。
    func setModelImages(client: MagpieAPIClient, id: String, model: String, images: Bool) async -> Bool {
        await simpleActionResult(
            client: client,
            path: "/api/provider/images",
            body: ["id": id, "model": model, "images": images]
        )
    }

    private func simpleActionResult(client: MagpieAPIClient, path: String, body: [String: Any]) async -> Bool {
        guard JSONSerialization.isValidJSONObject(body),
              let data = try? JSONSerialization.data(withJSONObject: body) else {
            errorMessage = String(localized: "请求数据无效")
            return false
        }
        isOperating = true
        errorMessage = nil
        defer { isOperating = false }
        do {
            _ = try await client.sendData(Endpoint(path: path, method: .post, body: data))
            await load(client: client)
            return true
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    private func simpleAction(client: MagpieAPIClient, path: String, body: [String: Any]) async {
        guard JSONSerialization.isValidJSONObject(body),
              let data = try? JSONSerialization.data(withJSONObject: body) else {
            return
        }
        isOperating = true
        defer { isOperating = false }
        do {
            _ = try await client.sendData(Endpoint(path: path, method: .post, body: data))
            await load(client: client)
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func removeKey(client: MagpieAPIClient, id: String, ref: String) async -> Bool {
        await keyAction(client: client, path: "/api/keys/remove", id: id, body: ["Ref": ref])
    }

    func toggleKey(client: MagpieAPIClient, id: String, ref: String, on: Bool) async -> Bool {
        await keyAction(
            client: client,
            path: on ? "/api/keys/on" : "/api/keys/off",
            id: id,
            body: ["Ref": ref]
        )
    }

    func useKey(client: MagpieAPIClient, id: String, ref: String) async -> Bool {
        await keyAction(client: client, path: "/api/keys/use", id: id, body: ["Ref": ref])
    }

    private func keyAction(client: MagpieAPIClient, path: String, id: String, body: [String: Any]) async -> Bool {
        var payload = body
        payload["ID"] = id
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload) else {
            errorMessage = String(localized: "请求数据无效")
            return false
        }
        isOperating = true
        errorMessage = nil
        defer { isOperating = false }
        do {
            _ = try await client.sendData(Endpoint(path: path, method: .post, body: data))
            await load(client: client)
            MagpieHaptics.success()
            return true
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    func addFromPreset(client: MagpieAPIClient, preset: PresetDTO, apiKey: String) async -> Bool {
        isOperating = true
        errorMessage = nil
        defer { isOperating = false }
        do {
            struct SaveBody: Encodable {
                let id: String
                let preset: String
                let key: String
                let name: String
            }
            let body = SaveBody(id: preset.id, preset: preset.id, key: apiKey, name: preset.name)
            _ = try await client.sendData(try .post("/api/provider/save", body: body))
            await load(client: client)
            return true
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }
}
