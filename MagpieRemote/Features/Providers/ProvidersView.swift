import SwiftUI
import UIKit

/// Providers 视图：1:1 对齐官方 Web / 客户端设计。
/// 支持官方彩色品牌 Logo、已启用/已停用分组、连通性状态与预设添加。
struct ProvidersView: View {
    @Environment(AppModel.self) private var app
    @State private var viewModel = ProvidersViewModel()
    @State private var searchText = ""
    @State private var showingAddSheet = false
    @State private var isOffExpanded = true
    @State private var showingOrderSheet = false
    @State private var testMessage: String?
    @Namespace private var zoomNamespace

    private var activeProviders: [ProviderDTO] {
        filtered(viewModel.providers.filter { !$0.isOff })
    }

    private var offProviders: [ProviderDTO] {
        filtered(viewModel.providers.filter { $0.isOff })
    }

    private func filtered(_ list: [ProviderDTO]) -> [ProviderDTO] {
        if searchText.isEmpty { return list }
        return list.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.id.localizedCaseInsensitiveContains(searchText) ||
            ($0.host?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    summaryBar

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

                    // Claude 出口地区告警（upstream egress）
                    if let badEgress = viewModel.providers.first(where: { $0.egress?.isUnsupported == true }),
                       let egress = badEgress.egress {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Image(systemName: "globe.badge.chevron.backward")
                                    .foregroundStyle(MagpieTheme.amber)
                                Text(String(localized: "Claude 出口地区受限\(egress.loc.map { " (\($0))" } ?? "")"))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(MagpieTheme.textPrimary)
                                Spacer()
                                Button(String(localized: "重新检测")) {
                                    guard let client = app.client else { return }
                                    Task { _ = await viewModel.checkEgress(client: client) }
                                }
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(MagpieTheme.accent)
                                .buttonStyle(.plain)
                                .disabled(viewModel.isOperating)
                            }
                            Text(String(localized: "当前网络出口不在 Anthropic 支持的地区，可在该 Provider 或设置中更换代理，或在设置中开启「不支持地区暂停 Claude 请求」。"))
                                .font(.caption2)
                                .foregroundStyle(MagpieTheme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .magpieCard(padding: 12)
                    }

                    // 已下架旧插件迁移提醒（upstream withdrawn）
                    if !viewModel.withdrawn.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundStyle(MagpieTheme.amber)
                                Text(String(localized: "存在已下架的旧插件"))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(MagpieTheme.textPrimary)
                            }
                            ForEach(viewModel.withdrawn) { item in
                                let label = item.name ?? item.id
                                let replacement = item.instead ?? item.insteadId
                                Text(
                                    replacement != nil
                                        ? String(localized: "\(label) 已下架，建议改用 \(replacement!)。")
                                        : String(localized: "\(label) 已下架，请在 Plugins 页停用或移除。")
                                )
                                .font(.caption2)
                                .foregroundStyle(MagpieTheme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .magpieCard(padding: 12)
                    }

                    // 活跃 Providers 卡片列表
                    if !activeProviders.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(String(localized: "已启用的提供方 (\(activeProviders.count))"))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(MagpieTheme.textMuted)

                            LazyVStack(spacing: 10) {
                                ForEach(activeProviders) { provider in
                                    NavigationLink(value: provider.id) {
                                        ProviderCard(provider: provider) { turnOn in
                                            toggleProvider(provider.id, turnOn: turnOn)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .matchedTransitionSource(id: provider.id, in: zoomNamespace)
                                    .contextMenu {
                                        providerContextMenu(provider)
                                    }
                                }
                            }
                        }
                    }

                    // 已停用的 Providers 折叠卡片列表
                    if !offProviders.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isOffExpanded.toggle()
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: isOffExpanded ? "chevron.down" : "chevron.right")
                                        .font(.caption2.weight(.bold))
                                    Text(String(localized: "已停用 (\(offProviders.count))"))
                                        .font(.caption.weight(.semibold))
                                    Spacer()
                                }
                                .foregroundStyle(MagpieTheme.textMuted)
                            }
                            .buttonStyle(.plain)

                            if isOffExpanded {
                                LazyVStack(spacing: 10) {
                                    ForEach(offProviders) { provider in
                                        NavigationLink(value: provider.id) {
                                            ProviderCard(provider: provider) { turnOn in
                                                toggleProvider(provider.id, turnOn: turnOn)
                                            }
                                        }
                                        .buttonStyle(.plain)
                                        .matchedTransitionSource(id: provider.id, in: zoomNamespace)
                                        .contextMenu {
                                            providerContextMenu(provider)
                                        }
                                        .transition(.magpieContent)
                                    }
                                }
                            }
                        }
                        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: isOffExpanded)
                    }

                    // 底部快捷添加按钮
                    Button {
                        showingAddSheet = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus.circle.fill")
                                .font(.body.weight(.semibold))
                            Text(String(localized: "添加模型提供商 (Provider)"))
                                .font(.subheadline.weight(.medium))
                        }
                        .foregroundStyle(MagpieTheme.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(MagpieTheme.card)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(MagpieTheme.accent.opacity(0.3), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .padding(.bottom, 96)
                .animation(.spring(response: 0.35, dampingFraction: 0.86), value: viewModel.providers.map(\.id))
            }
            .magpiePageBackground()
            .searchable(text: $searchText, prompt: String(localized: "搜索 Provider 或域名…"))
            .navigationTitle(String(localized: "Providers"))
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .navigationDestination(for: String.self) { id in
                ProviderDetailView(providerID: id, viewModel: viewModel)
                    .environment(viewModel)
                    .navigationTransition(.zoom(sourceID: id, in: zoomNamespace))
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button {
                            showingOrderSheet = true
                        } label: {
                            Label(String(localized: "调整 Provider 顺序…"), systemImage: "arrow.up.arrow.down")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.body.weight(.semibold))
                    }
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                AddProviderView()
                    .environment(viewModel)
            }
            .sheet(isPresented: $showingOrderSheet) {
                ProviderOrderSheet(providers: viewModel.providers) { order in
                    guard let client = app.client else { return false }
                    return await viewModel.arrange(client: client, order: order)
                }
            }
            .alert(
                String(localized: "连通性测试"),
                isPresented: Binding(
                    get: { testMessage != nil },
                    set: { if !$0 { testMessage = nil } }
                )
            ) {
                Button(String(localized: "好"), role: .cancel) { testMessage = nil }
            } message: {
                Text(testMessage ?? "")
            }
            .overlay {
                if viewModel.isLoading && viewModel.providers.isEmpty {
                    ProgressView(String(localized: "加载提供商列表…"))
                }
            }
            .task {
                if let client = app.client, viewModel.providers.isEmpty {
                    await viewModel.load(client: client)
                }
            }
            .refreshable {
                if let client = app.client {
                    await viewModel.load(client: client)
                }
            }
        }
        .environment(viewModel)
    }

    private func toggleProvider(_ id: String, turnOn: Bool) {
        guard let client = app.client else { return }
        Task {
            await viewModel.toggle(client: client, id: id, turnOn: turnOn)
        }
    }

    @ViewBuilder
    private func providerContextMenu(_ provider: ProviderDTO) -> some View {
        Button {
            toggleProvider(provider.id, turnOn: provider.isOff)
        } label: {
            Label(
                provider.isOff ? String(localized: "启用") : String(localized: "停用"),
                systemImage: "power"
            )
        }

        Button {
            testProvider(provider)
        } label: {
            Label(String(localized: "测试连通性"), systemImage: "bolt.fill")
        }

        Button {
            UIPasteboard.general.string = provider.id
            MagpieHaptics.success()
        } label: {
            Label(String(localized: "复制 ID"), systemImage: "doc.on.doc")
        }
    }

    private func testProvider(_ provider: ProviderDTO) {
        guard let client = app.client else { return }
        Task {
            if let response = await viewModel.testResults(client: client, id: provider.id) {
                let passed = response.results.filter { $0.succeeded }.count
                let total = response.results.count
                testMessage = total == 0
                    ? String(localized: "没有可测试的端点")
                    : String(localized: "\(passed)/\(total) 个端点通过")
                if passed == total, total > 0 {
                    MagpieHaptics.success()
                }
            } else {
                testMessage = viewModel.testResult ?? String(localized: "测试失败")
            }
        }
    }

    // MARK: - 概览信息栏
    private var summaryBar: some View {
        HStack {
            HStack(spacing: 6) {
                Circle().fill(MagpieTheme.green).frame(width: 6, height: 6)
                Text(String(localized: "\(viewModel.providers.filter { !$0.isOff }.count) 启用"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MagpieTheme.textPrimary)
            }

            Spacer()

            Text(String(localized: "共 \(viewModel.providers.reduce(0) { $0 + ($1.models?.count ?? 0) }) 个可用模型"))
                .font(.caption)
                .foregroundStyle(MagpieTheme.textMuted)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .magpieCard(padding: 0, cornerRadius: 14)
    }
}

// MARK: - Provider 排序
private struct ProviderOrderSheet: View {
    let providers: [ProviderDTO]
    let onSave: ([String]) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var items: [ProviderDTO] = []
    @State private var working = false
    @State private var errorMessage: String?
    @State private var primed = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, provider in
                        HStack(spacing: 10) {
                            MagpieIconView(icon: provider.icon ?? provider.id, name: provider.name, size: 26, cornerRadius: 6)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(provider.name)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(MagpieTheme.textPrimary)
                                Text(provider.id)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(MagpieTheme.textMuted)
                            }
                            Spacer()
                            Button {
                                move(index, by: -1)
                            } label: {
                                Image(systemName: "chevron.up")
                                    .foregroundStyle(index == 0 ? MagpieTheme.textMuted.opacity(0.3) : MagpieTheme.textSecondary)
                            }
                            .buttonStyle(.plain)
                            .disabled(index == 0)
                            Button {
                                move(index, by: 1)
                            } label: {
                                Image(systemName: "chevron.down")
                                    .foregroundStyle(index == items.count - 1 ? MagpieTheme.textMuted.opacity(0.3) : MagpieTheme.textSecondary)
                            }
                            .buttonStyle(.plain)
                            .disabled(index == items.count - 1)
                        }
                    }
                } footer: {
                    Text(String(localized: "顺序决定 Provider 列表的展示与同族模型的优先次序。"))
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(MagpieTheme.red)
                    }
                }
            }
            .navigationTitle(String(localized: "Provider 顺序"))
            .navigationBarTitleDisplayMode(.inline)
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
                items = providers
            }
        }
    }

    private func move(_ index: Int, by offset: Int) {
        let target = index + offset
        guard items.indices.contains(index), items.indices.contains(target) else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            items.swapAt(index, target)
        }
        MagpieHaptics.light()
    }

    private func save() {
        working = true
        errorMessage = nil
        Task {
            let ok = await onSave(items.map(\.id))
            working = false
            if ok { dismiss() } else { errorMessage = String(localized: "保存失败，请稍后再试。") }
        }
    }
}

// MARK: - 原版风格 Provider 卡片
private struct ProviderCard: View {
    let provider: ProviderDTO
    var onToggle: (Bool) -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(.white.opacity(0.16), lineWidth: 0.7)
                    )
                    .frame(width: 38, height: 38)
                MagpieIconView(icon: provider.icon ?? provider.id, name: provider.name, size: 30, cornerRadius: 7)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(provider.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(provider.isOff ? MagpieTheme.textMuted : MagpieTheme.textPrimary)

                    if provider.isOff {
                        Text(String(localized: "已停用"))
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(MagpieTheme.pill)
                            .foregroundStyle(MagpieTheme.textMuted)
                            .clipShape(Capsule())
                    } else if provider.ready == true {
                        MagpiePulseDot(color: MagpieTheme.green)
                    }

                    if provider.unlisted == true {
                        Text(String(localized: "仅路由组"))
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(MagpieTheme.cyan.opacity(0.13))
                            .foregroundStyle(MagpieTheme.cyan)
                            .clipShape(Capsule())
                    }
                }

                HStack(spacing: 8) {
                    if let host = provider.host, !host.isEmpty {
                        Text(host)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(MagpieTheme.textMuted)
                            .lineLimit(1)
                    }

                    if let count = provider.models?.count, count > 0 {
                        Text("• \(count) 个模型")
                            .font(.caption2)
                            .foregroundStyle(MagpieTheme.textSecondary)
                    }

                    if let keys = provider.keyList, !keys.isEmpty {
                        Text("• \(keys.count) 个 Key")
                            .font(.caption2)
                            .foregroundStyle(MagpieTheme.textSecondary)
                    } else if let masked = provider.key?.masked, !masked.isEmpty {
                        Text("• \(masked)")
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundStyle(MagpieTheme.textMuted)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            // 快捷开关
            Button {
                MagpieHaptics.light()
                onToggle(provider.isOff)
            } label: {
                Image(systemName: provider.isOff ? "power.circle" : "power.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(provider.isOff ? MagpieTheme.textMuted : MagpieTheme.green)
            }
            .buttonStyle(.plain)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(MagpieTheme.textMuted)
        }
        .magpieLiquidCard(padding: 14, cornerRadius: 18)
    }
}
