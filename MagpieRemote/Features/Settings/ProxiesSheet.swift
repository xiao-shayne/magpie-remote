import SwiftUI

/// 命名代理管理（HTTP / HTTPS / SOCKS5 / SSH）：对齐 upstream Settings › Network › Proxies。
struct ProxiesSheet: View {
    let viewModel: SettingsViewModel

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    private var proxies: [SavedProxyDTO] {
        viewModel.settings?.proxies ?? app.state?.settings?.proxies ?? []
    }

    @State private var editingProxy: SavedProxyDTO?
    @State private var showingNew = false
    @State private var testingID: String?
    @State private var testResults: [String: ProxyTestResultDTO] = [:]
    @State private var localError: String?

    var body: some View {
        NavigationStack {
            List {
                if let localError {
                    Section {
                        Text(localError)
                            .font(.caption)
                            .foregroundStyle(MagpieTheme.red)
                    }
                }

                if proxies.isEmpty {
                    Section {
                        ContentUnavailableView(
                            String(localized: "暂无命名代理"),
                            systemImage: "network.badge.shield.half.filled",
                            description: Text(String(localized: "支持添加 HTTP、SOCKS5 或 SSH 隧道代理，供指定 Provider 选用。"))
                        )
                    }
                } else {
                    Section {
                        ForEach(proxies) { proxy in
                            proxyRow(proxy)
                        }
                    } header: {
                        Text(String(localized: "已保存的代理 (\(proxies.count))"))
                    }
                }
            }
            .navigationTitle(String(localized: "命名代理"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "完成")) { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingNew = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingNew) {
                ProxyEditorSheet(existing: nil, viewModel: viewModel)
            }
            .sheet(item: $editingProxy) { proxy in
                ProxyEditorSheet(existing: proxy, viewModel: viewModel)
            }
        }
    }

    private func proxyRow(_ proxy: SavedProxyDTO) -> some View {
        let test = testResults[proxy.id] ?? proxy.test
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(proxy.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MagpieTheme.textPrimary)
                MagpieStatusChip(
                    text: proxy.isSSH ? "SSH" : schemeLabel(proxy.url),
                    color: proxy.isSSH ? MagpieTheme.purple : MagpieTheme.cyan
                )
                Spacer()
                if testingID == proxy.id {
                    ProgressView().controlSize(.small)
                } else {
                    Button(String(localized: "测试")) {
                        runTest(proxy)
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(MagpieTheme.accent)
                }
            }

            Text(proxy.url)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(MagpieTheme.textMuted)
                .lineLimit(1)

            if let user = proxy.user, !user.isEmpty {
                HStack(spacing: 6) {
                    Text(String(localized: "用户：\(user)"))
                    if proxy.hasKey == true {
                        Text("· SSH Key")
                    }
                    if proxy.hasPass == true {
                        Text(proxy.isSSH && proxy.hasKey == true ? String(localized: "· 含口令") : String(localized: "· 含密码"))
                    }
                }
                .font(.caption2)
                .foregroundStyle(MagpieTheme.textMuted)
            }

            if let uses = proxy.uses, !uses.isEmpty {
                let names = uses.compactMap(\.displayLabel).joined(separator: "、")
                if !names.isEmpty {
                    Text(String(localized: "使用中：\(names)"))
                        .font(.caption2)
                        .foregroundStyle(MagpieTheme.textSecondary)
                        .lineLimit(2)
                }
            }

            if let test {
                testSummary(test)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            editingProxy = proxy
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                remove(proxy)
            } label: {
                Label(String(localized: "删除"), systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private func testSummary(_ test: ProxyTestResultDTO) -> some View {
        if test.ok {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(MagpieTheme.green)
                let parts = [
                    test.loc,
                    test.ip,
                    test.ms.map { "\($0)ms" }
                ].compactMap { $0 }.filter { !$0.isEmpty }
                Text(parts.isEmpty ? String(localized: "连接正常") : parts.joined(separator: " · "))
                    .font(.caption2)
                    .foregroundStyle(MagpieTheme.green)
            }
        } else {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(MagpieTheme.red)
                Text(test.error ?? test.why ?? String(localized: "测试失败"))
                    .font(.caption2)
                    .foregroundStyle(MagpieTheme.red)
                    .lineLimit(3)
            }
        }
    }

    private func schemeLabel(_ raw: String) -> String {
        let lower = raw.lowercased()
        if lower.hasPrefix("socks5") { return "SOCKS5" }
        if lower.hasPrefix("https://") { return "HTTPS" }
        return "HTTP"
    }

    private func runTest(_ proxy: SavedProxyDTO) {
        guard let client = app.client else { return }
        testingID = proxy.id
        localError = nil
        Task {
            defer { testingID = nil }
            if let result = await viewModel.testProxy(client: client, id: proxy.id) {
                testResults[proxy.id] = result
                if result.ok { MagpieHaptics.success() }
            } else {
                localError = viewModel.errorMessage
            }
        }
    }

    private func remove(_ proxy: SavedProxyDTO) {
        guard let client = app.client else { return }
        localError = nil
        Task {
            let ok = await viewModel.deleteProxy(client: client, id: proxy.id)
            if !ok {
                localError = viewModel.errorMessage
            }
        }
    }
}

/// 新建或编辑单个命名代理（支持 HTTP / SOCKS5 / SSH）。
private struct ProxyEditorSheet: View {
    let existing: SavedProxyDTO?
    let viewModel: SettingsViewModel

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var kind = "http"
    @State private var name = ""
    @State private var url = ""
    @State private var user = ""
    @State private var pass = ""
    @State private var sshKey = ""
    @State private var trustNewKey = false
    @State private var isWorking = false
    @State private var testResult: ProxyTestResultDTO?
    @State private var localError: String?
    @State private var primed = false

    private var isSSH: Bool {
        kind == "ssh" || url.lowercased().hasPrefix("ssh://")
    }

    private var normalizedURL: String {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if trimmed.contains("://") { return trimmed }
        return "\(kind)://\(trimmed)"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(String(localized: "协议类型"), selection: $kind) {
                        Text("HTTP").tag("http")
                        Text("SOCKS5").tag("socks5")
                        Text("SSH").tag("ssh")
                    }
                    .pickerStyle(.segmented)

                    TextField(String(localized: "代理名称 (例如 Tokyo VPS)"), text: $name)
                    TextField(
                        isSSH ? "203.0.113.5:22" : "127.0.0.1:7890",
                        text: $url
                    )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                } header: {
                    Text(String(localized: "基础信息"))
                } footer: {
                    Text(
                        isSSH
                            ? String(localized: "填写 SSH 服务器地址与端口（如 ssh://host:22）；magpie 会自动维护转发隧道。")
                            : String(localized: "支持 http://、https://、socks5://，省略协议时按上方所选补全。")
                    )
                }

                Section {
                    TextField(String(localized: "用户名\(isSSH ? "" : "（可选）")"), text: $user)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    SecureField(
                        isSSH && !sshKey.isEmpty
                            ? String(localized: "私钥口令（留空保持不变）")
                            : String(localized: "密码（留空保持不变）"),
                        text: $pass
                    )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                    if isSSH {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(String(localized: "SSH 私钥（可选，PEM/OpenSSH 格式）"))
                                .font(.caption)
                                .foregroundStyle(MagpieTheme.textMuted)
                            TextEditor(text: $sshKey)
                                .font(.system(size: 10.5, design: .monospaced))
                                .frame(minHeight: 88)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }

                        if existing?.hostKey?.isEmpty == false {
                            Toggle(String(localized: "信任新的服务器主机指纹"), isOn: $trustNewKey)
                                .tint(MagpieTheme.amber)
                        }
                    }
                } header: {
                    Text(String(localized: "认证凭据"))
                }

                Section {
                    Button {
                        testDraft()
                    } label: {
                        HStack {
                            Label(String(localized: "测试此代理"), systemImage: "bolt.horizontal.circle")
                            Spacer()
                            if isWorking {
                                ProgressView().controlSize(.small)
                            }
                        }
                    }
                    .disabled(isWorking || normalizedURL.isEmpty)

                    if let testResult {
                        if testResult.ok {
                            let info = [testResult.loc, testResult.ip, testResult.ms.map { "\($0)ms" }]
                                .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
                            Label(info.isEmpty ? String(localized: "连接成功") : info, systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(MagpieTheme.green)
                        } else {
                            VStack(alignment: .leading, spacing: 4) {
                                Label(testResult.error ?? testResult.why ?? String(localized: "连接失败"), systemImage: "xmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(MagpieTheme.red)
                                if let was = testResult.was, let now = testResult.now, !was.isEmpty, !now.isEmpty {
                                    Text(String(localized: "主机指纹已变更：旧 \(was) → 新 \(now)"))
                                        .font(.caption2)
                                        .foregroundStyle(MagpieTheme.amber)
                                }
                            }
                        }
                    }
                }

                if let localError {
                    Section {
                        Text(localError)
                            .font(.caption)
                            .foregroundStyle(MagpieTheme.red)
                    }
                }
            }
            .navigationTitle(existing == nil ? String(localized: "添加代理") : String(localized: "编辑代理"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "取消")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "保存")) {
                        save()
                    }
                    .disabled(isWorking || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || normalizedURL.isEmpty)
                }
            }
            .onAppear {
                guard !primed else { return }
                primed = true
                if let existing {
                    name = existing.name
                    url = existing.url
                    user = existing.user ?? ""
                    if existing.isSSH {
                        kind = "ssh"
                    } else if existing.url.lowercased().hasPrefix("socks5") {
                        kind = "socks5"
                    } else {
                        kind = "http"
                    }
                }
            }
        }
    }

    private func testDraft() {
        guard let client = app.client else { return }
        isWorking = true
        localError = nil
        testResult = nil
        let passValue: String? = pass.isEmpty ? nil : pass
        let keyValue: String? = sshKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : sshKey
        Task {
            defer { isWorking = false }
            if let res = await viewModel.testProxy(
                client: client,
                id: existing?.id ?? "",
                url: normalizedURL,
                user: user.trimmingCharacters(in: .whitespacesAndNewlines),
                pass: passValue,
                key: keyValue,
                trustNewKey: trustNewKey
            ) {
                testResult = res
            } else {
                localError = viewModel.errorMessage
            }
        }
    }

    private func save() {
        guard let client = app.client else { return }
        isWorking = true
        localError = nil
        let passValue: String? = pass.isEmpty ? nil : pass
        let keyValue: String? = sshKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : sshKey
        Task {
            let ok = await viewModel.saveProxy(
                client: client,
                id: existing?.id ?? "",
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                url: normalizedURL,
                user: user.trimmingCharacters(in: .whitespacesAndNewlines),
                pass: passValue,
                key: keyValue,
                trustNewKey: trustNewKey
            )
            isWorking = false
            if ok {
                dismiss()
            } else {
                localError = viewModel.errorMessage
            }
        }
    }
}
