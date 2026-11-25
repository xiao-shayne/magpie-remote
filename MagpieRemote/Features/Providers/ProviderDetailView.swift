import SwiftUI
import UIKit

/// 已添加 Provider 的编辑页：对齐官方编辑器的分区结构。
/// 包含连接与密钥、多密钥管理、模型选择、路由/并发、连通性测试与危险操作。
struct ProviderDetailView: View {
    let providerID: String
    var viewModel: ProvidersViewModel? = nil
    @Environment(AppModel.self) private var app
    @Environment(ProvidersViewModel.self) private var envViewModel: ProvidersViewModel?
    @Environment(\.dismiss) private var dismiss
    @State private var fallbackViewModel = ProvidersViewModel()

    private var activeVM: ProvidersViewModel {
        viewModel ?? envViewModel ?? fallbackViewModel
    }

    @State private var isTesting = false
    @State private var testResponse: ProviderTestResponseDTO?
    @State private var testError: String?
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var showingDeleteAlert = false
    @State private var showingAddKey = false
    @State private var showingModels = false
    @State private var showingAdvanced = false
    @State private var pendingKeyRemoval: ProviderDTO.KeyItemDTO?

    // 快速操作
    @State private var isRefreshingModels = false
    @State private var refreshMessage: String?
    @State private var isCheckingBalance = false
    @State private var balanceMessage: String?
    @State private var modelTestResponse: ProviderTestResponseDTO?
    @State private var isTestingModels = false
    @State private var showingTestAllConfirm = false
    @State private var selectedTestModel = ""
    @State private var testAllModels = false
    @State private var relayCheckModel = ""
    @State private var isCheckingRelay = false
    @State private var relayCheckResult: RelayCheckResultDTO?
    @State private var relayCheckError: String?
    @State private var isCheckingEgress = false
    @State private var topUpRateDraft = 0.0
    @State private var connectAgentsDraft = false

    // 编辑草稿
    @State private var nameDraft = ""
    @State private var keyDraft = ""
    @State private var chatDraft = ""
    @State private var responsesDraft = ""
    @State private var anthropicDraft = ""
    @State private var geminiDraft = ""
    @State private var proxyDraft = ""
    @State private var searchesDraft = false
    @State private var unredactedDraft = false
    @State private var routingDraft = ""
    @State private var affinityDraft = ""
    @State private var sinkDraft = false
    @State private var useFirstDraft = false
    @State private var noStandInDraft = false
    @State private var maxConcurrencyDraft = 0
    @State private var queueLimitDraft = 0
    @State private var queueWaitDraft = 0
    @State private var maxRPMDraft = 0
    @State private var selectedModels: Set<String> = []
    @State private var isKeyVisible = false
    @State private var primed = false

    // 官方编辑器的高级字段
    @State private var unlistedDraft = false
    @State private var noModelsDraft = false
    @State private var bestInFamilyDraft = false
    @State private var listOffDraft = false
    @State private var priceRateDraft = 0.0
    @State private var headersDraft = ""
    @State private var extraBodyDraft = ""
    @State private var replyHeadersDraft = ""
    @State private var passHeadersDraft = ""
    @State private var insecureTLSDraft = false
    @State private var http1Draft = false
    @State private var socketDraft = ""
    @State private var limitRestOffDraft = false
    @State private var passUserAgentDraft = false
    @State private var authHeaderDraft = ""
    @State private var nativeCompactionDraft = false
    @State private var passErrorsDraft = false
    @State private var modelsURLDraft = ""
    @State private var balanceURLDraft = ""
    @State private var balancePathDraft = ""
    @State private var balanceMethodDraft = ""
    @State private var balanceTokenDraft = ""
    @State private var showingRequestAdvanced = false
    @State private var showingNetworkAdvanced = false
    @State private var showingRename = false
    @State private var renameIDDraft = ""
    @State private var revealedKey = ""
    @State private var showingRevealedKey = false
    @State private var keepLoginAsDraft = ""
    @State private var showingCopy = false
    @State private var copyIDDraft = ""
    @State private var contextsDraft: [String: Int] = [:]
    @State private var outputsDraft: [String: Int] = [:]
    @State private var accountSettingsUser: String?
    @State private var testAccount = ""
    @State private var testRun = ""
    @State private var modelSearch = ""
    @State private var settingsModelID: String?
    @State private var settingsModelName = ""
    @State private var settingsModelContext = ""
    @State private var settingsModelOutput = ""
    @State private var settingsModelEfforts: Set<String> = []
    @State private var settingsModelAvailableEfforts: [String] = []
    @State private var settingsModelImages = false

    private var provider: ProviderDTO? {
        activeVM.providers.first { $0.id == providerID }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                if let provider {
                    // 每个区块单独擦除类型：把 12 个高度嵌套的 SwiftUI 泛型
                    // 拼进同一个 TupleView，会让运行时反序列化超长泛型签名并爆栈。
                    AnyView(header(provider))
                    if let egress = provider.egress {
                        AnyView(egressBanner(egress))
                    }
                    if let proxyGone = provider.proxyGone, !proxyGone.isEmpty {
                        AnyView(
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(MagpieTheme.amber)
                                Text(String(localized: "原绑定的命名代理「\(proxyGone)」已被删除，当前回退到默认网络。"))
                                    .font(.caption)
                                    .foregroundStyle(MagpieTheme.textSecondary)
                                Spacer(minLength: 0)
                            }
                            .magpieCard(padding: 12)
                        )
                    }
                    AnyView(quickActions(provider))
                    AnyView(connectionSection)
                    AnyView(keysSection(provider))
                    if provider.isSubscription {
                        AnyView(subscriptionSection(provider))
                    }
                    AnyView(modelsSection(provider))
                    AnyView(behaviorSection(provider))
                    AnyView(routingSection)
                    AnyView(requestSection(provider))
                    if provider.preset?.isEmpty != false {
                        AnyView(customEndpointSection)
                    }
                    AnyView(testSection(provider))
                    AnyView(dangerSection)
                } else {
                    ProgressView(String(localized: "读取 Provider…"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 60)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .magpiePageBackground()
        .navigationTitle(provider?.name ?? String(localized: "Provider"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Button {
                        renameIDDraft = providerID
                        showingRename = true
                    } label: {
                        Label(String(localized: "重命名 ID"), systemImage: "character.cursor.ibeam")
                    }
                    if let provider {
                        Button {
                            refreshModels(provider)
                        } label: {
                            Label(String(localized: "从厂商重新获取模型"), systemImage: "arrow.triangle.2.circlepath")
                        }
                        Button {
                            runTest(id: provider.id)
                        } label: {
                            Label(String(localized: "测试连通性"), systemImage: "bolt.fill")
                        }
                        Button {
                            copyIDDraft = provider.id + "-copy"
                            showingCopy = true
                        } label: {
                            Label(String(localized: "复制为新 Provider…"), systemImage: "plus.square.on.square")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    save()
                } label: {
                    if isSaving {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(String(localized: "保存"))
                            .fontWeight(.semibold)
                    }
                }
                .disabled(isSaving || provider == nil)
            }
        }
        .task {
            if let client = app.client, activeVM.providers.isEmpty {
                await activeVM.load(client: client)
            }
            primeIfNeeded()
        }
        .onAppear { primeIfNeeded() }
        .alert(String(localized: "重命名 Provider ID"), isPresented: $showingRename) {
            TextField("provider-id", text: $renameIDDraft)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button(String(localized: "取消"), role: .cancel) {}
            Button(String(localized: "保存")) {
                guard let client = app.client, let provider else { return }
                let newID = renameIDDraft.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard !newID.isEmpty, newID != provider.id else { return }
                Task {
                    var request = buildSaveRequest(provider: provider, newID: newID)
                    request.from = provider.id
                    let ok = await activeVM.save(client: client, request: request)
                    if ok {
                        MagpieHaptics.success()
                        dismiss()
                    } else {
                        saveError = activeVM.errorMessage ?? String(localized: "重命名失败")
                    }
                }
            }
        } message: {
            Text(String(localized: "官方要求 ID 只能包含小写字母、数字和短横线；重命名后使用它模型的 Agent 会自动跟随。"))
        }
        .alert(String(localized: "复制为新 Provider"), isPresented: $showingCopy) {
            TextField("provider-copy", text: $copyIDDraft)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button(String(localized: "取消"), role: .cancel) {}
            Button(String(localized: "复制")) {
                copyProvider()
            }
        } message: {
            Text(String(localized: "复制端点、路由与并发设置；Key 需要在新 Provider 里重新填写。"))
        }
        .sheet(isPresented: $showingAddKey) {
            if let provider {
                ProviderAddKeySheet(
                    onAdd: { name, key, protocolName, weight in
                        guard let client = app.client else { return false }
                        return await activeVM.addKey(
                            client: client,
                            id: provider.id,
                            name: name,
                            key: key,
                            protocolName: protocolName,
                            weight: weight
                        )
                    },
                    onImport: { keys in
                        guard let client = app.client else { return false }
                        return await activeVM.importKeys(client: client, id: provider.id, keys: keys)
                    }
                )
            }
        }
        .sheet(isPresented: Binding(
            get: { settingsModelID != nil },
            set: { if !$0 { settingsModelID = nil } }
        )) {
            if let modelID = settingsModelID {
                ProviderModelSettingsSheet(
                    modelID: modelID,
                    name: settingsModelName,
                    context: settingsModelContext,
                    output: settingsModelOutput,
                    availableEfforts: settingsModelAvailableEfforts,
                    efforts: settingsModelEfforts,
                    images: settingsModelImages
                ) { name, context, output, efforts, images in
                    settingsModelName = name
                    settingsModelContext = context
                    settingsModelOutput = output
                    settingsModelEfforts = efforts
                    settingsModelImages = images
                    return await applyModelSettings(modelID)
                }
            }
        }
        .sheet(isPresented: $showingRevealedKey) {
            ProviderKeyRevealSheet(key: revealedKey)
        }
        .sheet(isPresented: Binding(
            get: { accountSettingsUser != nil },
            set: { if !$0 { accountSettingsUser = nil } }
        )) {
            if let provider, let user = accountSettingsUser {
                ProviderAccountSettingsSheet(
                    account: user,
                    cap: provider.accountCaps?[user.lowercased()] ?? 0,
                    weight: provider.accountWeights?[user.lowercased()] ?? 0,
                    concurrency: provider.accountConcurrency?[user.lowercased()] ?? 0
                ) { cap, weight, concurrency in
                    guard let client = app.client else { return false }
                    await activeVM.setAccountCap(client: client, id: provider.id, account: user, cap: cap)
                    await activeVM.setAccountWeight(client: client, id: provider.id, account: user, weight: weight)
                    await activeVM.setAccountConcurrency(client: client, id: provider.id, account: user, limit: concurrency)
                    return true
                }
            }
        }
        .alert(String(localized: "删除这个 Provider？"), isPresented: $showingDeleteAlert) {
            Button(String(localized: "删除"), role: .destructive) {
                guard let client = app.client else { return }
                Task {
                    _ = await activeVM.delete(client: client, id: providerID)
                    dismiss()
                }
            }
            Button(String(localized: "取消"), role: .cancel) {}
        } message: {
            Text(String(localized: "删除后，所有使用它模型的 Agent 会切换到其他来源或失去这些模型。"))
        }
        .confirmationDialog(
            String(localized: "移除密钥 \(pendingKeyRemoval?.displayName ?? "")？"),
            isPresented: Binding(
                get: { pendingKeyRemoval != nil },
                set: { if !$0 { pendingKeyRemoval = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(String(localized: "移除"), role: .destructive) {
                if let key = pendingKeyRemoval, let client = app.client {
                    Task { _ = await activeVM.removeKey(client: client, id: providerID, ref: key.id) }
                }
                pendingKeyRemoval = nil
            }
            Button(String(localized: "取消"), role: .cancel) { pendingKeyRemoval = nil }
        }
    }

    // MARK: - 头部
    private func header(_ provider: ProviderDTO) -> some View {
        VStack(spacing: 13) {
            HStack(spacing: 13) {
                MagpieIconView(icon: provider.icon ?? provider.id, name: provider.name, size: 50, cornerRadius: 11)

                VStack(alignment: .leading, spacing: 4) {
                    TextField(provider.name, text: $nameDraft)
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(MagpieTheme.textPrimary)
                        .textInputAutocapitalization(.never)

                    HStack(spacing: 6) {
                        Text(provider.id)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(MagpieTheme.textMuted)

                        if let preset = provider.preset, !preset.isEmpty {
                            MagpieStatusChip(text: preset.uppercased(), color: MagpieTheme.accent)
                        }
                        if provider.isOff {
                            MagpieStatusChip(text: String(localized: "已停用"), color: MagpieTheme.amber)
                        }
                        if provider.key?.isOptional == true {
                            MagpieStatusChip(text: String(localized: "Key 可选"), color: MagpieTheme.textMuted)
                        }
                    }

                    if let website = provider.website, let url = URL(string: website) {
                        Link(destination: url) {
                            HStack(spacing: 3) {
                                Text(url.host ?? website)
                                Image(systemName: "arrow.up.right")
                            }
                            .font(.caption2)
                            .foregroundStyle(MagpieTheme.accent)
                        }
                    }
                }

                Spacer(minLength: 4)

                Toggle("", isOn: Binding(
                    get: { !provider.isOff },
                    set: { on in
                        guard let client = app.client else { return }
                        Task { await activeVM.toggle(client: client, id: provider.id, turnOn: on) }
                    }
                ))
                .labelsHidden()
                .tint(MagpieTheme.green)
            }

            if let key = provider.key, key.isSet {
                Divider().background(MagpieTheme.borderSubtle)
                HStack(spacing: 8) {
                    Image(systemName: "key.fill")
                        .font(.caption)
                        .foregroundStyle(MagpieTheme.accent)
                    Text(key.masked ?? String(localized: "已设置"))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(MagpieTheme.textSecondary)
                    Spacer()
                    if let exposed = provider.exposed {
                        Text(String(localized: "\(exposed) 个模型可用"))
                            .font(.caption2)
                            .foregroundStyle(MagpieTheme.textMuted)
                    }
                }
            }
        }
        .magpieCard()
    }

    // MARK: - 快速操作
    private func quickActions(_ provider: ProviderDTO) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 9) {
                quickActionButton(
                    String(localized: "获取模型"),
                    icon: "arrow.triangle.2.circlepath",
                    tint: MagpieTheme.accent,
                    busy: isRefreshingModels
                ) {
                    refreshModels(provider)
                }

                quickActionButton(
                    String(localized: "测试连接"),
                    icon: "bolt.fill",
                    tint: MagpieTheme.green,
                    busy: isTesting
                ) {
                    runTest(id: provider.id)
                }

                quickActionButton(
                    String(localized: "检查余额"),
                    icon: "creditcard.fill",
                    tint: MagpieTheme.amber,
                    busy: isCheckingBalance
                ) {
                    checkBalance(provider)
                }
            }

            if let refreshMessage {
                quickMessageRow(refreshMessage, color: MagpieTheme.accent)
            }
            if let balanceMessage {
                quickMessageRow(balanceMessage, color: MagpieTheme.amber)
            }
            if let testResponse {
                quickMessageRow(
                    String(localized: "连通性 \(testResponse.results.filter { $0.succeeded }.count)/\(testResponse.results.count) 个端点通过"),
                    color: testResponse.results.allSatisfy { $0.succeeded } ? MagpieTheme.green : MagpieTheme.amber
                )
            }
            if let testError {
                quickMessageRow(testError, color: MagpieTheme.red)
            }
        }
    }

    private func quickActionButton(
        _ title: String,
        icon: String,
        tint: Color,
        busy: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                if busy {
                    ProgressView().controlSize(.small)
                        .frame(height: 16)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .frame(height: 16)
                }
                Text(title)
                    .font(.system(size: 10.5, weight: .semibold))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .foregroundStyle(tint)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(tint.opacity(0.16), lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
        .disabled(busy)
    }

    private func quickMessageRow(_ text: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 10))
            Text(text)
                .font(.caption2)
                .lineLimit(3)
            Spacer(minLength: 0)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    // MARK: - 连接
    private var connectionSection: some View {
        editorSection(String(localized: "连接与密钥"), icon: "point.3.connected.trianglepath.dotted", tint: MagpieTheme.accent) {
            VStack(alignment: .leading, spacing: 12) {
                Text(String(localized: "API Key"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MagpieTheme.textSecondary)

                HStack(spacing: 8) {
                    if isKeyVisible {
                        TextField(String(localized: "粘贴新 Key（留空保持原值）"), text: $keyDraft)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    } else {
                        SecureField(String(localized: "粘贴新 Key（留空保持原值）"), text: $keyDraft)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                    Button {
                        isKeyVisible.toggle()
                    } label: {
                        Image(systemName: isKeyVisible ? "eye.slash" : "eye")
                            .foregroundStyle(MagpieTheme.textMuted)
                    }
                    .buttonStyle(.plain)
                }
                .font(.subheadline)
                .padding(10)
                .background(MagpieTheme.cardSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                if provider?.key?.isSet == true {
                    Button {
                        revealKey()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "eye.fill")
                            Text(String(localized: "查看已保存的 Key"))
                        }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(MagpieTheme.accent)
                    }
                    .buttonStyle(.plain)
                }

                toggleRow(
                    String(localized: "允许联网搜索"),
                    subtitle: String(localized: "该厂商自身提供 Web Search"),
                    icon: "globe",
                    tint: MagpieTheme.cyan,
                    isOn: $searchesDraft
                )

                toggleRow(
                    String(localized: "免脱敏发送"),
                    subtitle: String(localized: "发往该 Provider 的请求跳过脱敏"),
                    icon: "shield.slash",
                    tint: MagpieTheme.amber,
                    isOn: $unredactedDraft
                )

                DisclosureGroup(isExpanded: $showingAdvanced) {
                    VStack(spacing: 10) {
                        endpointField(String(localized: "Chat Completions URL"), text: $chatDraft, placeholder: "https://…/v1")
                        endpointField(String(localized: "Responses URL"), text: $responsesDraft, placeholder: "https://…/v1")
                        endpointField(String(localized: "Anthropic Messages URL"), text: $anthropicDraft, placeholder: "https://…")
                        endpointField(String(localized: "Gemini URL"), text: $geminiDraft, placeholder: "https://…/v1beta")
                        endpointField(String(localized: "代理"), text: $proxyDraft, placeholder: "http://127.0.0.1:7890")
                    }
                    .padding(.top, 8)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "slider.horizontal.3")
                        Text(String(localized: "高级端点与网络"))
                            .font(.caption.weight(.semibold))
                        Spacer()
                    }
                    .foregroundStyle(MagpieTheme.textSecondary)
                }
            }
            .padding(14)
        }
    }

    private func endpointField(_ title: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(MagpieTheme.textMuted)
            TextField(placeholder, text: text)
                .font(.system(size: 11, design: .monospaced))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .padding(8)
                .background(MagpieTheme.cardSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
    }

    // MARK: - 多密钥
    private func keysSection(_ provider: ProviderDTO) -> some View {
        editorSection(
            String(localized: "密钥与账号"),
            icon: "key.horizontal.fill",
            tint: MagpieTheme.amber
        ) {
            VStack(spacing: 0) {
                if let keys = provider.keyList, !keys.isEmpty {
                    ForEach(Array(keys.enumerated()), id: \.offset) { index, key in
                        keyRow(key)
                        if index < keys.count - 1 {
                            Divider()
                                .background(MagpieTheme.borderSubtle)
                                .padding(.leading, 52)
                        }
                    }
                } else {
                    Text(String(localized: "还没有多个密钥；在上方填写主 Key 即可使用。"))
                        .font(.caption)
                        .foregroundStyle(MagpieTheme.textMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                }

                Divider().background(MagpieTheme.borderSubtle)

                HStack(spacing: 10) {
                    Button {
                        showingAddKey = true
                    } label: {
                        Label(String(localized: "添加密钥"), systemImage: "plus.circle.fill")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(MagpieTheme.accent)

                    Spacer()

                    Text(String(localized: "请求会按顺序尝试已启用的密钥"))
                        .font(.caption2)
                        .foregroundStyle(MagpieTheme.textMuted)
                }
                .padding(14)
            }
        }
    }

    private func keyRow(_ key: ProviderDTO.KeyItemDTO) -> some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(key.on == false ? MagpieTheme.pill : MagpieTheme.accentSoft)
                    .frame(width: 30, height: 30)
                Image(systemName: "key.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(key.on == false ? MagpieTheme.textMuted : MagpieTheme.accent)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(key.displayName)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(key.on == false ? MagpieTheme.textMuted : MagpieTheme.textPrimary)
                        .lineLimit(1)

                    if key.active == true {
                        MagpieStatusChip(text: String(localized: "当前"), color: MagpieTheme.green)
                    }
                    if let protocolLabel = key.protocolLabel {
                        MagpieStatusChip(text: protocolLabel, color: MagpieTheme.cyan)
                    }
                }

                if let masked = key.masked {
                    Text(masked)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(MagpieTheme.textMuted)
                        .lineLimit(1)
                }

                if let rest = key.rest {
                    let restText: String = {
                        if let why = rest.why, !why.isEmpty { return why }
                        if rest.notice == true { return String(localized: "上游限额提醒") }
                        return String(localized: "冷却中")
                    }()
                    Text(restText)
                        .font(.caption2)
                        .foregroundStyle(rest.notice == true ? MagpieTheme.amber : MagpieTheme.red)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 4)

            Toggle("", isOn: Binding(
                get: { key.on ?? true },
                set: { on in
                    guard let client = app.client else { return }
                    Task {
                        _ = await activeVM.toggleKey(
                            client: client,
                            id: providerID,
                            ref: key.id,
                            on: on
                        )
                    }
                }
            ))
            .labelsHidden()
            .tint(MagpieTheme.green)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contextMenu {
            if key.active != true {
                Button {
                    guard let client = app.client else { return }
                    Task { _ = await activeVM.useKey(client: client, id: providerID, ref: key.id) }
                } label: {
                    Label(String(localized: "设为当前密钥"), systemImage: "checkmark.circle")
                }
            }
            Button(role: .destructive) {
                pendingKeyRemoval = key
            } label: {
                Label(String(localized: "移除密钥"), systemImage: "trash")
            }
        }
    }

    // MARK: - 模型
    private func modelsSection(_ provider: ProviderDTO) -> some View {
        editorSection(String(localized: "模型"), icon: "cpu.fill", tint: MagpieTheme.purple) {
            VStack(spacing: 0) {
                modelToolbar(provider)

                Divider().background(MagpieTheme.borderSubtle)

                modelSearchBar

                if let models = provider.models, !models.isEmpty {
                    modelChips(models)
                } else {
                    Text(String(localized: "该厂商还没有返回模型列表；点「拉取」获取。"))
                        .font(.caption2)
                        .foregroundStyle(MagpieTheme.textMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 12)
                }

                let embedCount = provider.embedIds?.count ?? 0
                let rerankCount = provider.rerankIds?.count ?? 0
                if embedCount > 0 || rerankCount > 0 {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(MagpieTheme.cyan)
                        Text(String(localized: "检索模型：\(embedCount) 个嵌入 · \(rerankCount) 个重排"))
                            .font(.caption2)
                            .foregroundStyle(MagpieTheme.textMuted)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
                }

                if let refreshMessage {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 10))
                        Text(refreshMessage)
                            .font(.caption2)
                            .lineLimit(3)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(MagpieTheme.accent)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
                }

                Divider().background(MagpieTheme.borderSubtle)

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "waveform.path.ecg")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(MagpieTheme.green)
                        Text(String(localized: "模型测试"))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(MagpieTheme.textPrimary)
                        Spacer()
                        if isTestingModels {
                            Button(String(localized: "停止")) {
                                stopTest()
                            }
                            .font(.caption.weight(.semibold))
                            .buttonStyle(.plain)
                            .foregroundStyle(MagpieTheme.red)
                        } else {
                            Button(String(localized: "测试选中")) {
                                runModelTest(all: true)
                            }
                            .font(.caption.weight(.semibold))
                            .buttonStyle(.plain)
                            .foregroundStyle(MagpieTheme.amber)
                            .disabled(selectedModels.isEmpty)
                        }
                    }

                    Text(String(localized: "每个模型发送一次真实的最小请求，按厂商价格计费。"))
                        .font(.caption2)
                        .foregroundStyle(MagpieTheme.textMuted)

                    if let testError {
                        Text(testError)
                            .font(.caption)
                            .foregroundStyle(MagpieTheme.red)
                            .textSelection(.enabled)
                    }

                    if let response = modelTestResponse {
                        HStack(spacing: 6) {
                            Image(systemName: response.results.allSatisfy { $0.succeeded } ? "checkmark.circle.fill" : "info.circle.fill")
                                .foregroundStyle(response.results.allSatisfy { $0.succeeded } ? MagpieTheme.green : MagpieTheme.amber)
                            Text(String(localized: "\(response.results.filter { $0.succeeded }.count)/\(response.results.count) 个模型通过"))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(MagpieTheme.textPrimary)
                            Spacer()
                        }

                        VStack(spacing: 0) {
                            ForEach(Array(response.results.enumerated()), id: \.offset) { index, result in
                                testResultRow(result)
                                if index < response.results.count - 1 {
                                    Divider()
                                        .background(MagpieTheme.borderSubtle)
                                        .padding(.leading, 8)
                                }
                            }
                        }
                    }
                }
                .padding(14)

                Divider().background(MagpieTheme.borderSubtle)

                Button {
                    forgetModelList()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "trash.slash")
                            .font(.system(size: 11, weight: .semibold))
                        Text(String(localized: "忘记厂商模型列表（下次重新拉取）"))
                            .font(.caption)
                        Spacer()
                    }
                    .foregroundStyle(MagpieTheme.textMuted)
                    .padding(14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - 模型工具条与胶囊
    private func modelToolbar(_ provider: ProviderDTO) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "已选 \(selectedModels.count) / \((provider.models ?? []).count)"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MagpieTheme.textSecondary)
                Text(String(localized: "点按模型切换是否对外提供；改动在右上角保存后生效"))
                    .font(.caption2)
                    .foregroundStyle(MagpieTheme.textMuted)
            }

            Spacer()

            Button {
                refreshModels(provider)
            } label: {
                if isRefreshingModels {
                    ProgressView().controlSize(.small)
                } else {
                    Label(String(localized: "拉取"), systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption.weight(.semibold))
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(MagpieTheme.accent)
            .disabled(isRefreshingModels)

            Button {
                runModelTest(all: true)
            } label: {
                if isTestingModels {
                    ProgressView().controlSize(.small)
                } else {
                    Label(String(localized: "测试"), systemImage: "bolt.fill")
                        .font(.caption.weight(.semibold))
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(MagpieTheme.green)
            .disabled(isTestingModels || selectedModels.isEmpty)

            Menu {
                Button(String(localized: "全选")) {
                    selectedModels = Set((provider.models ?? []).map(\.id))
                    noModelsDraft = false
                }
                Button(String(localized: "清空（不提供任何模型）")) {
                    selectedModels.removeAll()
                    noModelsDraft = true
                }
                Divider()
                if isTestingModels {
                    Button(String(localized: "停止测试"), role: .destructive) {
                        stopTest()
                    }
                }
                Button(String(localized: "忘记厂商列表"), role: .destructive) {
                    forgetModelList()
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(MagpieTheme.textMuted)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
    }

    private var modelSearchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(MagpieTheme.textMuted)
            TextField(String(localized: "搜索模型…"), text: $modelSearch)
                .font(.system(size: 12))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !modelSearch.isEmpty {
                Button {
                    modelSearch = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(MagpieTheme.textMuted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(MagpieTheme.cardSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func modelChips(_ models: [ProviderModelDTO]) -> some View {
        let query = modelSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = query.isEmpty
            ? models
            : models.filter {
                $0.displayName.localizedCaseInsensitiveContains(query)
                    || $0.id.localizedCaseInsensitiveContains(query)
            }

        return VStack(alignment: .leading, spacing: 8) {
            if filtered.isEmpty {
                Text(String(localized: "没有匹配的模型"))
                    .font(.caption2)
                    .foregroundStyle(MagpieTheme.textMuted)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 150), spacing: 8)],
                    alignment: .leading,
                    spacing: 8
                ) {
                    ForEach(Array(filtered.enumerated()), id: \.offset) { index, model in
                        modelChip(model)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            }
        }
    }

    private func modelChip(_ model: ProviderModelDTO) -> some View {
        let selected = selectedModels.contains(model.id)
        return Button {
            if selected {
                selectedModels.remove(model.id)
                if selectedModels.isEmpty { noModelsDraft = true }
            } else {
                selectedModels.insert(model.id)
                noModelsDraft = false
            }
            MagpieHaptics.light()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 9, weight: .bold))
                Text(model.displayName)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .lineLimit(1)
                if let context = model.context, context > 0 {
                    Text(UsageDTO.formatTokens(context))
                        .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(MagpieTheme.textMuted)
                }
                if model.images == true {
                    Image(systemName: "photo")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(MagpieTheme.textMuted)
                }
                if model.disabled != nil {
                    Image(systemName: "nosign")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(MagpieTheme.red)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? MagpieTheme.accentSoft : MagpieTheme.pill)
            .foregroundStyle(selected ? MagpieTheme.accent : MagpieTheme.textSecondary)
            .opacity(model.disabled != nil ? 0.55 : 1)
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(
                    selected ? MagpieTheme.accent.opacity(0.35) : MagpieTheme.borderSubtle,
                    lineWidth: 0.7
                )
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                openModelSettings(model)
            } label: {
                Label(String(localized: "模型设置…"), systemImage: "slider.horizontal.3")
            }
            Button {
                runSingleModelTest(model.id)
            } label: {
                Label(String(localized: "测试此模型"), systemImage: "bolt.fill")
            }
            Button {
                UIPasteboard.general.string = model.id
                MagpieHaptics.success()
            } label: {
                Label(String(localized: "复制模型 ID"), systemImage: "doc.on.doc")
            }
        }
    }

    private func runSingleModelTest(_ id: String) {
        guard let client = app.client else { return }
        isTestingModels = true
        modelTestResponse = nil
        testError = nil
        let run = UUID().uuidString
        testRun = run
        Task {
            defer { isTestingModels = false }
            if let response = await activeVM.testResults(
                client: client,
                id: providerID,
                models: [id],
                run: run
            ) {
                modelTestResponse = response
            } else {
                testError = activeVM.testResult ?? String(localized: "模型测试失败")
            }
            if testRun == run { testRun = "" }
        }
    }

    private func openModelSettings(_ model: ProviderModelDTO) {
        settingsModelID = model.id
        settingsModelName = model.name ?? ""
        settingsModelContext = contextsDraft[model.id].map(String.init) ?? ""
        settingsModelOutput = outputsDraft[model.id].map(String.init) ?? ""
        settingsModelEfforts = Set(model.kept ?? model.efforts ?? [])
        settingsModelAvailableEfforts = model.efforts ?? []
        settingsModelImages = model.images ?? false
    }

    private func applyModelSettings(_ modelID: String) async -> Bool {
        guard let client = app.client else { return false }
        let name = settingsModelName.trimmingCharacters(in: .whitespacesAndNewlines)
        let contextText = settingsModelContext.trimmingCharacters(in: .whitespacesAndNewlines)
        let outputText = settingsModelOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        if (!contextText.isEmpty && Int(contextText) == nil)
            || (!outputText.isEmpty && Int(outputText) == nil) {
            return false
        }
        let renamed = await activeVM.renameModel(
            client: client,
            providerID: providerID,
            model: modelID,
            name: name
        )
        let effortsSaved = await activeVM.setModelEfforts(
            client: client,
            id: providerID,
            model: modelID,
            efforts: Array(settingsModelEfforts).sorted()
        )
        let imagesSaved = await activeVM.setModelImages(
            client: client,
            id: providerID,
            model: modelID,
            images: settingsModelImages
        )
        if let context = Int(contextText) {
            contextsDraft[modelID] = context
        } else {
            contextsDraft.removeValue(forKey: modelID)
        }
        if let output = Int(outputText) {
            outputsDraft[modelID] = output
        } else {
            outputsDraft.removeValue(forKey: modelID)
        }
        return renamed && effortsSaved && imagesSaved
    }

    // MARK: - 订阅账号
    private func subscriptionSection(_ provider: ProviderDTO) -> some View {
        editorSection(String(localized: "订阅账号"), icon: "person.badge.key.fill", tint: MagpieTheme.green) {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    MagpieIconView(
                        icon: provider.icon ?? provider.id,
                        name: provider.name,
                        size: 30,
                        cornerRadius: 7
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(provider.accountUser ?? provider.accountAgentName ?? provider.name)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(MagpieTheme.textPrimary)
                            .lineLimit(1)
                        HStack(spacing: 5) {
                            if let plan = provider.accountPlan, !plan.isEmpty {
                                MagpieStatusChip(text: plan, color: MagpieTheme.green)
                            }
                            if let agentName = provider.accountAgentName, !agentName.isEmpty {
                                Text(agentName)
                                    .font(.caption2)
                                    .foregroundStyle(MagpieTheme.textMuted)
                            }
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)

                let logins = uniqueLogins(provider.accountLogins)
                if logins.count > 1 {
                    ForEach(Array(logins.enumerated()), id: \.offset) { index, user in
                        Divider().background(MagpieTheme.borderSubtle).padding(.leading, 54)
                        HStack(spacing: 10) {
                            Image(systemName: user == provider.accountUser ? "person.crop.circle.fill.badge.checkmark" : "person.crop.circle")
                                .font(.system(size: 16))
                                .foregroundStyle(user == provider.accountUser ? MagpieTheme.green : MagpieTheme.textMuted)
                            Text(user)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(MagpieTheme.textPrimary)
                                .lineLimit(1)
                            Spacer()
                            if user != provider.accountUser {
                                Button(String(localized: "切换")) {
                                    guard let client = app.client else { return }
                                    Task {
                                        await activeVM.switchLogin(
                                            client: client,
                                            agent: provider.accountAgent ?? provider.preset ?? provider.id,
                                            user: user
                                        )
                                    }
                                }
                                .font(.caption.weight(.semibold))
                                .buttonStyle(.plain)
                                .foregroundStyle(MagpieTheme.accent)
                            }
                            Menu {
                                Button {
                                    accountSettingsUser = user
                                } label: {
                                    Label(String(localized: "账号设置…"), systemImage: "slider.horizontal.3")
                                }
                            } label: {
                                Image(systemName: "ellipsis")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(MagpieTheme.textMuted)
                                    .frame(width: 22, height: 22)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                    }
                }

                rowDivider

                toggleRow(
                    String(localized: "保持登录在固定账号"),
                    subtitle: String(localized: "额度不足时不把它切到下一个账号"),
                    icon: "pin.fill",
                    tint: MagpieTheme.green,
                    isOn: Binding(
                        get: { provider.keepLogin ?? false },
                        set: { on in
                            guard let client = app.client else { return }
                            Task {
                                await activeVM.setKeepLogin(
                                    client: client,
                                    id: provider.id,
                                    on: on,
                                    keepAs: keepLoginAsDraft
                                )
                            }
                        }
                    )
                )

                if provider.keepLogin == true {
                    rowDivider
                    HStack(spacing: 8) {
                        TextField(String(localized: "固定到的账号名（留空=第一个）"), text: $keepLoginAsDraft)
                            .font(.system(size: 11, design: .monospaced))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(8)
                            .background(MagpieTheme.cardSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        Button(String(localized: "应用")) {
                            guard let client = app.client else { return }
                            Task {
                                await activeVM.setKeepLogin(
                                    client: client,
                                    id: provider.id,
                                    on: true,
                                    keepAs: keepLoginAsDraft
                                )
                            }
                        }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.plain)
                        .foregroundStyle(MagpieTheme.accent)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }

                rowDivider

                toggleRow(
                    String(localized: "只切换登录"),
                    subtitle: String(localized: "只移动 Codex / Claude 自身的登录，不把请求经 magpie 路由"),
                    icon: "arrow.left.arrow.right",
                    tint: MagpieTheme.cyan,
                    isOn: Binding(
                        get: { provider.switchOnly ?? false },
                        set: { on in
                            guard let client = app.client else { return }
                            Task { await activeVM.setSwitchOnly(client: client, id: provider.id, on: on) }
                        }
                    )
                )

                rowDivider

                toggleRow(
                    String(localized: "自动重启 Codex App"),
                    subtitle: String(localized: "账号切换后自动重启 Codex 的应用服务"),
                    icon: "arrow.clockwise.circle",
                    tint: MagpieTheme.amber,
                    isOn: Binding(
                        get: { provider.restartApp ?? false },
                        set: { on in
                            guard let client = app.client else { return }
                            Task { await activeVM.setRestartApp(client: client, id: provider.id, on: on) }
                        }
                    )
                )
            }
        }
    }

    // MARK: - 模型行为
    private func behaviorSection(_ provider: ProviderDTO) -> some View {
        editorSection(String(localized: "模型行为"), icon: "slider.horizontal.below.rectangle", tint: MagpieTheme.purple) {
            VStack(spacing: 0) {
                toggleRow(
                    String(localized: "仅通过路由组使用"),
                    subtitle: String(localized: "模型不直接出现在 Agent 的模型列表里，只经路由组调用"),
                    icon: "square.3.layers.3d",
                    tint: MagpieTheme.cyan,
                    isOn: $unlistedDraft
                )

                rowDivider

                toggleRow(
                    String(localized: "不直接提供模型"),
                    subtitle: String(localized: "Select none：一个模型都不对外提供，但仍可留在分组里"),
                    icon: "nosign",
                    tint: MagpieTheme.textSecondary,
                    isOn: Binding(
                        get: { noModelsDraft },
                        set: { on in
                            noModelsDraft = on
                            if on { selectedModels = [] }
                        }
                    )
                )

                rowDivider

                toggleRow(
                    String(localized: "每族只留最新"),
                    subtitle: String(localized: "没有显式选择时，每个模型家族只提供最新的一个"),
                    icon: "star.circle.fill",
                    tint: MagpieTheme.amber,
                    isOn: $bestInFamilyDraft
                )

                rowDivider

                toggleRow(
                    String(localized: "不拉取厂商列表"),
                    subtitle: String(localized: "只提供手动按 ID 添加的模型"),
                    icon: "arrow.down.circle.dotted",
                    tint: MagpieTheme.green,
                    isOn: $listOffDraft
                )

                rowDivider

                HStack(spacing: 12) {
                    editorGlyph("tag.fill", tint: Color(hex: "ec4899"))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "价格倍率"))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(MagpieTheme.textPrimary)
                        Text(String(localized: "按官方价折算的自定义计费，0 为不折算"))
                            .font(.caption2)
                            .foregroundStyle(MagpieTheme.textMuted)
                    }
                    Spacer(minLength: 8)
                    let safePrice = Binding<Double>(
                        get: { min(max(priceRateDraft, 0), 100) },
                        set: { priceRateDraft = $0 }
                    )
                    Stepper(value: safePrice, in: 0...100, step: 0.05) {
                        Text(safePrice.wrappedValue <= 0 ? String(localized: "原价") : String(format: "×%.2f", safePrice.wrappedValue))
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(MagpieTheme.textSecondary)
                            .frame(minWidth: 44, alignment: .trailing)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
    }

    // MARK: - 请求与网络（官方编辑器高级项）
    private func requestSection(_ provider: ProviderDTO) -> some View {
        editorSection(String(localized: "请求与网络"), icon: "network.badge.shield.half.filled", tint: MagpieTheme.cyan) {
            VStack(spacing: 0) {
                DisclosureGroup(isExpanded: $showingRequestAdvanced) {
                    VStack(alignment: .leading, spacing: 12) {
                        textEditorBlock(
                            title: String(localized: "请求头"),
                            hint: String(localized: "每行一条，例如 X-Custom: value"),
                            text: $headersDraft,
                            minHeight: 80
                        )

                        textEditorBlock(
                            title: String(localized: "Extra body (JSON)"),
                            hint: String(localized: "并入每个请求体，例如 {\"enable_thinking\": true}"),
                            text: $extraBodyDraft,
                            minHeight: 80
                        )

                        fieldBlockLite(title: String(localized: "透传的响应头"), text: $replyHeadersDraft, placeholder: "x-request-id, x-ratelimit-remaining")
                        fieldBlockLite(title: String(localized: "透传的请求头"), text: $passHeadersDraft, placeholder: "anthropic-beta, x-trace-id")

                        pickerRow(
                            String(localized: "认证头"),
                            subtitle: String(localized: "第三方 Anthropic API 上 Key 放在哪个头"),
                            icon: "key.horizontal.fill",
                            tint: MagpieTheme.amber,
                            selection: $authHeaderDraft,
                            options: [
                                ("", String(localized: "默认（两个都发）")),
                                ("x-api-key", "x-api-key"),
                                ("bearer", "Authorization: Bearer")
                            ]
                        )
                    }
                    .padding(.top, 10)
                    .padding(.bottom, 4)
                } label: {
                    disclosureLabel(String(localized: "请求头与 Body"), icon: "doc.badge.gearshape")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)

                rowDivider

                DisclosureGroup(isExpanded: $showingNetworkAdvanced) {
                    VStack(spacing: 0) {
                        toggleRow(
                            String(localized: "发送 Agent 自己的 User-Agent"),
                            subtitle: String(localized: "不使用 magpie 的统一 UA"),
                            icon: "person.crop.circle.badge.checkmark",
                            tint: MagpieTheme.cyan,
                            isOn: $passUserAgentDraft

                        )
                        if provider.takesPassErrors == true {
                            rowDivider
                            toggleRow(
                                String(localized: "透传厂商错误"),
                                subtitle: String(localized: "把厂商的原始错误原样返回给 Agent"),
                                icon: "exclamationmark.bubble.fill",
                                tint: MagpieTheme.red,
                                isOn: $passErrorsDraft
                            )
                        }
                        if provider.carriesCompaction == true {
                            rowDivider
                            toggleRow(
                                String(localized: "Codex 原生压缩"),
                                subtitle: String(localized: "Codex 的压缩请求按原样发给厂商"),
                                icon: "archivebox.fill",
                                tint: MagpieTheme.purple,
                                isOn: $nativeCompactionDraft
                            )
                        }
                        rowDivider
                        toggleRow(
                            String(localized: "429 后不冷却"),
                            subtitle: String(localized: "配额拒绝或 429 之后仍照常尝试，不把它放到一边"),
                            icon: "clock.badge.xmark",
                            tint: MagpieTheme.amber,
                            isOn: $limitRestOffDraft
                        )
                        if provider.takesSocket == true {
                            rowDivider
                            pickerRow(
                                String(localized: "Responses WebSocket"),
                                subtitle: String(localized: "Responses 请求是否走 WebSocket"),
                                icon: "bolt.horizontal.circle",
                                tint: MagpieTheme.green,
                                selection: $socketDraft,
                                options: [
                                    ("", String(localized: "自动")),
                                    ("auto", "Auto"),
                                    ("on", String(localized: "开启")),
                                    ("off", String(localized: "关闭"))
                                ]
                            )
                        }
                        if provider.takesInsecureTLS == true {
                            rowDivider
                            toggleRow(
                                String(localized: "跳过证书校验"),
                                subtitle: String(localized: "信任该地址的自签名证书（仅用于你自己的服务）"),
                                icon: "lock.slash.fill",
                                tint: MagpieTheme.red,
                                isOn: $insecureTLSDraft
                            )
                        }
                        rowDivider
                        toggleRow(
                            String(localized: "只用 HTTP/1.1"),
                            subtitle: String(localized: "不协商 HTTP/2，兼容老旧代理"),
                            icon: "arrow.left.arrow.right.circle",
                            tint: MagpieTheme.textSecondary,
                            isOn: $http1Draft
                        )
                    }
                } label: {
                    disclosureLabel(String(localized: "传输与兼容"), icon: "ant.fill")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
        }
    }

    // MARK: - 自定义端点（仅自定义 Provider）
    private var customEndpointSection: some View {
        editorSection(String(localized: "自定义端点与余额"), icon: "point.topleft.down.to.point.bottomright.curvepath", tint: MagpieTheme.amber) {
            VStack(alignment: .leading, spacing: 12) {
                fieldBlockLite(
                    title: String(localized: "模型列表 URL"),
                    text: $modelsURLDraft,
                    placeholder: "https://api.example.com/v1/models"
                )

                Text(String(localized: "余额查询"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MagpieTheme.textSecondary)

                fieldBlockLite(title: String(localized: "URL"), text: $balanceURLDraft, placeholder: "https://api.example.com/user/balance")

                HStack(spacing: 10) {
                    fieldBlockLite(title: String(localized: "路径"), text: $balancePathDraft, placeholder: "data.balance")
                    Picker("", selection: $balanceMethodDraft) {
                        Text("GET").tag("GET")
                        Text("POST").tag("POST")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 130)
                }

                fieldBlockLite(title: String(localized: "余额 Token"), text: $balanceTokenDraft, placeholder: String(localized: "可选的查询用 Token"))
            }
            .padding(14)
        }
    }

    private func disclosureLabel(_ title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(MagpieTheme.textSecondary)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(MagpieTheme.textSecondary)
            Spacer()
        }
    }

    private func textEditorBlock(
        title: String,
        hint: String,
        text: Binding<String>,
        minHeight: CGFloat
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(MagpieTheme.textMuted)
            TextEditor(text: text)
                .font(.system(size: 11, design: .monospaced))
                .scrollContentBackground(.hidden)
                .frame(minHeight: minHeight)
                .padding(8)
                .background(MagpieTheme.cardSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Text(hint)
                .font(.caption2)
                .foregroundStyle(MagpieTheme.textMuted)
        }
    }

    private func fieldBlockLite(title: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(MagpieTheme.textMuted)
            TextField(placeholder, text: text)
                .font(.system(size: 11, design: .monospaced))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(9)
                .background(MagpieTheme.cardSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    // MARK: - 路由
    private var routingSection: some View {
        editorSection(String(localized: "路由与并发"), icon: "arrow.triangle.branch", tint: MagpieTheme.green) {
            VStack(spacing: 0) {
                pickerRow(
                    String(localized: "密钥分发"),
                    subtitle: String(localized: "多个 Key / 账号之间如何选择"),
                    icon: "arrow.triangle.2.circlepath",
                    tint: MagpieTheme.green,
                    selection: $routingDraft,
                    options: [
                        ("", String(localized: "额度优先（默认）")),
                        ("order", String(localized: "按顺序")),
                        ("drain", String(localized: "逐个用完")),
                        ("rotate", String(localized: "轮询")),
                        ("usage", String(localized: "用量最少")),
                        ("pace", String(localized: "到期前用完")),
                        ("weight", String(localized: "按权重")),
                        ("free", String(localized: "免费优先")),
                        ("fast", String(localized: "速度优先"))
                    ]
                )

                rowDivider

                pickerRow(
                    String(localized: "对话保持"),
                    subtitle: String(localized: "同一会话是否固定在同一账号"),
                    icon: "person.wave.2",
                    tint: MagpieTheme.cyan,
                    selection: $affinityDraft,
                    options: [
                        ("", String(localized: "自动")),
                        ("session", String(localized: "整个会话")),
                        ("turn", String(localized: "仅当前轮")),
                        ("off", String(localized: "不保持")),
                        ("strict", String(localized: "严格保持"))
                    ]
                )

                rowDivider

                toggleRow(
                    String(localized: "限流后置"),
                    subtitle: String(localized: "仍有额度但被限流的账号排到后面"),
                    icon: "arrow.down.to.line",
                    tint: MagpieTheme.amber,
                    isOn: $sinkDraft
                )

                rowDivider

                toggleRow(
                    String(localized: "优先使用"),
                    subtitle: String(localized: "在智能路由中优先于其他 Provider"),
                    icon: "star.fill",
                    tint: MagpieTheme.amber,
                    isOn: $useFirstDraft
                )

                rowDivider

                toggleRow(
                    String(localized: "不作为备用"),
                    subtitle: String(localized: "其他模型的请求不会降级到它"),
                    icon: "nosign",
                    tint: MagpieTheme.red,
                    isOn: $noStandInDraft
                )

                rowDivider

                stepperRow(
                    String(localized: "最大并发"),
                    subtitle: String(localized: "每个密钥同时进行的请求数，0 为不限"),
                    icon: "speedometer",
                    tint: MagpieTheme.accent,
                    value: $maxConcurrencyDraft,
                    range: 0...1000,
                    step: 1
                )

                rowDivider

                stepperRow(
                    String(localized: "队列长度"),
                    subtitle: String(localized: "等待中的请求上限，0 为不限"),
                    icon: "list.bullet",
                    tint: MagpieTheme.cyan,
                    value: $queueLimitDraft,
                    range: 0...10000,
                    step: 10
                )

                rowDivider

                stepperRow(
                    String(localized: "队列等待"),
                    subtitle: String(localized: "最长等待时间（秒），0 为不限"),
                    icon: "hourglass",
                    tint: MagpieTheme.amber,
                    value: $queueWaitDraft,
                    range: 0...3600,
                    step: 10
                )

                rowDivider

                stepperRow(
                    String(localized: "每分钟请求"),
                    subtitle: String(localized: "每个密钥每分钟上限，0 为不限"),
                    icon: "gauge.with.dots.needle.50percent",
                    tint: MagpieTheme.purple,
                    value: $maxRPMDraft,
                    range: 0...10000,
                    step: 10
                )
            }
        }
    }

    // MARK: - 测试
    private func testSection(_ provider: ProviderDTO) -> some View {
        editorSection(String(localized: "连通性"), icon: "bolt.horizontal.circle.fill", tint: MagpieTheme.accent) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "向每个 API 端点发送最小请求"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(MagpieTheme.textPrimary)
                        Text(String(localized: "使用当前已保存的密钥，不修改任何设置"))
                            .font(.caption2)
                            .foregroundStyle(MagpieTheme.textMuted)
                    }
                    Spacer()
                    Button {
                        runTest(id: provider.id)
                    } label: {
                        if isTesting {
                            ProgressView().controlSize(.small)
                        } else {
                            Text(String(localized: "开始测试"))
                        }
                    }
                    .buttonStyle(MagpiePrimaryButtonStyle(tint: MagpieTheme.accent))
                    .disabled(isTesting)

                    if isTesting {
                        Button(String(localized: "停止")) {
                            stopTest()
                        }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.plain)
                        .foregroundStyle(MagpieTheme.red)
                    }
                }

                let loginOptions = uniqueLogins(provider.accountLogins)
                if loginOptions.count > 1 {
                    HStack(spacing: 8) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(MagpieTheme.textMuted)
                        Text(String(localized: "测试账号"))
                            .font(.caption)
                            .foregroundStyle(MagpieTheme.textMuted)
                        Spacer()
                        Picker("", selection: $testAccount) {
                            Text(String(localized: "全部账号")).tag("")
                            ForEach(Array(loginOptions.enumerated()), id: \.offset) { _, user in
                                Text(user).tag(user)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .tint(MagpieTheme.textSecondary)
                    }
                }

                if let testError {
                    Text(testError)
                        .font(.caption)
                        .foregroundStyle(MagpieTheme.red)
                        .textSelection(.enabled)
                }

                if let response = testResponse {
                    HStack(spacing: 6) {
                        Image(systemName: response.results.allSatisfy { $0.succeeded } ? "checkmark.circle.fill" : "info.circle.fill")
                            .foregroundStyle(response.results.allSatisfy { $0.succeeded } ? MagpieTheme.green : MagpieTheme.amber)
                        Text(String(localized: "\(response.results.filter { $0.succeeded }.count)/\(response.results.count) 个端点通过"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(MagpieTheme.textPrimary)
                        Spacer()
                    }

                    VStack(spacing: 0) {
                        ForEach(Array(response.results.enumerated()), id: \.offset) { index, result in
                            testResultRow(result)
                            if index < response.results.count - 1 {
                                Divider()
                                    .background(MagpieTheme.borderSubtle)
                                    .padding(.leading, 10)
                            }
                        }
                    }
                }

                // MARK: - 中转质量检测（POST /api/relay-check）
                let allModels = (provider.models ?? []).map(\.id)
                if !allModels.isEmpty {
                    Divider().background(MagpieTheme.borderSubtle)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(String(localized: "中转质量检测"))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(MagpieTheme.textPrimary)
                                Text(String(localized: "对指定模型发起真实问答、工具调用与测速实测"))
                                    .font(.caption2)
                                    .foregroundStyle(MagpieTheme.textMuted)
                            }
                            Spacer()
                            Button {
                                let target = allModels.contains(relayCheckModel) ? relayCheckModel : (allModels.first ?? "")
                                runRelayCheck(providerID: provider.id, model: target)
                            } label: {
                                if isCheckingRelay {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Text(String(localized: "质量检测"))
                                }
                            }
                            .buttonStyle(MagpiePrimaryButtonStyle(tint: MagpieTheme.cyan))
                            .disabled(isCheckingRelay)
                        }

                        HStack(spacing: 8) {
                            Text(String(localized: "检测模型"))
                                .font(.caption)
                                .foregroundStyle(MagpieTheme.textMuted)
                            Spacer()
                            Picker("", selection: $relayCheckModel) {
                                ForEach(allModels.prefix(200), id: \.self) { mid in
                                    Text(mid).tag(mid)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .tint(MagpieTheme.textSecondary)
                        }

                        if let relayCheckError {
                            Text(relayCheckError)
                                .font(.caption)
                                .foregroundStyle(MagpieTheme.red)
                                .textSelection(.enabled)
                        }

                        if let relay = relayCheckResult {
                            HStack(spacing: 6) {
                                Image(systemName: relay.passedCount == relay.parts.count ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                                    .foregroundStyle(relay.passedCount == relay.parts.count ? MagpieTheme.green : MagpieTheme.amber)
                                Text(String(localized: "\(relay.model)：\(relay.passedCount)/\(relay.parts.count) 项通过"))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(MagpieTheme.textPrimary)
                                Spacer()
                            }

                            VStack(spacing: 6) {
                                ForEach(relay.parts) { part in
                                    relayPartRow(part)
                                }
                            }
                        }
                    }
                }
            }
            .padding(14)
        }
    }

    private func relayPartRow(_ part: RelayPartDTO) -> some View {
        let passed = part.ok && part.match
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(passed ? MagpieTheme.green : MagpieTheme.red)
                Text(part.kind)
                    .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(MagpieTheme.textPrimary)
                if let served = part.served, !served.isEmpty {
                    Text(served)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(MagpieTheme.textMuted)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if let ttft = part.ttftMs, ttft > 0 {
                    Text("TTFT \(ttft)ms")
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(MagpieTheme.textSecondary)
                }
                if let tps = part.tps, tps > 0 {
                    Text(String(format: "%.1f tok/s", tps))
                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(MagpieTheme.cyan)
                } else {
                    Text("\(part.ms)ms")
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(MagpieTheme.textMuted)
                }
            }
            if let error = part.error, !error.isEmpty {
                Text(error)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(MagpieTheme.red)
                    .textSelection(.enabled)
            } else if !passed, let want = part.want, let got = part.got {
                Text(String(localized: "期望 \(want)，实际 \(got)"))
                    .font(.caption2)
                    .foregroundStyle(MagpieTheme.amber)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(MagpieTheme.cardSecondary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func runRelayCheck(providerID: String, model: String) {
        guard let client = app.client, !model.isEmpty else { return }
        isCheckingRelay = true
        relayCheckError = nil
        relayCheckResult = nil
        Task {
            defer { isCheckingRelay = false }
            if let res = await activeVM.checkRelay(client: client, provider: providerID, model: model) {
                relayCheckResult = res
                if res.passedCount == res.parts.count { MagpieHaptics.success() }
            } else {
                relayCheckError = activeVM.errorMessage ?? String(localized: "中转检测失败")
            }
        }
    }

    private func egressBanner(_ egress: EgressResultDTO) -> some View {
        let tint: Color = egress.isUnsupported ? MagpieTheme.red : (egress.isSupported ? MagpieTheme.green : MagpieTheme.amber)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: egress.isUnsupported ? "exclamationmark.shield.fill" : "globe")
                    .foregroundStyle(tint)
                Text(
                    egress.isUnsupported
                        ? String(localized: "出口地区不受 Anthropic 支持\(egress.loc.map { " (\($0))" } ?? "")")
                        : (egress.isSupported
                           ? String(localized: "出口地区受支持\(egress.loc.map { " (\($0))" } ?? "")")
                           : String(localized: "出口地区未知"))
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(MagpieTheme.textPrimary)
                Spacer()
                Button {
                    guard let client = app.client else { return }
                    isCheckingEgress = true
                    Task {
                        defer { isCheckingEgress = false }
                        _ = await activeVM.checkEgress(client: client)
                    }
                } label: {
                    if isCheckingEgress {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(String(localized: "重新检测"))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(MagpieTheme.accent)
                    }
                }
                .buttonStyle(.plain)
                .disabled(isCheckingEgress)
            }
            if let via = egress.via, !via.isEmpty {
                Text(String(localized: "通道：\(via)"))
                    .font(.caption2)
                    .foregroundStyle(MagpieTheme.textMuted)
            }
            if let err = egress.error, !err.isEmpty {
                Text(err)
                    .font(.caption2)
                    .foregroundStyle(MagpieTheme.amber)
            }
        }
        .magpieCard(padding: 12)
    }

    private func testResultRow(_ result: ProviderTestResultDTO) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Image(systemName: result.succeeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(result.succeeded ? MagpieTheme.green : MagpieTheme.red)

                Text(result.protocolLabel)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(MagpieTheme.textPrimary)

                if let model = result.model, !model.isEmpty {
                    Text(model)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(MagpieTheme.textMuted)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                if result.succeeded {
                    Text("\(Int(result.ms ?? 0))ms")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(MagpieTheme.green)
                } else if let status = result.status, status > 0 {
                    Text("HTTP \(status)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(MagpieTheme.red)
                }
            }

            if let error = result.error, !error.isEmpty {
                Text(error)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(MagpieTheme.red)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let queued = result.queued, !queued.isEmpty {
                Text(queued)
                    .font(.caption2)
                    .foregroundStyle(MagpieTheme.amber)
            }

            if let v1 = result.v1, !v1.isEmpty {
                Text(String(localized: "此端点应使用：\(v1)"))
                    .font(.caption2)
                    .foregroundStyle(MagpieTheme.accent)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: - 危险操作
    private var dangerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(role: .destructive) {
                showingDeleteAlert = true
            } label: {
                HStack {
                    Spacer()
                    Image(systemName: "trash")
                    Text(String(localized: "删除这个 Provider"))
                    Spacer()
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(MagpieTheme.red)
                .padding(.vertical, 14)
                .background(MagpieTheme.redSoft)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)

            if let saveError {
                Text(saveError)
                    .font(.caption)
                    .foregroundStyle(MagpieTheme.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - 行
    private func editorSection<Content: View>(
        _ title: String,
        icon: String,
        tint: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(tint)
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(MagpieTheme.textMuted)
                Spacer()
            }
            .padding(.horizontal, 4)

            VStack(spacing: 0) {
                content()
            }
            .magpieCard(padding: 0)
        }
    }

    private func toggleRow(
        _ title: String,
        subtitle: String,
        icon: String,
        tint: Color,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: 12) {
            editorGlyph(icon, tint: tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(MagpieTheme.textPrimary)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(MagpieTheme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(MagpieTheme.green)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private func pickerRow(
        _ title: String,
        subtitle: String,
        icon: String,
        tint: Color,
        selection: Binding<String>,
        options: [(String, String)]
    ) -> some View {
        HStack(spacing: 12) {
            editorGlyph(icon, tint: tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(MagpieTheme.textPrimary)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(MagpieTheme.textMuted)
            }
            Spacer(minLength: 8)
            Picker("", selection: selection) {
                ForEach(Array(options.enumerated()), id: \.offset) { item in
                    Text(item.element.1).tag(item.element.0)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .tint(MagpieTheme.textSecondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func stepperRow(
        _ title: String,
        subtitle: String,
        icon: String,
        tint: Color,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        step: Int
    ) -> some View {
        HStack(spacing: 12) {
            editorGlyph(icon, tint: tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(MagpieTheme.textPrimary)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(MagpieTheme.textMuted)
            }
            Spacer(minLength: 8)
            let safeVal = Binding<Int>(
                get: { min(max(value.wrappedValue, range.lowerBound), range.upperBound) },
                set: { value.wrappedValue = $0 }
            )
            Stepper(value: safeVal, in: range, step: step) {
                Text(safeVal.wrappedValue == 0 ? String(localized: "不限") : "\(safeVal.wrappedValue)")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(MagpieTheme.textSecondary)
                    .frame(minWidth: 36, alignment: .trailing)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func editorGlyph(_ icon: String, tint: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tint.opacity(0.13))
                .frame(width: 30, height: 30)
            Image(systemName: icon)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(tint)
        }
    }

    private var rowDivider: some View {
        Divider()
            .background(MagpieTheme.borderSubtle)
            .padding(.leading, 56)
    }

    // MARK: - 生命周期
    private func primeIfNeeded() {
        guard !primed else { return }
        prime(force: false)
    }

    private func prime(force: Bool) {
        guard let p = provider else { return }
        if primed && !force { return }
        primed = true
        nameDraft = p.name
        keyDraft = ""
        chatDraft = p.chat ?? ""
        responsesDraft = p.responses ?? ""
        anthropicDraft = p.anthropic ?? ""
        geminiDraft = p.gemini ?? ""
        proxyDraft = p.proxy ?? ""
        searchesDraft = p.searches ?? false
        unredactedDraft = p.unredacted ?? false
        routingDraft = p.routing ?? ""
        affinityDraft = p.affinity ?? ""
        sinkDraft = p.sink ?? false
        useFirstDraft = p.useFirst ?? false
        noStandInDraft = p.noStandIn ?? false
        maxConcurrencyDraft = p.maxConcurrency ?? 0
        queueLimitDraft = p.queueLimit ?? 0
        queueWaitDraft = p.queueWait ?? 0
        maxRPMDraft = p.maxRPM ?? 0

        unlistedDraft = p.unlisted ?? false
        noModelsDraft = p.noModels ?? false
        bestInFamilyDraft = p.bestInFamily ?? false
        listOffDraft = p.listOff ?? false
        priceRateDraft = p.priceRate ?? 0
        topUpRateDraft = p.topUpRate ?? 0
        connectAgentsDraft = p.connectAgents ?? false
        headersDraft = formatHeaders(p.headers)
        extraBodyDraft = p.extraBody?.prettyText ?? ""
        replyHeadersDraft = (p.replyHeaders ?? []).joined(separator: ", ")
        passHeadersDraft = (p.passHeaders ?? []).joined(separator: ", ")
        insecureTLSDraft = p.insecureTLS ?? false
        http1Draft = p.http1 ?? false
        socketDraft = p.socket ?? ""
        limitRestOffDraft = p.limitRestOff ?? false
        passUserAgentDraft = p.passUserAgent ?? false
        authHeaderDraft = p.authHeader ?? ""
        nativeCompactionDraft = p.nativeCompaction ?? false
        passErrorsDraft = p.passErrors ?? false
        modelsURLDraft = p.modelsURL ?? ""
        balanceURLDraft = p.balanceURL ?? ""
        balancePathDraft = p.balancePath ?? ""
        balanceMethodDraft = (p.balanceMethod?.isEmpty == false) ? p.balanceMethod! : "GET"
        balanceTokenDraft = ""
        keepLoginAsDraft = p.keepLoginAs ?? ""
        contextsDraft = p.contexts ?? [:]
        outputsDraft = p.outputs ?? [:]
        renameIDDraft = p.id

        let all = (p.models ?? []).map(\.id)
        let chosen = p.chosen ?? []
        if p.noModels == true {
            selectedModels = []
        } else {
            selectedModels = Set(chosen.isEmpty ? all : chosen)
        }
        if selectedTestModel.isEmpty
            || (selectedTestModel != "__all__" && !all.contains(selectedTestModel)) {
            selectedTestModel = all.first ?? "__all__"
        }
        if relayCheckModel.isEmpty || !all.contains(relayCheckModel) {
            relayCheckModel = all.first ?? ""
        }
    }

    private func save() {
        guard let client = app.client, let provider else { return }
        saveError = nil

        // extraBody 必须是合法 JSON；解析失败时不提交。
        if !extraBodyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           JSONValue.parse(extraBodyDraft) == nil {
            saveError = String(localized: "Extra body 不是合法的 JSON。")
            return
        }

        let request = buildSaveRequest(provider: provider, newID: provider.id)
        isSaving = true

        Task {
            let ok = await activeVM.save(client: client, request: request)
            if ok {
                // 这两个开关在服务端由独立动作写入，保存请求不会覆盖它们。
                await activeVM.setUseFirst(client: client, id: provider.id, on: useFirstDraft)
                await activeVM.setStandIn(client: client, id: provider.id, noStandIn: noStandInDraft)
                prime(force: true)
                MagpieHaptics.success()
            } else {
                saveError = activeVM.errorMessage ?? String(localized: "保存失败")
            }
            isSaving = false
        }
    }

    /// 官方 Add 的「从现有 Provider 复制」：copyOf 指向来源，new 分配新 id。
    private func copyProvider() {
        guard let client = app.client, let provider else { return }
        let newID = copyIDDraft.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !newID.isEmpty else { return }
        var request = buildSaveRequest(provider: provider, newID: newID)
        request.isNew = true
        request.copyOf = provider.id
        request.key = nil
        request.name = provider.name + " copy"
        Task {
            if await activeVM.save(client: client, request: request) {
                MagpieHaptics.success()
                dismiss()
            } else {
                saveError = activeVM.errorMessage ?? String(localized: "复制失败")
            }
        }
    }

    /// 把编辑器草稿组装成官方 `save` 请求体。
    private func buildSaveRequest(provider: ProviderDTO, newID: String) -> ProviderSaveRequest {
        let trimmedName = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let headers = parseHeaders(headersDraft)
        let extraBody = JSONValue.parse(extraBodyDraft)
        return ProviderSaveRequest(
            id: newID,
            name: trimmedName.isEmpty ? provider.name : trimmedName,
            preset: provider.preset,
            key: keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil
                : keyDraft.trimmingCharacters(in: .whitespacesAndNewlines),
            chat: trimmedOrNil(chatDraft),
            responses: trimmedOrNil(responsesDraft),
            anthropic: trimmedOrNil(anthropicDraft),
            gemini: trimmedOrNil(geminiDraft),
            baseAPI: nil,
            isNew: false,
            searches: searchesDraft,
            unredacted: unredactedDraft,
            models: Array(selectedModels).sorted(),
            proxy: trimmedOrNil(proxyDraft),
            routing: routingDraft,
            affinity: affinityDraft,
            sink: sinkDraft,
            useFirst: useFirstDraft,
            noStandIn: noStandInDraft,
            maxConcurrency: maxConcurrencyDraft,
            queueLimit: queueLimitDraft,
            queueWait: queueWaitDraft,
            maxRPM: maxRPMDraft,
            priceRate: priceRateDraft > 0 ? priceRateDraft : 0,
            topUpRate: topUpRateDraft > 0 ? topUpRateDraft : nil,
            connectAgents: provider.connectAgents != nil ? connectAgentsDraft : nil,
            from: nil,
            unlisted: unlistedDraft,
            noModels: noModelsDraft,
            bestInFamily: bestInFamilyDraft,
            listOff: listOffDraft,
            headers: headers,
            extraBody: extraBody,
            replyHeaders: parseList(replyHeadersDraft) ?? [],
            passHeaders: parseList(passHeadersDraft) ?? [],
            insecureTLS: insecureTLSDraft,
            http1: http1Draft,
            socket: socketDraft,
            limitRestOff: limitRestOffDraft,
            passUserAgent: passUserAgentDraft,
            authHeader: authHeaderDraft,
            nativeCompaction: nativeCompactionDraft,
            passErrors: passErrorsDraft,
            modelsURL: trimmedOrNil(modelsURLDraft),
            balanceURL: trimmedOrNil(balanceURLDraft),
            balancePath: trimmedOrNil(balancePathDraft),
            balanceMethod: trimmedOrNil(balanceMethodDraft),
            balanceToken: trimmedOrNil(balanceTokenDraft),
            contexts: contextsDraft,
            outputs: outputsDraft
        )
    }

    /// 每行 "Key: Value" 的请求头草稿。
    private func parseHeaders(_ text: String) -> [String: String] {
        var out: [String: String] = [:]
        for line in text.split(separator: "\n") {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            if !key.isEmpty { out[key] = value }
        }
        return out
    }

    private func parseList(_ text: String) -> [String]? {
        let items = text
            .split(whereSeparator: { $0 == "\n" || $0 == "," })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return items.isEmpty ? nil : items
    }

    private func formatHeaders(_ headers: [String: String]?) -> String {
        guard let headers, !headers.isEmpty else { return "" }
        return headers
            .sorted { $0.key < $1.key }
            .map { "\($0.key): \($0.value)" }
            .joined(separator: "\n")
    }

    private func trimmedOrNil(_ value: String) -> String? {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// 服务端账号列表可能包含重复账号；Picker 的 tag 与 ForEach 标识都必须唯一。
    private func uniqueLogins(_ logins: [String]) -> [String] {
        var seen = Set<String>()
        return logins.filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    private func runTest(id: String) {
        guard let client = app.client else { return }
        isTesting = true
        testResponse = nil
        testError = nil
        let run = UUID().uuidString
        testRun = run
        Task {
            defer { isTesting = false }
            if let response = await activeVM.testResults(
                client: client,
                id: id,
                account: testAccount.isEmpty ? nil : testAccount,
                run: run
            ) {
                testResponse = response
            } else {
                testError = activeVM.testResult ?? String(localized: "测试失败")
            }
            if testRun == run { testRun = "" }
        }
    }

    private func stopTest() {
        guard let client = app.client, !testRun.isEmpty else { return }
        Task { await activeVM.stopTest(client: client, run: testRun) }
    }

    // MARK: - 获取模型
    private func refreshModels(_ provider: ProviderDTO) {
        guard let client = app.client else { return }
        isRefreshingModels = true
        refreshMessage = nil
        Task {
            let response = await activeVM.refreshModels(
                client: client,
                id: provider.id,
                key: keyDraft.trimmingCharacters(in: .whitespacesAndNewlines),
                chat: chatDraft,
                responses: responsesDraft,
                anthropic: anthropicDraft,
                gemini: geminiDraft,
                proxy: proxyDraft
            )
            isRefreshingModels = false
            if let response {
                var message = String(localized: "已获取 \(response.count ?? 0) 个模型")
                if let dropped = response.dropped, !dropped.isEmpty {
                    message += String(localized: "，\(dropped.count) 个已下架模型被移除")
                }
                refreshMessage = message

                if let refreshed = activeVM.providers.first(where: { $0.id == provider.id }) {
                    let all = (refreshed.models ?? []).map(\.id)
                    let chosen = refreshed.chosen ?? []
                    selectedModels = Set(chosen.isEmpty ? all : chosen)
                    if selectedTestModel.isEmpty || !all.contains(selectedTestModel) {
                        selectedTestModel = all.first ?? "__all__"
                    }
                }
                MagpieHaptics.success()
            } else {
                refreshMessage = activeVM.errorMessage ?? String(localized: "获取模型失败")
            }
        }
    }

    // MARK: - 忘记厂商列表
    private func forgetModelList() {
        guard let client = app.client else { return }
        Task {
            if await activeVM.forgetModelList(client: client, id: providerID) {
                refreshMessage = String(localized: "已忘记厂商列表，下次刷新会重新拉取。")
                MagpieHaptics.success()
            } else {
                saveError = activeVM.errorMessage ?? String(localized: "操作失败")
            }
        }
    }

    // MARK: - 查看已保存 Key
    private func revealKey() {
        guard let client = app.client else { return }
        Task {
            if let key = await activeVM.revealKey(client: client, id: providerID) {
                revealedKey = key
                showingRevealedKey = true
            } else {
                saveError = activeVM.errorMessage ?? String(localized: "读取 Key 失败")
            }
        }
    }

    // MARK: - 余额
    private func checkBalance(_ provider: ProviderDTO) {
        guard let client = app.client else { return }
        isCheckingBalance = true
        balanceMessage = nil
        Task {
            let response = await activeVM.checkBalance(client: client, id: provider.id)
            isCheckingBalance = false
            if let response {
                if let amount = response.amount, !amount.isEmpty, response.ok != false {
                    balanceMessage = String(localized: "余额：\(amount)")
                } else if let error = response.error, !error.isEmpty {
                    balanceMessage = error
                } else if response.ok == false {
                    balanceMessage = String(localized: "该 Provider 没有可查询的余额接口")
                } else {
                    balanceMessage = String(localized: "余额查询完成")
                }
            } else {
                balanceMessage = activeVM.errorMessage ?? String(localized: "余额查询失败")
            }
        }
    }

    // MARK: - 模型测试
    private func runModelTest(all: Bool) {
        guard let client = app.client else { return }
        let models: [String]
        if all || selectedTestModel == "__all__" {
            models = Array(selectedModels).sorted()
        } else {
            models = [selectedTestModel]
        }
        guard !models.isEmpty else {
            testError = String(localized: "没有选择模型")
            return
        }

        isTestingModels = true
        modelTestResponse = nil
        let run = UUID().uuidString
        testRun = run
        Task {
            defer { isTestingModels = false }
            if let response = await activeVM.testResults(
                client: client,
                id: providerID,
                models: models,
                run: run
            ) {
                modelTestResponse = response
            } else {
                testError = activeVM.testResult ?? String(localized: "模型测试失败")
            }
            if testRun == run { testRun = "" }
        }
    }
}

// MARK: - 单个模型的设置
private struct ProviderModelSettingsSheet: View {
    let modelID: String
    let name: String
    let context: String
    let output: String
    let availableEfforts: [String]
    let efforts: Set<String>
    let images: Bool
    let onSave: (String, String, String, Set<String>, Bool) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var nameDraft = ""
    @State private var contextDraft = ""
    @State private var outputDraft = ""
    @State private var effortsDraft: Set<String> = []
    @State private var imagesDraft = false
    @State private var working = false
    @State private var errorMessage: String?
    @State private var primed = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(String(localized: "显示名称（留空恢复厂商名）"), text: $nameDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text(modelID)
                } footer: {
                    Text(String(localized: "名称只影响 magpie 的展示，不改厂商的模型 ID。"))
                }

                Section {
                    TextField(String(localized: "上下文（留空=厂商默认）"), text: $contextDraft)
                        .keyboardType(.numberPad)
                    TextField(String(localized: "输出上限（留空=默认）"), text: $outputDraft)
                        .keyboardType(.numberPad)
                } footer: {
                    Text(String(localized: "上下文与输出上限随「保存」写入 Provider。"))
                }

                if !availableEfforts.isEmpty {
                    Section {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(Array(availableEfforts.enumerated()), id: \.offset) { _, level in
                                    Button {
                                        toggleEffort(level)
                                    } label: {
                                        Text(level)
                                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                            .padding(.horizontal, 9)
                                            .padding(.vertical, 5)
                                            .background(effortsDraft.contains(level) ? MagpieTheme.accentSoft : MagpieTheme.pill)
                                            .foregroundStyle(effortsDraft.contains(level) ? MagpieTheme.accent : MagpieTheme.textSecondary)
                                            .clipShape(Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    } header: {
                        Text(String(localized: "保留的推理档"))
                    } footer: {
                        Text(String(localized: "不选任何一档表示该模型不提供推理档；全部保留即厂商默认。"))
                    }
                }

                Section {
                    Toggle(String(localized: "支持图片输入"), isOn: $imagesDraft)
                } footer: {
                    Text(String(localized: "告诉 Agent 这个模型能看图；保存后立即生效。"))
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(MagpieTheme.red)
                    }
                }
            }
            .navigationTitle(String(localized: "模型设置"))
            .navigationBarTitleDisplayMode(.inline)
            .scrollContentBackground(.hidden)
            .background(MagpieAuroraBackground())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "取消")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        save()
                    } label: {
                        if working {
                            ProgressView().controlSize(.small)
                        } else {
                            Text(String(localized: "保存")).fontWeight(.semibold)
                        }
                    }
                    .disabled(working)
                }
            }
            .onAppear {
                guard !primed else { return }
                primed = true
                nameDraft = name
                contextDraft = context
                outputDraft = output
                effortsDraft = efforts
                imagesDraft = images
            }
        }
    }

    private func toggleEffort(_ level: String) {
        if effortsDraft.contains(level) {
            effortsDraft.remove(level)
        } else {
            effortsDraft.insert(level)
        }
        MagpieHaptics.light()
    }

    private func save() {
        working = true
        errorMessage = nil
        Task {
            let ok = await onSave(nameDraft, contextDraft, outputDraft, effortsDraft, imagesDraft)
            working = false
            if ok { dismiss() } else { errorMessage = String(localized: "保存失败，请检查名称或数值。") }
        }
    }
}

// MARK: - 账号级设置
private struct ProviderAccountSettingsSheet: View {
    let account: String
    let cap: Int
    let weight: Int
    let concurrency: Int
    let onSave: (Int, Int, Int) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var capDraft = 0
    @State private var weightDraft = 0
    @State private var concurrencyDraft = 0
    @State private var working = false
    @State private var errorMessage: String?
    @State private var primed = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $capDraft, in: 0...99) {
                        Text(String(localized: "用量上限：\(capDraft == 0 ? String(localized: "不限") : "\(capDraft)%")"))
                    }
                    Stepper(value: $weightDraft, in: 0...100) {
                        Text(String(localized: "路由权重：\(weightDraft == 0 ? String(localized: "默认") : "\(weightDraft)")"))
                    }
                    Stepper(value: $concurrencyDraft, in: 0...100) {
                        Text(String(localized: "并发上限：\(concurrencyDraft == 0 ? String(localized: "不限") : "\(concurrencyDraft)")"))
                    }
                } header: {
                    Text(account)
                } footer: {
                    Text(String(localized: "用量上限是账号窗口的使用百分比；权重只在按权重路由时生效。"))
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(MagpieTheme.red)
                    }
                }
            }
            .navigationTitle(String(localized: "账号设置"))
            .navigationBarTitleDisplayMode(.inline)
            .scrollContentBackground(.hidden)
            .background(MagpieAuroraBackground())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "取消")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        save()
                    } label: {
                        if working {
                            ProgressView().controlSize(.small)
                        } else {
                            Text(String(localized: "保存")).fontWeight(.semibold)
                        }
                    }
                    .disabled(working)
                }
            }
            .onAppear {
                guard !primed else { return }
                primed = true
                capDraft = cap
                weightDraft = weight
                concurrencyDraft = concurrency
            }
        }
    }

    private func save() {
        working = true
        errorMessage = nil
        Task {
            let ok = await onSave(capDraft, weightDraft, concurrencyDraft)
            working = false
            if ok { dismiss() } else { errorMessage = String(localized: "保存失败，请稍后重试。") }
        }
    }
}

// MARK: - 查看 Key
private struct ProviderKeyRevealSheet: View {
    let key: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text(key)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(MagpieTheme.textPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(MagpieTheme.cardSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                Button {
                    UIPasteboard.general.string = key
                    MagpieHaptics.success()
                } label: {
                    Label(String(localized: "复制 Key"), systemImage: "doc.on.doc.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(MagpiePrimaryButtonStyle(tint: MagpieTheme.accent))

                Spacer()
            }
            .padding(16)
            .magpiePageBackground()
            .navigationTitle(String(localized: "已保存的 Key"))
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

// MARK: - 模型选择
private struct ProviderModelsSheet: View {
    let models: [ProviderModelDTO]
    @Binding var selected: Set<String>
    var onRename: (String, String) async -> Bool
    var contextOf: (String) -> Int? = { _ in nil }
    var outputOf: (String) -> Int? = { _ in nil }
    var onSetCaps: (String, Int?, Int?) -> Void = { _, _, _ in }
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var renamingModel: ProviderModelDTO?
    @State private var renameText = ""
    @State private var renameError: String?
    @State private var capsModel: ProviderModelDTO?
    @State private var capsContext = ""
    @State private var capsOutput = ""
    @State private var capsError: String?

    private var filtered: [ProviderModelDTO] {
        guard !searchText.isEmpty else { return models }
        let q = searchText.lowercased()
        return models.filter {
            $0.displayName.lowercased().contains(q) || $0.id.lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Text(String(localized: "已选 \(selected.count) / \(models.count)"))
                            .font(.caption)
                            .foregroundStyle(MagpieTheme.textSecondary)
                        Spacer()
                        Button(String(localized: "全选")) {
                            selected = Set(models.map(\.id))
                        }
                        .font(.caption.weight(.semibold))
                        Button(String(localized: "清空")) {
                            selected.removeAll()
                        }
                        .font(.caption.weight(.semibold))
                    }
                }

                Section {
                    ForEach(Array(filtered.enumerated()), id: \.offset) { _, model in
                        Button {
                            if selected.contains(model.id) {
                                selected.remove(model.id)
                            } else {
                                selected.insert(model.id)
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: selected.contains(model.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selected.contains(model.id) ? MagpieTheme.accent : MagpieTheme.textMuted.opacity(0.55))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(model.displayName)
                                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                                        .foregroundStyle(MagpieTheme.textPrimary)
                                    if model.displayName != model.id {
                                        Text(model.id)
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundStyle(MagpieTheme.textMuted)
                                    }
                                }
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                renamingModel = model
                                renameText = model.name ?? ""
                            } label: {
                                Label(String(localized: "重命名模型…"), systemImage: "pencil")
                            }
                            Button {
                                capsModel = model
                                capsContext = contextOf(model.id).map(String.init) ?? ""
                                capsOutput = outputOf(model.id).map(String.init) ?? ""
                                capsError = nil
                            } label: {
                                Label(String(localized: "设置上下文与输出…"), systemImage: "ruler")
                            }
                        }
                    }
                }

                if let renameError {
                    Section {
                        Text(renameError)
                            .font(.caption)
                            .foregroundStyle(MagpieTheme.red)
                    }
                }
            }
            .searchable(text: $searchText, prompt: String(localized: "搜索模型…"))
            .navigationTitle(String(localized: "模型"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "完成")) { dismiss() }
                }
            }
            .alert(
                String(localized: "重命名模型"),
                isPresented: Binding(
                    get: { renamingModel != nil },
                    set: { if !$0 { renamingModel = nil } }
                )
            ) {
                TextField(String(localized: "显示名称（留空恢复厂商名）"), text: $renameText)
                    .textInputAutocapitalization(.never)
                Button(String(localized: "取消"), role: .cancel) { renamingModel = nil }
                Button(String(localized: "保存")) {
                    guard let model = renamingModel else { return }
                    let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                    renamingModel = nil
                    Task {
                        if !(await onRename(model.id, name)) {
                            renameError = String(localized: "重命名失败，可能是模型已被厂商下架。")
                        }
                    }
                }
            } message: {
                Text(renamingModel?.id ?? "")
            }
            .alert(
                String(localized: "模型上限"),
                isPresented: Binding(
                    get: { capsModel != nil },
                    set: { if !$0 { capsModel = nil } }
                )
            ) {
                TextField(String(localized: "上下文（留空=厂商默认）"), text: $capsContext)
                    .keyboardType(.numberPad)
                TextField(String(localized: "输出上限（留空=默认）"), text: $capsOutput)
                    .keyboardType(.numberPad)
                Button(String(localized: "取消"), role: .cancel) { capsModel = nil }
                Button(String(localized: "保存")) {
                    guard let model = capsModel else { return }
                    let contextText = capsContext.trimmingCharacters(in: .whitespacesAndNewlines)
                    let outputText = capsOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                    if (!contextText.isEmpty && Int(contextText) == nil)
                        || (!outputText.isEmpty && Int(outputText) == nil) {
                        capsError = String(localized: "请填写整数，或留空使用厂商默认值。")
                        return
                    }
                    onSetCaps(
                        model.id,
                        contextText.isEmpty ? nil : Int(contextText),
                        outputText.isEmpty ? nil : Int(outputText)
                    )
                    capsModel = nil
                }
            } message: {
                Text(capsError ?? (capsModel?.id ?? ""))
            }
        }
    }
}

// MARK: - 添加密钥
private struct ProviderAddKeySheet: View {
    let onAdd: (String, String, String?, Int?) async -> Bool
    let onImport: (String) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var keyText = ""
    @State private var protocolName = ""
    @State private var weight = 1
    @State private var working = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(String(localized: "名称（例如 main）"), text: $name)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    Picker(String(localized: "协议"), selection: $protocolName) {
                        Text(String(localized: "跟随 Provider")).tag("")
                        Text("Chat Completions").tag("chat")
                        Text("Responses").tag("responses")
                        Text("Anthropic Messages").tag("anthropic")
                        Text("Gemini").tag("gemini")
                    }

                    Stepper(value: $weight, in: 1...100) {
                        Text(String(localized: "权重 \(weight)"))
                    }
                } footer: {
                    Text(String(localized: "按权重路由时会参考该值；协议留空时由端点自动判断。"))
                }

                Section {
                    TextEditor(text: $keyText)
                        .font(.system(size: 11, design: .monospaced))
                        .frame(minHeight: 110)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } header: {
                    Text(String(localized: "密钥"))
                } footer: {
                    Text(String(localized: "一行一个可一次导入多个；单个密钥也可直接添加。"))
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(MagpieTheme.red)
                    }
                }
            }
            .navigationTitle(String(localized: "添加密钥"))
            .navigationBarTitleDisplayMode(.inline)
            .scrollContentBackground(.hidden)
            .background(MagpieAuroraBackground())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "取消")) { dismiss() }
                }
                ToolbarItemGroup(placement: .confirmationAction) {
                    Button(String(localized: "导入多个")) {
                        importKeys()
                    }
                    .disabled(keyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || working)

                    Button(String(localized: "添加")) {
                        addKey()
                    }
                    .fontWeight(.semibold)
                    .disabled(keyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || working)
                }
            }
            .overlay {
                if working {
                    ProgressView()
                        .padding(16)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
    }

    private func addKey() {
        working = true
        errorMessage = nil
        Task {
            let ok = await onAdd(
                name.trimmingCharacters(in: .whitespacesAndNewlines),
                keyText.trimmingCharacters(in: .whitespacesAndNewlines),
                protocolName.isEmpty ? nil : protocolName,
                weight > 1 ? weight : nil
            )
            working = false
            if ok { dismiss() } else { errorMessage = String(localized: "添加失败，请检查密钥格式。") }
        }
    }

    private func importKeys() {
        working = true
        errorMessage = nil
        Task {
            let ok = await onImport(keyText)
            working = false
            if ok { dismiss() } else { errorMessage = String(localized: "导入失败，请检查内容。") }
        }
    }
}
