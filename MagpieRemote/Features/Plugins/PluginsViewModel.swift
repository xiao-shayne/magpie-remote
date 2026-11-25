import Foundation
import Observation

@Observable
@MainActor
final class PluginsViewModel {
    var plugins: [PluginEntryDTO] = []
    var leftovers: [PluginLeftoverDTO] = []
    var listings: [PluginListingDTO] = []
    var searchHits: [PluginSearchHitDTO] = []
    var updates: PluginUpdatesDTO?
    var hasBun = false
    var bunVersion: String?
    var isMirrorOn = false
    var registry: PluginRegistryDTO?
    var isLoading = false
    var isOperating = false
    var installingSpec: String?
    var errorMessage: String?
    var lastAction: String?

    // MARK: - 已安装
    func load(client: MagpieAPIClient) async {
        isLoading = true
        errorMessage = nil
        do {
            apply(try await client.send(.get("/api/plugins"), as: PluginsResponseDTO.self, timeout: 90))
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
    }

    func apply(_ state: PluginsResponseDTO) {
        self.plugins = state.plugins
        self.leftovers = state.leftovers ?? []
        self.hasBun = state.bun ?? false
        self.bunVersion = state.bunVersion
        self.isMirrorOn = state.mirror ?? false
        self.registry = state.registry
        if let err = state.error, !err.isEmpty {
            self.errorMessage = err
        }
    }

    // MARK: - 商店
    func loadMarket(client: MagpieAPIClient) async {
        isLoading = true
        errorMessage = nil
        do {
            let market: PluginMarketResponseDTO = try await client.send(
                .get("/api/plugins/market"),
                as: PluginMarketResponseDTO.self,
                timeout: 90
            )
            self.listings = market.listings
            if let state = market.state {
                apply(state)
            }
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
    }

    func loadUpdates(client: MagpieAPIClient) async {
        do {
            updates = try await client.send(.get("/api/plugins/updates"), as: PluginUpdatesDTO.self)
        } catch {
            // 更新检查失败不覆盖主列表错误
        }
    }

    func search(client: MagpieAPIClient, query: String) async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else {
            searchHits = []
            return
        }
        isOperating = true
        errorMessage = nil
        defer { isOperating = false }
        do {
            let result: PluginSearchResponseDTO = try await client.send(
                .get("/api/plugins/search", query: [URLQueryItem(name: "q", value: q)]),
                as: PluginSearchResponseDTO.self,
                timeout: 30
            )
            searchHits = result.hits
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: - 安装 / 更新 / 删除
    func install(client: MagpieAPIClient, spec: String) async -> Bool {
        await mutate(client: client, path: "/api/plugins/add", spec: spec, action: String(localized: "插件已安装"))
    }

    func upgrade(client: MagpieAPIClient, spec: String) async -> Bool {
        await mutate(client: client, path: "/api/plugins/upgrade", spec: spec, action: String(localized: "插件已更新"))
    }

    func updateAll(client: MagpieAPIClient) async -> Bool {
        isOperating = true
        installingSpec = nil
        errorMessage = nil
        defer { isOperating = false }
        do {
            let state: PluginsResponseDTO = try await client.send(
                .post("/api/plugins/update"),
                as: PluginsResponseDTO.self,
                timeout: 300
            )
            apply(state)
            lastAction = String(localized: "全部插件已更新")
            await loadUpdates(client: client)
            MagpieHaptics.success()
            return true
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    private func mutate(client: MagpieAPIClient, path: String, spec: String, action: String) async -> Bool {
        isOperating = true
        installingSpec = spec
        errorMessage = nil
        defer {
            isOperating = false
            installingSpec = nil
        }
        do {
            struct ActionBody: Encodable { var Spec: String }
            let state: PluginsResponseDTO = try await client.send(
                .post(path, body: ActionBody(Spec: spec)),
                as: PluginsResponseDTO.self,
                timeout: 300
            )
            apply(state)
            lastAction = action
            await loadUpdates(client: client)
            MagpieHaptics.success()
            return true
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    func toggle(client: MagpieAPIClient, spec: String, turnOn: Bool) async {
        isOperating = true
        errorMessage = nil
        defer { isOperating = false }
        do {
            struct OffBody: Encodable {
                var Spec: String
                var Off: Bool
            }
            let state: PluginsResponseDTO = try await client.send(
                .post("/api/plugins/off", body: OffBody(Spec: spec, Off: !turnOn)),
                as: PluginsResponseDTO.self
            )
            apply(state)
            MagpieHaptics.light()
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func remove(client: MagpieAPIClient, spec: String) async {
        isOperating = true
        errorMessage = nil
        defer { isOperating = false }
        do {
            struct RemoveBody: Encodable { var Spec: String }
            let state: PluginsResponseDTO = try await client.send(
                .post("/api/plugins/remove", body: RemoveBody(Spec: spec)),
                as: PluginsResponseDTO.self,
                timeout: 300
            )
            apply(state)
            await loadUpdates(client: client)
            MagpieHaptics.success()
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// 清理安装失败残留的未注册依赖包（`POST /api/plugins/leftover`）。
    func dropLeftover(client: MagpieAPIClient, spec: String) async {
        isOperating = true
        errorMessage = nil
        defer { isOperating = false }
        do {
            struct LeftoverBody: Encodable { var Spec: String }
            let state: PluginsResponseDTO = try await client.send(
                .post("/api/plugins/leftover", body: LeftoverBody(Spec: spec)),
                as: PluginsResponseDTO.self,
                timeout: 120
            )
            apply(state)
            lastAction = String(localized: "已清理残留依赖包")
            MagpieHaptics.success()
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func checkUpdates(client: MagpieAPIClient) async {
        isOperating = true
        errorMessage = nil
        defer { isOperating = false }
        do {
            _ = try await client.sendData(Endpoint.post("/api/plugins/check"), timeout: 120)
            await load(client: client)
            await loadUpdates(client: client)
            MagpieHaptics.success()
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: - 设置
    func setMirror(client: MagpieAPIClient, enable: Bool) async {
        isOperating = true
        defer { isOperating = false }
        do {
            struct MirrorBody: Encodable { var On: Bool }
            _ = try await client.sendData(try Endpoint.post("/api/plugins/mirror", body: MirrorBody(On: enable)))
            isMirrorOn = enable
            MagpieHaptics.success()
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func setRegistry(client: MagpieAPIClient, url: String) async {
        isOperating = true
        defer { isOperating = false }
        do {
            struct RegistryBody: Encodable { var URL: String }
            _ = try await client.sendData(try Endpoint.post("/api/plugins/registry", body: RegistryBody(URL: url)))
            let state: PluginsResponseDTO = try await client.send(.get("/api/plugins"), as: PluginsResponseDTO.self)
            registry = state.registry
            MagpieHaptics.success()
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// 保存 / 清除插件的运行选项（官方 `/api/plugins/options`）。
    func setOptions(client: MagpieAPIClient, spec: String, options: JSONValue?) async {
        isOperating = true
        errorMessage = nil
        defer { isOperating = false }
        do {
            struct Body: Encodable {
                let spec: String
                let options: JSONValue?
            }
            let state: PluginsResponseDTO = try await client.send(
                .post("/api/plugins/options", body: Body(spec: spec, options: options)),
                as: PluginsResponseDTO.self
            )
            apply(state)
            lastAction = options == nil ? String(localized: "选项已清除") : String(localized: "选项已保存")
            MagpieHaptics.success()
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// 指定某 Provider 由这个插件运行（官方 `/api/plugins/prefer`）。
    func prefer(client: MagpieAPIClient, spec: String, provider: String) async {
        isOperating = true
        errorMessage = nil
        defer { isOperating = false }
        do {
            struct Body: Encodable {
                let spec: String
                let provider: String
            }
            let state: PluginsResponseDTO = try await client.send(
                .post("/api/plugins/prefer", body: Body(spec: spec, provider: provider)),
                as: PluginsResponseDTO.self
            )
            apply(state)
            lastAction = String(localized: "已切换提供方")
            MagpieHaptics.success()
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: - 查询
    var installedSpecs: Set<String> {
        Set(plugins.map(\.spec))
    }

    func isInstalled(_ listing: PluginListingDTO) -> Bool {
        isInstalled(packageName: listing.packageName)
    }

    func isInstalled(packageName: String) -> Bool {
        installedSpecs.contains(packageName)
            || plugins.contains { $0.packageName == packageName || $0.spec == packageName }
    }

    var availableUpdates: [PluginEntryDTO] {
        plugins.filter { $0.hasUpdate }
    }

    var pendingWaits: [PluginWaitingDTO] {
        updates?.waiting ?? []
    }
}
