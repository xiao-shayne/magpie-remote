import Foundation

/// 单个 magpie 连接的 API 客户端。
///
/// 鉴权：用 Web Key 走 `GET /?k=` 换取 Cookie `magpie_web_<port>`；
/// 遇 401 自动重新登录并重试。原生客户端配置标准 User-Agent 以通过 Cloudflare 反代防护。
final class MagpieAPIClient: Sendable {
    let baseURL: URL
    private let key: String
    private let session: URLSession
    private let decoder: JSONDecoder
    private static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1 MagpieRemote/1.0"

    /// `tlsMaterial` 非空时，会话用专用 delegate 出示客户端证书并以 CA 校验服务端。
    init(baseURL: URL, key: String, tlsMaterial: ClientTLSMaterial? = nil) {
        self.baseURL = baseURL
        self.key = key
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.httpShouldSetCookies = true
        config.httpCookieAcceptPolicy = .always
        config.timeoutIntervalForRequest = 30
        config.waitsForConnectivity = false
        if let tlsMaterial {
            let delegate = MagpieTLSSessionDelegate(material: tlsMaterial)
            self.session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        } else {
            self.session = URLSession(configuration: config)
        }
        self.decoder = JSONDecoder()
    }

    // MARK: - 鉴权

    /// 用 Web Key 登录：`GET /?k=<key>` → 服务器种 Cookie 并重定向到主页。
    func signIn() async throws {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.path = "/"
        components?.queryItems = [URLQueryItem(name: "k", value: key)]
        guard let url = components?.url else { throw APIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")

        let (_, response) = try await perform(request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidURL }

        // 提取并保存所有 Set-Cookie
        Self.saveCookies(from: http, for: baseURL)

        if http.statusCode == 401 { throw APIError.unauthorized }
        guard (200...399).contains(http.statusCode) else {
            throw APIError.http(status: http.statusCode, message: "")
        }
    }

    /// 当前是否已持有登录 Cookie。
    var hasCookie: Bool {
        let cookies = HTTPCookieStorage.shared.cookies(for: baseURL) ?? []
        return cookies.contains { $0.name.hasPrefix("magpie_web_") }
    }

    // MARK: - 请求

    /// 发送请求并解码为 `T`；遇 401 自动重登一次。
    func send<T: Decodable>(_ endpoint: Endpoint, as type: T.Type = T.self) async throws -> T {
        let data = try await sendData(endpoint)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            #if DEBUG
            print("[MagpieAPIClient] 解码 \(T.self) 失败: \(error)")
            #endif
            throw APIError.from(decodingError: error)
        }
    }

    /// 长耗时请求的解码版本。
    func send<T: Decodable>(_ endpoint: Endpoint, as type: T.Type = T.self, timeout: TimeInterval) async throws -> T {
        let data = try await sendData(endpoint, timeout: timeout)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            #if DEBUG
            print("[MagpieAPIClient] 解码 \(T.self) 失败: \(error)")
            #endif
            throw APIError.from(decodingError: error)
        }
    }

    /// 发送请求并返回原始数据；遇 401 自动重登一次。
    func sendData(_ endpoint: Endpoint) async throws -> Data {
        do {
            return try await performAuthorized(endpoint, timeout: nil)
        } catch let error as APIError where error == .unauthorized {
            try await signIn()
            return try await performAuthorized(endpoint, timeout: nil)
        }
    }

    /// 长耗时请求（安装/更新插件、首次下载 Bun 等）。
    /// 单独指定请求超时，避免默认 30 秒提前放弃，而服务器仍在继续执行。
    func sendData(_ endpoint: Endpoint, timeout: TimeInterval) async throws -> Data {
        do {
            return try await performAuthorized(endpoint, timeout: timeout)
        } catch let error as APIError where error == .unauthorized {
            try await signIn()
            return try await performAuthorized(endpoint, timeout: timeout)
        }
    }

    private func performAuthorized(_ endpoint: Endpoint, timeout: TimeInterval?) async throws -> Data {
        let request = try makeRequest(endpoint, timeout: timeout)
        let (data, response) = try await perform(request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidURL }

        // 保存响应中返回的 Cookie
        Self.saveCookies(from: http, for: baseURL)

        switch http.statusCode {
        case 200...299:
            return data
        case 401:
            throw APIError.unauthorized
        case 403:
            throw APIError.forbidden
        default:
            throw APIError.http(status: http.statusCode, message: Self.errorMessage(from: data))
        }
    }

    private func makeRequest(_ endpoint: Endpoint, timeout: TimeInterval?) throws -> URLRequest {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL
        }
        components.path = endpoint.path
        if !endpoint.query.isEmpty { components.queryItems = endpoint.query }
        guard let url = components.url else { throw APIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        request.httpBody = endpoint.body
        if let timeout {
            request.timeoutInterval = timeout
        }
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        if endpoint.body != nil {
            request.setValue(endpoint.contentType, forHTTPHeaderField: "Content-Type")
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let cookies = HTTPCookieStorage.shared.cookies(for: url), !cookies.isEmpty {
            let headerDict = HTTPCookie.requestHeaderFields(with: cookies)
            for (field, value) in headerDict {
                request.setValue(value, forHTTPHeaderField: field)
            }
        }
        return request
    }

    private func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch let error as URLError where error.code == .notConnectedToInternet || error.code == .networkConnectionLost {
            throw APIError.offline
        } catch {
            throw APIError.transport(error.localizedDescription)
        }
    }

    private static func saveCookies(from response: HTTPURLResponse, for url: URL) {
        var headerFields: [String: String] = [:]
        for (k, v) in response.allHeaderFields {
            if let key = k as? String, let val = v as? String {
                headerFields[key] = val
            }
        }
        let cookies = HTTPCookie.cookies(withResponseHeaderFields: headerFields, for: url)
        for cookie in cookies {
            HTTPCookieStorage.shared.setCookie(cookie)
        }
    }

    private static func errorMessage(from data: Data) -> String {
        struct ErrorEnvelope: Decodable {
            let error: String?
            let detail: String?
        }
        if let obj = try? JSONDecoder().decode(ErrorEnvelope.self, from: data),
           let message = obj.error, !message.isEmpty {
            return message
        }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    // MARK: - Settings 安全合并写入

    /// 将单个设置项合并到服务端最新的 `/api/settings` 完整 JSON 对象中。
    ///
    /// upstream `POST /api/settings` 通过 `settingsapi.Apply` 解析整份 `settings.Settings`，
    /// 省略的 `settingsapi.Keys` 字段会被重置为零值；因此修改单个字段前必须基于完整配置合并，
    /// 并移除 `settingsJSON` 中仅用于展示且覆盖原字段类型的只读 `proxies` 字段。
    static func mergedSettingsBody<V: Encodable>(baseJSON: Data, key: String, value: V) throws -> Data {
        guard var dict = try JSONSerialization.jsonObject(with: baseJSON) as? [String: Any] else {
            throw APIError.decoding("无法解析当前服务端设置对象")
        }
        dict.removeValue(forKey: "proxies")
        let encodedValue = try JSONEncoder().encode(value)
        let jsonValue = try JSONSerialization.jsonObject(with: encodedValue, options: .fragmentsAllowed)
        dict[key] = jsonValue
        return try JSONSerialization.data(withJSONObject: dict)
    }

    /// 基于当前服务端完整设置安全更新单个字段，并返回最新的 `SettingsDTO` 与原始 JSON。
    func patchSettings<V: Encodable & Sendable>(
        key: String,
        value: V,
        baseJSON: Data? = nil
    ) async throws -> (settings: SettingsDTO, rawJSON: Data) {
        let base: Data
        if let baseJSON {
            base = baseJSON
        } else {
            base = try await sendData(.get("/api/settings"))
        }
        let body = try Self.mergedSettingsBody(baseJSON: base, key: key, value: value)
        let responseData = try await sendData(Endpoint(path: "/api/settings", method: .post, body: body))
        do {
            let decoded = try decoder.decode(SettingsDTO.self, from: responseData)
            return (decoded, responseData)
        } catch {
            throw APIError.from(decodingError: error)
        }
    }
}
