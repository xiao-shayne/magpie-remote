import SwiftUI
import UIKit

/// 网关调用密钥 (Caller Keys) 管理：1:1 对齐官方 Web / 客户端设计。
/// 支持新建 Key、管理密钥名称与管理员权限、控制局域网客户端访问。
struct GatewayView: View {
    @Environment(AppModel.self) private var app
    @State private var viewModel = GatewayViewModel()
    @State private var searchText = ""
    @State private var showCreateSheet = false
    @State private var newKeyName = ""
    @State private var newKeyIsAdmin = false
    @State private var newKeyIsReadOnly = false
    @State private var isCreating = false
    @State private var secretReveal: SecretReveal?
    @State private var limitTarget: GatewayLimitTarget?
    @State private var showingAccountGroups = false
    @State private var selectedCall: GatewayCallDTO?
    @State private var connectFlavor = "openai"
    @State private var connectModel = ""
    @State private var connectExpanded = true
    @State private var showingAllModels = false
    @State private var isCopiedSnippet = false

    private var filteredKeys: [GatewayKeyDTO] {
        if searchText.isEmpty { return viewModel.keys }
        return viewModel.keys.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText) ||
            $0.id.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        MagpieNavigationContainer {
            ScrollView {
                VStack(spacing: 16) {
                    if let error = viewModel.errorMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text(error)
                        }
                        .font(.subheadline)
                        .foregroundStyle(MagpieTheme.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .magpieCard()
                    }

                    statusCard
                    connectCard
                    modelsCard
                    callsCard

                    MagpieSectionLabel(
                        title: String(localized: "Gateway Keys"),
                        detail: "\(viewModel.keys.count)"
                    )

                    if filteredKeys.isEmpty {
                        emptyState
                    } else {
                        LazyVStack(spacing: 10) {
                            ForEach(filteredKeys) { key in
                                GatewayKeyCard(key: key, onToggle: { turnOn in
                                    if let client = app.client {
                                        Task { await viewModel.toggle(client: client, id: key.id, turnOn: turnOn) }
                                    }
                                }, onCopy: {
                                    reveal(key: key)
                                }, onRotate: {
                                    rotate(key: key)
                                }, onLimit: {
                                    limitTarget = GatewayLimitTarget(keyID: key.id, initialSlot: key.bindingLimitIndex)
                                }, onRouting: { routing in
                                    if let client = app.client {
                                        Task { _ = await viewModel.setRouting(client: client, keyID: key.id, routing: routing) }
                                    }
                                }, onMemory: { allow in
                                    if let client = app.client {
                                        Task { _ = await viewModel.setMemory(client: client, keyID: key.id, memory: allow) }
                                    }
                                }, onDelete: {
                                    if let client = app.client {
                                        Task { _ = await viewModel.delete(client: client, id: key.id) }
                                    }
                                })
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .magpiePageBackground()
            .searchable(text: $searchText, prompt: String(localized: "搜索网关 Key…"))
            .navigationTitle(String(localized: "Gateway Keys"))
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showCreateSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.body.weight(.semibold))
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            if let client = app.client {
                                Task { await viewModel.load(client: client) }
                            }
                        } label: {
                            Label(String(localized: "刷新"), systemImage: "arrow.clockwise")
                        }

                        Button {
                            showingAccountGroups = true
                        } label: {
                            Label(String(localized: "账户组…"), systemImage: "person.2.fill")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showingAccountGroups) {
                GatewayAccountGroupsSheet(viewModel: viewModel)
            }
            .sheet(isPresented: $showCreateSheet) {
                createKeySheet
            }
            .sheet(item: $secretReveal) { reveal in
                SecretRevealSheet(reveal: reveal)
            }
            .sheet(item: $limitTarget) { target in
                GatewayLimitEditorSheet(
                    keyID: target.keyID,
                    initialSlot: target.initialSlot,
                    viewModel: viewModel,
                    models: viewModel.models
                )
            }
            .overlay {
                if viewModel.isLoading && viewModel.keys.isEmpty {
                    ProgressView(String(localized: "加载网关 Key 列表…"))
                }
            }
            .task {
                if let client = app.client {
                    await viewModel.loadAll(client: client)
                }
            }
            .refreshable {
                if let client = app.client {
                    await viewModel.loadAll(client: client)
                }
            }
            .sheet(item: $selectedCall) { call in
                GatewayCallSheet(call: call) {
                    guard let client = app.client else { return nil }
                    return await viewModel.loadCall(client: client, id: call.id)
                }
            }
            .sheet(isPresented: $showingAllModels) {
                GatewayModelsSheet(models: viewModel.models)
            }
        }
    }

    // MARK: - 网关状态
    private var gatewayBase: String {
        let raw = viewModel.gateway?.url ?? app.activeURL?.absoluteString ?? "http://127.0.0.1:3425"
        return raw.hasSuffix("/") ? String(raw.dropLast()) : raw
    }

    private var statusCard: some View {
        VStack(spacing: 13) {
            HStack(spacing: 13) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: viewModel.gateway?.running == true
                                    ? [MagpieTheme.green, MagpieTheme.cyan]
                                    : [MagpieTheme.amber, MagpieTheme.red],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)
                    Image(systemName: "server.rack")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(String(localized: "本地网关"))
                            .font(.headline)
                            .foregroundStyle(MagpieTheme.textPrimary)
                        if viewModel.gateway?.running == true {
                            HStack(spacing: 4) {
                                MagpiePulseDot(color: MagpieTheme.green)
                                Text(String(localized: "运行中"))
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3.5)
                            .background(MagpieTheme.greenSoft, in: Capsule())
                            .foregroundStyle(MagpieTheme.green)
                        } else {
                            MagpieStatusChip(
                                text: String(localized: "未运行"),
                                color: MagpieTheme.amber
                            )
                        }
                        if viewModel.gateway?.paused == true {
                            MagpieStatusChip(text: String(localized: "已暂停"), color: MagpieTheme.amber)
                        }
                    }

                    Text(gatewayBase)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(MagpieTheme.textMuted)
                        .lineLimit(1)
                }

                Spacer()

                Button {
                    copy(gatewayBase)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .foregroundStyle(MagpieTheme.textMuted)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 0) {
                gatewayStat(
                    String(localized: "模型"),
                    "\(viewModel.gateway?.models ?? viewModel.models.count)"
                )
                gatewayDivider
                gatewayStat(
                    String(localized: "最近调用"),
                    "\(viewModel.gateway?.calls?.count ?? 0)"
                )
                gatewayDivider
                gatewayStat(
                    String(localized: "版本"),
                    viewModel.gateway?.version ?? "—"
                )
            }

            if let lanURLs = viewModel.gateway?.lanURLs, !lanURLs.isEmpty {
                Divider().background(MagpieTheme.borderSubtle)
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "局域网地址"))
                        .font(.caption2)
                        .foregroundStyle(MagpieTheme.textMuted)
                    ForEach(lanURLs.prefix(3), id: \.self) { url in
                        Button {
                            copy(url)
                        } label: {
                            HStack(spacing: 6) {
                                Text(url)
                                    .font(.system(size: 10.5, design: .monospaced))
                                    .foregroundStyle(MagpieTheme.textSecondary)
                                    .lineLimit(1)
                                Spacer()
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 10))
                                    .foregroundStyle(MagpieTheme.textMuted)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .magpieCard()
    }

    private func gatewayStat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(MagpieTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.system(size: 9.5))
                .foregroundStyle(MagpieTheme.textMuted)
        }
        .frame(maxWidth: .infinity)
    }

    private var gatewayDivider: some View {
        Rectangle()
            .fill(MagpieTheme.borderSubtle)
            .frame(width: 1, height: 26)
    }

    // MARK: - 连接
    private var connectCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    connectExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "link")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(MagpieTheme.accent)
                    Text(String(localized: "连接客户端"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(MagpieTheme.textPrimary)
                    Spacer()
                    Image(systemName: connectExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(MagpieTheme.textMuted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if connectExpanded {
                Picker("", selection: $connectFlavor) {
                    Text("OpenAI").tag("openai")
                    Text("Anthropic").tag("anthropic")
                    Text("curl").tag("curl")
                    Text("Shell").tag("shell")
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                HStack(spacing: 8) {
                    Text(String(localized: "示例模型"))
                        .font(.caption2)
                        .foregroundStyle(MagpieTheme.textMuted)
                    Spacer()
                    if viewModel.models.isEmpty {
                        TextField("model-id", text: $connectModel)
                            .font(.system(size: 11, design: .monospaced))
                            .multilineTextAlignment(.trailing)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    } else {
                        Picker("", selection: $connectModel) {
                            Text(String(localized: "自动")).tag("")
                            ForEach(viewModel.models.prefix(200)) { model in
                                Text(model.id).tag(model.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }
                }

                Text(connectSnippet)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(MagpieTheme.textPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(11)
                    .background(MagpieTheme.cardSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                HStack {
                    Text(String(localized: "局域网共享时请使用 Gateway Key，而不是 magpie。"))
                        .font(.caption2)
                        .foregroundStyle(MagpieTheme.textMuted)
                    Spacer()
                    Button {
                        UIPasteboard.general.string = connectSnippet
                        withAnimation(.snappy(duration: 0.25)) { isCopiedSnippet = true }
                        MagpieHaptics.success()
                        Task {
                            try? await Task.sleep(nanoseconds: 1_800_000_000)
                            withAnimation(.snappy(duration: 0.25)) { isCopiedSnippet = false }
                        }
                    } label: {
                        Label(
                            isCopiedSnippet ? String(localized: "已复制") : String(localized: "复制"),
                            systemImage: isCopiedSnippet ? "checkmark" : "doc.on.doc"
                        )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isCopiedSnippet ? MagpieTheme.green : MagpieTheme.accent)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .magpieCard()
    }

    private var selectedConnectModel: String {
        if !connectModel.isEmpty { return connectModel }
        if let first = viewModel.models.first?.id, !first.isEmpty { return first }
        return "your-model"
    }

    private var connectSnippet: String {
        let base = gatewayBase
        let model = selectedConnectModel
        switch connectFlavor {
        case "anthropic":
            return """
            ANTHROPIC_BASE_URL=\(base)
            ANTHROPIC_AUTH_TOKEN=magpie
            ANTHROPIC_MODEL=\(model)
            """
        case "curl":
            return """
            curl -s \(base)/v1/chat/completions \\
              -H 'Authorization: Bearer magpie' \\
              -H 'Content-Type: application/json' \\
              -d '{"model":"\(model)","messages":[{"role":"user","content":"hi"}]}'
            """
        case "shell":
            return """
            export OPENAI_BASE_URL=\(base)/v1
            export OPENAI_API_KEY=magpie
            export ANTHROPIC_BASE_URL=\(base)
            export ANTHROPIC_AUTH_TOKEN=magpie
            """
        default:
            return """
            OPENAI_BASE_URL=\(base)/v1
            OPENAI_API_KEY=magpie
            OPENAI_MODEL=\(model)
            """
        }
    }

    // MARK: - 模型
    private var modelsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                MagpieSectionLabel(
                    title: String(localized: "可用模型"),
                    detail: viewModel.models.isEmpty ? nil : "\(viewModel.models.count)"
                )
                Spacer()
                if viewModel.models.count > 8 {
                    Button(String(localized: "全部")) {
                        showingAllModels = true
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(MagpieTheme.accent)
                }
            }

            if viewModel.models.isEmpty {
                Text(String(localized: "还没有可列出的模型；先在 Providers 中添加并启用模型。"))
                    .font(.caption)
                    .foregroundStyle(MagpieTheme.textMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .magpieCard()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(viewModel.models.prefix(8).enumerated()), id: \.element.id) { index, model in
                        HStack(spacing: 10) {
                            MagpieIconView(
                                icon: model.provider,
                                name: model.providerName ?? model.provider ?? model.id,
                                size: 26,
                                cornerRadius: 6
                            )
                            VStack(alignment: .leading, spacing: 2) {
                                Text(model.displayName)
                                    .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                                    .foregroundStyle(MagpieTheme.textPrimary)
                                    .lineLimit(1)
                                Text(model.id)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(MagpieTheme.textMuted)
                                    .lineLimit(1)
                            }
                            Spacer()
                            if model.decides == true {
                                MagpieStatusChip(text: String(localized: "决策组"), color: MagpieTheme.cyan)
                            } else if model.group == true {
                                MagpieStatusChip(text: String(localized: "路由组"), color: MagpieTheme.purple)
                            }
                            if let provider = model.providerName ?? model.provider {
                                Text(provider)
                                    .font(.caption2)
                                    .foregroundStyle(MagpieTheme.textMuted)
                                    .lineLimit(1)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)

                        if index < min(viewModel.models.count, 8) - 1 {
                            Divider()
                                .background(MagpieTheme.borderSubtle)
                                .padding(.leading, 50)
                        }
                    }
                }
                .magpieCard(padding: 0)
            }
        }
    }

    // MARK: - 最近调用
    private var callsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                MagpieSectionLabel(
                    title: String(localized: "最近调用"),
                    detail: viewModel.gateway?.calls?.isEmpty == false ? "\(viewModel.gateway?.calls?.count ?? 0)" : nil
                )
                Spacer()
                Button {
                    if let client = app.client {
                        Task { await viewModel.loadGateway(client: client) }
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(MagpieTheme.textMuted)
                }
                .buttonStyle(.plain)
            }

            if let calls = viewModel.gateway?.calls, !calls.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(calls.prefix(20).enumerated()), id: \.element.id) { index, call in
                        Button {
                            selectedCall = call
                        } label: {
                            callRow(call)
                        }
                        .buttonStyle(.plain)

                        if index < min(calls.count, 20) - 1 {
                            Divider()
                                .background(MagpieTheme.borderSubtle)
                                .padding(.leading, 50)
                        }
                    }
                }
                .magpieCard(padding: 0)
            } else {
                Text(String(localized: "最近还没有经过网关的请求。"))
                    .font(.caption)
                    .foregroundStyle(MagpieTheme.textMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .magpieCard()
            }
        }
    }

    private func callRow(_ call: GatewayCallDTO) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(call.isError ? MagpieTheme.red : ((call.status ?? 0) >= 200 && (call.status ?? 0) < 400 ? MagpieTheme.green : MagpieTheme.amber))
                .frame(width: 7, height: 7)

            MagpieIconView(icon: call.agent, name: call.agent ?? "agent", size: 26, cornerRadius: 6)

            VStack(alignment: .leading, spacing: 2) {
                Text(call.model ?? String(localized: "未知模型"))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(MagpieTheme.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    if let agent = call.agent, !agent.isEmpty {
                        Text(agent)
                    }
                    if let provider = call.provider, !provider.isEmpty {
                        Text("·")
                        Text(provider)
                    }
                }
                .font(.caption2)
                .foregroundStyle(MagpieTheme.textMuted)
                .lineLimit(1)
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 2) {
                if let status = call.status, status > 0 {
                    Text("\(status)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(call.isError ? MagpieTheme.red : MagpieTheme.green)
                }
                Text(call.ms.map { "\($0)ms" } ?? callTime(call.time))
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(MagpieTheme.textMuted)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(MagpieTheme.textMuted.opacity(0.7))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private func callTime(_ raw: String?) -> String {
        guard let raw else { return "—" }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: raw) {
            let f = DateFormatter()
            f.dateFormat = "HH:mm:ss"
            return f.string(from: date)
        }
        return String(raw.prefix(8))
    }

    private func copy(_ text: String) {
        UIPasteboard.general.string = text
        MagpieHaptics.success()
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(MagpieTheme.pill)
                    .frame(width: 56, height: 56)
                Image(systemName: "key.slash")
                    .font(.title2)
                    .foregroundStyle(MagpieTheme.textMuted)
            }

            Text(String(localized: "暂无网关 Key"))
                .font(.headline)
                .foregroundStyle(MagpieTheme.textPrimary)

            Text(String(localized: "网关 Key 可分发给局域网其他设备或终端 Agent 使用，具备独立的额度与路由限制。"))
                .font(.subheadline)
                .foregroundStyle(MagpieTheme.textSecondary)
                .multilineTextAlignment(.center)

            Button {
                showCreateSheet = true
            } label: {
                Text(String(localized: "创建第一个 Gateway Key"))
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(MagpieTheme.accent)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .magpieCard()
    }

    private var createKeySheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(String(localized: "密钥名称 (例如 Work Laptop)"), text: $newKeyName)
                    Toggle(String(localized: "管理员权限 (Admin)"), isOn: $newKeyIsAdmin)
                        .tint(MagpieTheme.green)
                        .disabled(newKeyIsReadOnly)
                    Toggle(String(localized: "只读权限 (仅统计)"), isOn: $newKeyIsReadOnly)
                        .tint(MagpieTheme.green)
                } header: {
                    Text(String(localized: "密钥信息"))
                } footer: {
                    Text(String(localized: "管理员权限允许通过此 Key 访问网关的管理接口；只读 Key 只能读取统计，不能调用模型。"))
                }
            }
            .navigationTitle(String(localized: "新建 Gateway Key"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "取消")) { showCreateSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "创建")) {
                        createKey()
                    }
                    .disabled(newKeyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCreating)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func createKey() {
        guard let client = app.client else { return }
        isCreating = true
        Task {
            defer { isCreating = false }
            let admin = (newKeyIsAdmin && !newKeyIsReadOnly) ? "any" : ""
            let secret = await viewModel.create(
                client: client,
                name: newKeyName.trimmingCharacters(in: .whitespacesAndNewlines),
                admin: admin,
                readOnly: newKeyIsReadOnly
            )
            showCreateSheet = false
            if let secret {
                secretReveal = SecretReveal(name: newKeyName, secret: secret)
            }
            newKeyName = ""
            newKeyIsAdmin = false
            newKeyIsReadOnly = false
        }
    }

    private func reveal(key: GatewayKeyDTO) {
        guard let client = app.client else { return }
        Task {
            if let secret = await viewModel.revealSecret(client: client, id: key.id) {
                secretReveal = SecretReveal(name: key.displayName, secret: secret)
            }
        }
    }

    private func rotate(key: GatewayKeyDTO) {
        guard let client = app.client else { return }
        Task {
            if let secret = await viewModel.rotate(client: client, id: key.id) {
                secretReveal = SecretReveal(name: key.displayName, secret: secret)
            }
        }
    }
}

// MARK: - 明文展示
private struct SecretReveal: Identifiable {
    let id = UUID()
    let name: String
    let secret: String
}

private struct SecretRevealSheet: View {
    let reveal: SecretReveal
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                VStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(MagpieTheme.greenSoft)
                            .frame(width: 58, height: 58)
                        Image(systemName: "key.horizontal.fill")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(MagpieTheme.green)
                    }
                    Text(reveal.name)
                        .font(.headline)
                        .foregroundStyle(MagpieTheme.textPrimary)
                    Text(String(localized: "请立即复制并妥善保存。离开此页后，明文不会再显示。"))
                        .font(.caption)
                        .foregroundStyle(MagpieTheme.textSecondary)
                        .multilineTextAlignment(.center)
                }

                Text(reveal.secret)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(MagpieTheme.textPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(MagpieTheme.cardSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(MagpieTheme.borderSubtle, lineWidth: 1)
                    )

                Button {
                    UIPasteboard.general.string = reveal.secret
                    copied = true
                    MagpieHaptics.success()
                } label: {
                    Label(
                        copied ? String(localized: "已复制") : String(localized: "复制密钥"),
                        systemImage: copied ? "checkmark" : "doc.on.doc"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(MagpiePrimaryButtonStyle(tint: copied ? MagpieTheme.green : MagpieTheme.accent))

                Spacer()
            }
            .padding(20)
            .magpiePageBackground()
            .navigationTitle(String(localized: "Gateway Key"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "完成")) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - 限额编辑

private struct GatewayLimitTarget: Identifiable {
    let id = UUID()
    let keyID: String
    var initialSlot = 0
}

/// 一个 Key 的限额编辑器，对齐官方 Gateway 页的限额表单：
/// 单个限额直接替换，多个限额按 `index` 增删改。
private struct GatewayLimitEditorSheet: View {
    let keyID: String
    let initialSlot: Int
    let viewModel: GatewayViewModel
    let models: [GatewayModelDTO]

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var selectedSlot = 0
    @State private var period = "day"
    @State private var days = ""
    @State private var hours = ""
    @State private var selectedAccountWindow = ""
    @State private var tokens = ""
    @State private var cost = ""
    @State private var cacheReads = false
    @State private var scopedModels: [String] = []
    @State private var showModels = false
    @State private var showResetConfirm = false
    @State private var isSaving = false
    @State private var localError: String?
    @State private var didLoad = false

    private var key: GatewayKeyDTO? {
        viewModel.keys.first { $0.id == keyID }
    }

    private var limits: [GatewayLimitDTO] { key?.limits ?? [] }
    private var usages: [GatewayLimitUsageDTO] { key?.limitUsages ?? [] }
    private var isNew: Bool { selectedSlot >= limits.count }
    private var showSlotPicker: Bool { limits.count > 1 || (isNew && !limits.isEmpty) }

    private var currentUsage: GatewayLimitUsageDTO? {
        guard !isNew, usages.indices.contains(selectedSlot) else { return nil }
        return usages[selectedSlot]
    }

    private var parsedAccountWindow: (account: String, window: String)? {
        let parts = selectedAccountWindow.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
        return (parts[0], parts[1])
    }

    private var canSave: Bool {
        guard let tokenValue = Self.parseTokenCount(tokens),
              let costValue = Self.parseCost(cost),
              tokenValue > 0 || costValue > 0
        else { return false }
        if period == "days" {
            guard let value = Int(days.trimmingCharacters(in: .whitespaces)), (1...3650).contains(value) else { return false }
        }
        if period == "hours" {
            guard let value = Int(hours.trimmingCharacters(in: .whitespaces)), (1...8760).contains(value) else { return false }
        }
        if period == "account" {
            guard parsedAccountWindow != nil else { return false }
        }
        return true
    }

    var body: some View {
        NavigationStack {
            Form {
                if showSlotPicker {
                    Section {
                        Picker(String(localized: "限额"), selection: Binding(
                            get: { selectedSlot },
                            set: { load($0) }
                        )) {
                            ForEach(Array(limits.enumerated()), id: \.element.id) { index, limit in
                                Text("\(limit.periodName) \(limit.capDescription)").tag(index)
                            }
                            if limits.count < 5 {
                                Text(String(localized: "新增限额")).tag(limits.count)
                            }
                        }
                    }
                }

                Section {
                    Picker(String(localized: "窗口"), selection: $period) {
                        Text(String(localized: "每天")).tag("day")
                        Text(String(localized: "每周")).tag("week")
                        Text(String(localized: "每月")).tag("month")
                        Text(String(localized: "每 N 天")).tag("days")
                        Text(String(localized: "每 N 小时")).tag("hours")
                        if !viewModel.accountWindows.isEmpty || period == "account" {
                            Text(String(localized: "跟随账号窗口")).tag("account")
                        }
                        Text(String(localized: "累计（不自动重置）")).tag("total")
                    }
                    if period == "days" {
                        TextField(String(localized: "天数 (1–3650)"), text: $days)
                            .keyboardType(.numberPad)
                    }
                    if period == "hours" {
                        TextField(String(localized: "小时数 (1–8760)"), text: $hours)
                            .keyboardType(.numberPad)
                    }
                    if period == "account" {
                        if viewModel.accountWindows.isEmpty {
                            Text(String(localized: "当前没有可用的订阅账号配额窗口"))
                                .font(.caption)
                                .foregroundStyle(MagpieTheme.textMuted)
                        } else {
                            Picker(String(localized: "账号窗口"), selection: $selectedAccountWindow) {
                                ForEach(viewModel.accountWindows) { win in
                                    Text(win.displayLabel).tag(win.id)
                                }
                            }
                        }
                    }
                } header: {
                    Text(String(localized: "周期"))
                } footer: {
                    Text(String(localized: "日/周/月按本机时区的自然窗口计算；每 N 天/小时从设置或重置时开始循环；跟随账号窗口会在对应订阅窗口重置时清零。"))
                }

                Section {
                    TextField(String(localized: "不限额留空"), text: $tokens)
                        .keyboardType(.numbersAndPunctuation)
                    TextField(String(localized: "不限额留空"), text: $cost)
                        .keyboardType(.decimalPad)
                    Toggle(String(localized: "计入缓存读取"), isOn: $cacheReads)
                        .tint(MagpieTheme.green)
                } header: {
                    Text(String(localized: "额度"))
                } footer: {
                    Text(String(localized: "Tokens 为每次调用的未缓存输入、输出与缓存写入；成本按 Usage 页价格估算（美元）。两者都填时任一用尽即拒绝。"))
                }

                Section {
                    Button {
                        showModels = true
                    } label: {
                        HStack {
                            Text(String(localized: "模型范围"))
                                .foregroundStyle(MagpieTheme.textPrimary)
                            Spacer()
                            Text(scopedModels.isEmpty
                                 ? String(localized: "全部模型")
                                 : String(localized: "\(scopedModels.count) 个模型"))
                                .foregroundStyle(MagpieTheme.textMuted)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(MagpieTheme.textMuted)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } footer: {
                    Text(String(localized: "不选表示该 Key 的所有调用都计入此限额。"))
                }

                if let usage = currentUsage {
                    usageSection(usage)
                }

                if !isNew {
                    Section {
                        Button(role: .destructive) {
                            remove()
                        } label: {
                            Text(String(localized: "移除该限额"))
                        }
                        .disabled(isSaving)
                    }
                }

                if limits.count < 5 && !isNew {
                    Section {
                        Button {
                            load(limits.count)
                        } label: {
                            Label(String(localized: "新增限额"), systemImage: "plus")
                        }
                        .disabled(isSaving)
                    } footer: {
                        Text(String(localized: "一个 Key 最多 5 个限额；请求只有在每个限额都还有余量时才会通过。"))
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
            .navigationTitle(String(localized: "限额"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "取消")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "保存")) { save() }
                        .disabled(!canSave || isSaving)
                }
            }
            .onAppear {
                guard !didLoad else { return }
                didLoad = true
                load(initialSlot)
            }
            .sheet(isPresented: $showModels) {
                GatewayLimitModelsPicker(models: models, selection: $scopedModels)
            }
            .confirmationDialog(
                String(localized: "重置已用额度？"),
                isPresented: $showResetConfirm,
                titleVisibility: .visible
            ) {
                Button(String(localized: "重置用量"), role: .destructive) { reset() }
                Button(String(localized: "取消"), role: .cancel) {}
            } message: {
                Text(String(localized: "该 Key 在本窗口已用的 tokens 与成本会清零，之后重新计数。"))
            }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private func usageSection(_ usage: GatewayLimitUsageDTO) -> some View {
        Section {
            if let left = usage.tokensLeftDescription {
                LabeledContent {
                    Text(left)
                } label: {
                    Text(String(localized: "Tokens"))
                }
            }
            if let left = usage.costLeftDescription {
                LabeledContent {
                    Text(left)
                } label: {
                    Text(String(localized: "成本"))
                }
            }
            if usage.period != "total", let reset = usage.resetDate {
                LabeledContent {
                    Text(reset.formatted(date: .abbreviated, time: .shortened))
                } label: {
                    Text(String(localized: "重置时间"))
                }
            } else if let start = usage.startDate {
                LabeledContent {
                    Text(start.formatted(date: .abbreviated, time: .shortened))
                } label: {
                    Text(String(localized: "开始计数"))
                }
            }
            if usage.isSpent {
                Label(String(localized: "已用尽，重置前拒绝请求"), systemImage: "exclamationmark.octagon.fill")
                    .font(.caption)
                    .foregroundStyle(MagpieTheme.red)
            }
            Button(String(localized: "重置用量"), role: .destructive) {
                showResetConfirm = true
            }
            .disabled(isSaving)
        } header: {
            Text(String(localized: "本窗口用量"))
        }
    }

    private func load(_ slot: Int) {
        selectedSlot = slot
        localError = nil
        let list = limits
        if list.indices.contains(slot) {
            let limit = list[slot]
            period = limit.period
            days = limit.days.map { String($0) } ?? ""
            hours = limit.hours.map { String($0) } ?? ""
            if let acc = limit.account, let win = limit.accountWindow, !acc.isEmpty, !win.isEmpty {
                selectedAccountWindow = "\(acc)|\(win)"
            } else {
                selectedAccountWindow = viewModel.accountWindows.first?.id ?? ""
            }
            tokens = limit.tokens.map { String($0) } ?? ""
            cost = limit.cost.map { String(format: "%g", $0) } ?? ""
            cacheReads = limit.cacheReads ?? false
            scopedModels = limit.models ?? []
        } else {
            let taken = Set(list.map(\.period))
            let fresh = ["week", "hours", "day", "month"].first { !taken.contains($0) } ?? "days"
            period = fresh
            days = fresh == "days" ? "10" : ""
            hours = fresh == "hours" ? "5" : ""
            selectedAccountWindow = viewModel.accountWindows.first?.id ?? ""
            tokens = ""
            cost = ""
            cacheReads = false
            scopedModels = []
        }
    }

    private func save() {
        guard let client = app.client else {
            localError = String(localized: "连接已断开")
            return
        }
        guard let tokenValue = Self.parseTokenCount(tokens),
              let costValue = Self.parseCost(cost)
        else {
            localError = String(localized: "请输入有效的 tokens 数量与美元成本")
            return
        }
        guard tokenValue > 0 || costValue > 0 else {
            localError = String(localized: "至少填写 tokens 或成本之一")
            return
        }

        var dayCount: Int?
        var hourCount: Int?
        var accountName: String?
        var accountWindowName: String?
        if period == "days" {
            guard let value = Int(days.trimmingCharacters(in: .whitespaces)), (1...3650).contains(value) else {
                localError = String(localized: "周期天数需为 1–3650")
                return
            }
            dayCount = value
        }
        if period == "hours" {
            guard let value = Int(hours.trimmingCharacters(in: .whitespaces)), (1...8760).contains(value) else {
                localError = String(localized: "周期小时数需为 1–8760")
                return
            }
            hourCount = value
        }
        if period == "account" {
            guard let parsed = parsedAccountWindow else {
                localError = String(localized: "请选择一个账号配额窗口")
                return
            }
            accountName = parsed.account
            accountWindowName = parsed.window
        }

        let payload = GatewayLimitPayload(
            period: period,
            days: dayCount,
            hours: hourCount,
            account: accountName,
            accountWindow: accountWindowName,
            tokens: tokenValue > 0 ? tokenValue : nil,
            cost: costValue > 0 ? costValue : nil,
            cacheReads: cacheReads ? true : nil,
            models: scopedModels.isEmpty ? nil : scopedModels
        )
        let index: Int? = (limits.count > 1 || isNew) ? selectedSlot : nil
        isSaving = true
        localError = nil
        Task {
            let ok = await viewModel.setLimit(client: client, keyID: keyID, limit: payload, index: index)
            isSaving = false
            if ok {
                dismiss()
            } else {
                localError = viewModel.errorMessage
            }
        }
    }

    private func remove() {
        guard let client = app.client else { return }
        let index: Int? = limits.count > 1 ? selectedSlot : nil
        isSaving = true
        localError = nil
        Task {
            let ok = await viewModel.setLimit(client: client, keyID: keyID, limit: nil, index: index)
            isSaving = false
            if ok {
                dismiss()
            } else {
                localError = viewModel.errorMessage
            }
        }
    }

    private func reset() {
        guard let client = app.client else { return }
        let index: Int? = limits.count > 1 ? selectedSlot : nil
        isSaving = true
        localError = nil
        Task {
            let ok = await viewModel.resetLimit(client: client, keyID: keyID, index: index)
            isSaving = false
            if !ok {
                localError = viewModel.errorMessage
            }
        }
    }

    /// 与官方 UI 一致：支持 2M、500k、1.5m、100万、1亿 等写法。
    static func parseTokenCount(_ raw: String) -> Int64? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        text = text
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: " ", with: "")
        if text.isEmpty { return 0 }
        var multiplier = 1.0
        for (suffix, value) in [("k", 1e3), ("m", 1e6), ("b", 1e9), ("万", 1e4), ("亿", 1e8)] {
            if text.hasSuffix(suffix) {
                text.removeLast(suffix.count)
                multiplier = value
                break
            }
        }
        guard let number = Double(text), number >= 0, number.isFinite else { return nil }
        let scaled = (number * multiplier).rounded()
        guard scaled.isFinite, scaled <= Double(Int64.max) else { return nil }
        return Int64(scaled)
    }

    static func parseCost(_ raw: String) -> Double? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("$") || text.hasPrefix("＄") {
            text.removeFirst()
        }
        if text.isEmpty { return 0 }
        guard let value = Double(text), value >= 0, value.isFinite else { return nil }
        return (value * 10_000).rounded() / 10_000
    }
}

// MARK: - 限额的模型范围

private struct GatewayLimitModelsPicker: View {
    let models: [GatewayModelDTO]
    @Binding var selection: [String]

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private struct Option: Identifiable, Hashable {
        let id: String
        let name: String
        let detail: String
    }

    private var options: [Option] {
        var seen = Set<String>()
        var out: [Option] = []
        for model in models where model.group != true {
            let provider = model.provider ?? model.id.split(separator: "/").first.map { String($0) } ?? ""
            if !provider.isEmpty, seen.insert("\(provider)/*").inserted {
                out.append(Option(
                    id: "\(provider)/*",
                    name: String(localized: "全部 \(model.providerName ?? provider) 模型"),
                    detail: "\(provider)/*"
                ))
            }
            if seen.insert(model.id).inserted {
                out.append(Option(id: model.id, name: model.displayName, detail: model.id))
            }
        }
        for id in selection where !seen.contains(id) {
            out.append(Option(id: id, name: id, detail: String(localized: "当前未提供")))
        }
        return out
    }

    private var filtered: [Option] {
        guard !searchText.isEmpty else { return options }
        let query = searchText.lowercased()
        return options.filter {
            $0.id.lowercased().contains(query) || $0.name.lowercased().contains(query)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        selection = []
                    } label: {
                        HStack {
                            Text(String(localized: "全部模型"))
                                .foregroundStyle(MagpieTheme.textPrimary)
                            Spacer()
                            if selection.isEmpty {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(MagpieTheme.accent)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                Section {
                    ForEach(filtered) { option in
                        Button {
                            toggle(option.id)
                        } label: {
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(option.name)
                                        .foregroundStyle(MagpieTheme.textPrimary)
                                    Text(option.detail)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(MagpieTheme.textMuted)
                                }
                                Spacer()
                                if selection.contains(option.id) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(MagpieTheme.accent)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .searchable(text: $searchText, prompt: String(localized: "搜索模型…"))
            .navigationTitle(String(localized: "计入限额的模型"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "完成")) { dismiss() }
                }
            }
        }
    }

    private func toggle(_ id: String) {
        if let index = selection.firstIndex(of: id) {
            selection.remove(at: index)
        } else {
            selection.append(id)
        }
    }
}

// MARK: - 原版风格网关 Key 卡片
private struct GatewayKeyCard: View {
    let key: GatewayKeyDTO
    let onToggle: (Bool) -> Void
    let onCopy: () -> Void
    let onRotate: () -> Void
    let onLimit: () -> Void
    let onRouting: (String) -> Void
    let onMemory: (Bool) -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(key.isOff ? MagpieTheme.pill : MagpieTheme.accentSoft)
                    .frame(width: 36, height: 36)
                Image(systemName: "key.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(key.isOff ? MagpieTheme.textMuted : MagpieTheme.accent)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(key.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(key.isOff ? MagpieTheme.textMuted : MagpieTheme.textPrimary)

                    if key.isAdmin {
                        Text("ADMIN")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(MagpieTheme.purple.opacity(0.15))
                            .foregroundStyle(MagpieTheme.purple)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    if key.isReadOnly {
                        Text("READ ONLY")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(MagpieTheme.amberSoft)
                            .foregroundStyle(MagpieTheme.amber)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    if key.browser == true {
                        Text("BROWSER")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(MagpieTheme.accentSoft)
                            .foregroundStyle(MagpieTheme.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    if key.memory == true {
                        Text("MEMORY")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(MagpieTheme.cyan.opacity(0.15))
                            .foregroundStyle(MagpieTheme.cyan)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }

                if let routing = key.routing, !routing.isEmpty {
                    Text(String(localized: "路由覆盖：\(GroupRouting.displayName(routing))"))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(MagpieTheme.accent)
                }

                if let masked = key.masked {
                    Text(masked)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(MagpieTheme.textMuted)
                }

                Button(action: onLimit) {
                    HStack(spacing: 5) {
                        Image(systemName: "gauge.with.dots.needle.33percent")
                            .font(.system(size: 8))
                        if key.limits.isEmpty {
                            Text(String(localized: "限额"))
                                .font(.system(size: 9, weight: .medium))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(MagpieTheme.pill)
                                .clipShape(Capsule())
                        } else {
                            let index = key.bindingLimitIndex
                            if key.limits.indices.contains(index) {
                                let limit = key.limits[index]
                                let usage = key.limitUsages.indices.contains(index) ? key.limitUsages[index] : nil
                                Text("\(limit.periodName) \(usage?.compactDescription ?? limit.capDescription)")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(usage?.isSpent == true ? MagpieTheme.red : MagpieTheme.textMuted)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(MagpieTheme.pill)
                                    .clipShape(Capsule())
                            }
                            if key.limits.count > 1 {
                                Text("+\(key.limits.count - 1)")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(MagpieTheme.textMuted)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(MagpieTheme.pill)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    .foregroundStyle(MagpieTheme.textMuted)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { !key.isOff },
                set: { value in
                    MagpieHaptics.light()
                    onToggle(value)
                }
            ))
            .labelsHidden()
            .tint(MagpieTheme.green)
        }
        .magpieLiquidCard(padding: 14, cornerRadius: 20)
        .contextMenu {
            Button(action: onCopy) {
                Label(String(localized: "查看并复制 Key"), systemImage: "doc.on.doc")
            }
            Button(action: onLimit) {
                Label(String(localized: "限额…"), systemImage: "gauge.with.dots.needle.33percent")
            }
            if !key.isReadOnly && key.browser != true {
                Menu {
                    ForEach(GroupRouting.keyOverrides) { option in
                        Button {
                            onRouting(option.id)
                        } label: {
                            if (key.routing ?? "") == option.id {
                                Label(option.label, systemImage: "checkmark")
                            } else {
                                Text(option.label)
                            }
                        }
                    }
                } label: {
                    Label(String(localized: "路由策略覆盖"), systemImage: "arrow.triangle.branch")
                }

                if key.lan != true && key.expires == nil {
                    Button {
                        onMemory(!(key.memory == true))
                    } label: {
                        Label(
                            key.memory == true ? String(localized: "关闭 Memory 访问") : String(localized: "允许 Memory 访问"),
                            systemImage: key.memory == true ? "brain.head.profile.fill" : "brain.head.profile"
                        )
                    }
                }
            }
            Button(action: onRotate) {
                Label(String(localized: "轮换 Key"), systemImage: "arrow.triangle.2.circlepath")
            }
            Divider()
            Button(role: .destructive, action: onDelete) {
                Label(String(localized: "删除密钥"), systemImage: "trash")
            }
        }
    }
}

// MARK: - 调用详情
private struct GatewayCallSheet: View {
    let call: GatewayCallDTO
    let load: () async -> GatewayCallDetailDTO?
    @Environment(\.dismiss) private var dismiss
    @State private var detail: GatewayCallDetailDTO?
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(call.isError ? MagpieTheme.red : MagpieTheme.green)
                                .frame(width: 8, height: 8)
                            Text(call.model ?? String(localized: "未知模型"))
                                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                .foregroundStyle(MagpieTheme.textPrimary)
                            Spacer()
                            if let status = call.status {
                                Text("HTTP \(status)")
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(call.isError ? MagpieTheme.red : MagpieTheme.green)
                            }
                        }

                        HStack(spacing: 8) {
                            if let agent = call.agent { Text(agent) }
                            if let provider = call.provider {
                                Text("·")
                                Text(provider)
                            }
                            if let ms = call.ms {
                                Text("· \(ms)ms")
                            }
                        }
                        .font(.caption2)
                        .foregroundStyle(MagpieTheme.textMuted)

                        if let error = call.error, !error.isEmpty {
                            Text(error)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(MagpieTheme.red)
                                .textSelection(.enabled)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .magpieCard()

                    if isLoading {
                        ProgressView(String(localized: "读取请求内容…"))
                            .padding(.vertical, 20)
                    } else if let detail {
                        bodyCard(String(localized: "请求体"), text: detail.requestBody, truncated: detail.requestTruncated)
                        bodyCard(String(localized: "响应体"), text: detail.responseBody, truncated: detail.responseTruncated)
                    } else {
                        Text(String(localized: "这次调用的请求体已不在最近记录中。"))
                            .font(.caption)
                            .foregroundStyle(MagpieTheme.textMuted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .magpieCard()
                    }
                }
                .padding(16)
            }
            .magpiePageBackground()
            .navigationTitle(String(localized: "调用详情"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "完成")) { dismiss() }
                }
            }
            .task {
                detail = await load()
                isLoading = false
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func bodyCard(_ title: String, text: String?, truncated: Bool?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MagpieTheme.textMuted)
                Spacer()
                if truncated == true {
                    Text(String(localized: "已截断"))
                        .font(.caption2)
                        .foregroundStyle(MagpieTheme.amber)
                }
                if let text, !text.isEmpty {
                    Button {
                        UIPasteboard.general.string = text
                        MagpieHaptics.success()
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.caption)
                            .foregroundStyle(MagpieTheme.textMuted)
                    }
                    .buttonStyle(.plain)
                }
            }

            Text(text?.isEmpty == false ? text! : String(localized: "（空）"))
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(MagpieTheme.textPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(MagpieTheme.cardSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .magpieCard()
    }
}

// MARK: - 全部模型
private struct GatewayModelsSheet: View {
    let models: [GatewayModelDTO]
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var filtered: [GatewayModelDTO] {
        guard !searchText.isEmpty else { return models }
        let q = searchText.lowercased()
        return models.filter {
            $0.id.lowercased().contains(q)
                || $0.displayName.lowercased().contains(q)
                || ($0.provider?.lowercased().contains(q) ?? false)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filtered) { model in
                    HStack(spacing: 10) {
                        MagpieIconView(
                            icon: model.provider,
                            name: model.providerName ?? model.provider ?? model.id,
                            size: 26,
                            cornerRadius: 6
                        )
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.displayName)
                                .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                                .foregroundStyle(MagpieTheme.textPrimary)
                            Text(model.id)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(MagpieTheme.textMuted)
                        }
                        Spacer()
                        if model.group == true {
                            Text(String(localized: "路由组"))
                                .font(.caption2)
                                .foregroundStyle(MagpieTheme.purple)
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: String(localized: "搜索模型…"))
            .navigationTitle(String(localized: "网关模型"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "完成")) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
