import SwiftUI
import UIKit

/// Plugins：已安装、插件商店、更新与运行环境。
/// 商店与安装全部走真实的 `/api/plugins/*`，首次安装可能下载 Bun，因此使用长超时。
struct PluginsView: View {
    @Environment(AppModel.self) private var app
    @State private var viewModel = PluginsViewModel()
    @State private var tab: PluginTab = .installed
    @State private var searchText = ""
    @State private var showingManualInstall = false
    @State private var manualSpec = ""
    @State private var showingRegistry = false
    @State private var registryDraft = ""
    @State private var pendingRemoval: PluginEntryDTO?
    @State private var optionsPlugin: PluginEntryDTO?
    @State private var optionsText = ""
    @State private var optionsError: String?
    @State private var hasSavedOptions = false

    enum PluginTab: String, CaseIterable, Identifiable, Hashable {
        case installed
        case discover
        case updates

        var id: String { rawValue }

        var title: String {
            switch self {
            case .installed: return String(localized: "已安装")
            case .discover: return String(localized: "商店")
            case .updates: return String(localized: "更新")
            }
        }

        var icon: String {
            switch self {
            case .installed: return "shippingbox.fill"
            case .discover: return "sparkles"
            case .updates: return "arrow.down.circle.fill"
            }
        }
    }

    private var filteredPlugins: [PluginEntryDTO] {
        guard !searchText.isEmpty else { return viewModel.plugins }
        let q = searchText.lowercased()
        return viewModel.plugins.filter {
            $0.displayName.lowercased().contains(q)
                || $0.spec.lowercased().contains(q)
                || ($0.packageName?.lowercased().contains(q) ?? false)
        }
    }

    private var filteredListings: [PluginListingDTO] {
        guard !searchText.isEmpty else { return viewModel.listings }
        let q = searchText.lowercased()
        return viewModel.listings.filter {
            $0.displayName.lowercased().contains(q)
                || $0.packageName.lowercased().contains(q)
                || $0.summaryText.lowercased().contains(q)
                || ($0.npm?.publisher?.lowercased().contains(q) ?? false)
        }
    }

    private var updateCount: Int {
        max(viewModel.availableUpdates.count, viewModel.pendingWaits.count)
    }

    var body: some View {
        MagpieNavigationContainer {
            ScrollView {
                VStack(spacing: 16) {
                    summaryBar
                    tabBar

                    if let error = viewModel.errorMessage {
                        errorBanner(error)
                    }

                    switch tab {
                    case .installed:
                        installedSection
                    case .discover:
                        discoverSection
                    case .updates:
                        updatesSection
                    }

                    runtimeCard
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .magpiePageBackground()
            .navigationTitle(String(localized: "Plugins"))
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        manualSpec = ""
                        showingManualInstall = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(String(localized: "安装插件"))
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if let client = app.client {
                            Task { await loadAll(client: client) }
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(viewModel.isLoading || viewModel.isOperating)
                }
            }
            .refreshable {
                if let client = app.client { await loadAll(client: client) }
            }
            .task {
                if let client = app.client {
                    await loadAll(client: client)
                }
            }
            .sheet(isPresented: $showingManualInstall) {
                manualInstallSheet
            }
            .sheet(isPresented: $showingRegistry) {
                registrySheet
            }
            .sheet(item: $optionsPlugin) { plugin in
                NavigationStack {
                    Form {
                        Section {
                            TextEditor(text: $optionsText)
                                .font(.system(size: 11, design: .monospaced))
                                .frame(minHeight: 180)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .scrollContentBackground(.hidden)
                        } header: {
                            Text(String(localized: "Options (JSON)"))
                        } footer: {
                            Text(hasSavedOptions
                                ? String(localized: "已保存的选项：应用到下一次请求。")
                                : String(localized: "还没设置：这是它的包给出的示例。"))
                        }

                        if let optionsError {
                            Section {
                                Text(optionsError)
                                    .font(.caption)
                                    .foregroundStyle(MagpieTheme.red)
                            }
                        }
                    }
                    .navigationTitle(plugin.displayName)
                    .navigationBarTitleDisplayMode(.inline)
            .scrollContentBackground(.hidden)
            .background(MagpieAuroraBackground())
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(String(localized: "取消")) { optionsPlugin = nil }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button(String(localized: "保存")) {
                                saveOptions(plugin)
                            }
                            .fontWeight(.semibold)
                        }
                    }
                }
                .presentationDetents([.medium, .large])
            }
            .confirmationDialog(
                String(localized: "卸载 \(pendingRemoval?.displayName ?? "插件")？"),
                isPresented: Binding(
                    get: { pendingRemoval != nil },
                    set: { if !$0 { pendingRemoval = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button(String(localized: "卸载"), role: .destructive) {
                    if let plugin = pendingRemoval, let client = app.client {
                        Task { await viewModel.remove(client: client, spec: plugin.spec) }
                    }
                    pendingRemoval = nil
                }
                Button(String(localized: "取消"), role: .cancel) { pendingRemoval = nil }
            } message: {
                Text(String(localized: "插件提供的提供商、工具或页面会同时消失。"))
            }
            .overlay {
                if let spec = viewModel.installingSpec {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text(String(localized: "正在处理 \(spec)…"))
                            .font(.caption)
                            .foregroundStyle(MagpieTheme.textSecondary)
                        Text(String(localized: "首次安装可能需要下载 Bun，请保持页面打开。"))
                            .font(.caption2)
                            .foregroundStyle(MagpieTheme.textMuted)
                            .multilineTextAlignment(.center)
                    }
                    .padding(20)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: .black.opacity(0.12), radius: 24, y: 10)
                }
            }
        }
    }

    private func openOptions(_ plugin: PluginEntryDTO) {
        optionsError = nil
        optionsText = (plugin.options ?? plugin.optionsExample)?.prettyText ?? "{\n  \n}"
        hasSavedOptions = plugin.options != nil
        optionsPlugin = plugin
    }

    private func saveOptions(_ plugin: PluginEntryDTO) {
        guard let client = app.client else { return }
        let trimmed = optionsText.trimmingCharacters(in: .whitespacesAndNewlines)
        let value: JSONValue?
        if trimmed.isEmpty {
            value = nil
        } else {
            guard let parsed = JSONValue.parse(trimmed), case .object = parsed else {
                optionsError = String(localized: "Options 需要是一个 JSON 对象。")
                return
            }
            value = parsed
        }
        optionsPlugin = nil
        Task {
            await viewModel.setOptions(client: client, spec: plugin.spec, options: value)
        }
    }

    // MARK: - 概览状态栏
    private var summaryBar: some View {
        HStack(spacing: 8) {
            if viewModel.hasBun {
                HStack(spacing: 4) {
                    MagpiePulseDot(color: MagpieTheme.green)
                    Text(viewModel.bunVersion ?? "Bun")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(MagpieTheme.greenSoft, in: Capsule())
                .foregroundStyle(MagpieTheme.green)
            } else {
                MagpieStatusChip(
                    text: String(localized: "Bun 未安装"),
                    color: MagpieTheme.amber,
                    icon: "exclamationmark.triangle.fill"
                )
            }
            MagpieStatusChip(
                text: String(localized: "\(viewModel.plugins.count) 个插件"),
                color: MagpieTheme.accent,
                icon: "shippingbox.fill"
            )
            if updateCount > 0 {
                MagpieStatusChip(
                    text: String(localized: "\(updateCount) 个更新"),
                    color: MagpieTheme.amber,
                    icon: "arrow.down.circle.fill"
                )
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .magpieCard(padding: 0, cornerRadius: 14)
    }

    private var tabBar: some View {
        Picker("", selection: Binding(
            get: { tab },
            set: { next in
                withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                    tab = next
                }
                MagpieHaptics.light()
            }
        )) {
            ForEach(PluginTab.allCases) { item in
                Text(item.title).tag(item)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    // MARK: - 已安装
    private var installedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                MagpieSectionLabel(
                    title: String(localized: "已安装"),
                    detail: viewModel.plugins.isEmpty ? nil : "\(viewModel.plugins.count)"
                )
                Spacer()
                if viewModel.isLoading && viewModel.plugins.isEmpty {
                    ProgressView().controlSize(.small)
                }
            }

            if filteredPlugins.isEmpty {
                emptyState(
                    icon: "puzzlepiece.extension",
                    title: viewModel.plugins.isEmpty ? String(localized: "还没有安装插件") : String(localized: "没有匹配的插件"),
                    subtitle: String(localized: "到「商店」挑选社区插件，或用右上角 + 输入 npm 包名 / GitHub 仓库。")
                )
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(filteredPlugins) { plugin in
                        pluginCard(plugin)
                    }
                }
            }

            if !viewModel.leftovers.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    MagpieSectionLabel(
                        title: String(localized: "残留依赖包"),
                        detail: "\(viewModel.leftovers.count)"
                    )
                    VStack(spacing: 0) {
                        ForEach(Array(viewModel.leftovers.enumerated()), id: \.element.id) { index, item in
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(MagpieTheme.textPrimary)
                                    Text(item.version.map { "\(item.spec) · v\($0)" } ?? item.spec)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(MagpieTheme.textMuted)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 8)
                                Button(String(localized: "清理")) {
                                    guard let client = app.client else { return }
                                    Task { await viewModel.dropLeftover(client: client, spec: item.spec) }
                                }
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(MagpieTheme.red)
                                .buttonStyle(.plain)
                                .disabled(viewModel.isOperating)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)

                            if index < viewModel.leftovers.count - 1 {
                                Divider().background(MagpieTheme.borderSubtle).padding(.leading, 14)
                            }
                        }
                    }
                    .magpieCard(padding: 0)
                }
                .padding(.top, 4)
            }
        }
    }

    private func pluginCard(_ plugin: PluginEntryDTO) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 11) {
                MagpieIconView(icon: plugin.icon, name: plugin.displayName, size: 38, cornerRadius: 9)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(plugin.displayName)
                            .font(.system(size: 14.5, weight: .semibold))
                            .foregroundStyle(plugin.isOff ? MagpieTheme.textMuted : MagpieTheme.textPrimary)
                            .lineLimit(1)

                        if plugin.hasUpdate {
                            MagpieStatusChip(text: String(localized: "可更新"), color: MagpieTheme.amber)
                        }
                    }

                    Text(plugin.packageName ?? plugin.spec)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(MagpieTheme.textMuted)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                Toggle("", isOn: Binding(
                    get: { !plugin.isOff },
                    set: { on in
                        MagpieHaptics.light()
                        if let client = app.client {
                            Task { await viewModel.toggle(client: client, spec: plugin.spec, turnOn: on) }
                        }
                    }
                ))
                .labelsHidden()
                .tint(MagpieTheme.green)
            }

            HStack(spacing: 7) {
                if let version = plugin.version, !version.isEmpty {
                    Text("v\(version)")
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(MagpieTheme.pill)
                        .foregroundStyle(MagpieTheme.textMuted)
                        .clipShape(Capsule())
                }

                if plugin.hasEditableOptions {
                    Button(String(localized: "Options")) {
                        openOptions(plugin)
                    }
                    .font(.caption2.weight(.semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(MagpieTheme.accent)
                }

                if let providers = plugin.providers, providers.count > 1 {
                    Menu {
                        ForEach(providers, id: \.self) { provider in
                            Button(provider) {
                                guard let client = app.client else { return }
                                Task { await viewModel.prefer(client: client, spec: plugin.spec, provider: provider) }
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.triangle.swap")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(MagpieTheme.textSecondary)
                    }
                    .accessibilityLabel(String(localized: "指定由这个插件运行 Provider"))
                }

                if let providers = plugin.providers, !providers.isEmpty {
                    Text(providers.joined(separator: " · "))
                        .font(.system(size: 9.5))
                        .foregroundStyle(MagpieTheme.textSecondary)
                        .lineLimit(1)
                }

                if let tools = plugin.tools, !tools.isEmpty {
                    Text("\(tools.count) tools")
                        .font(.system(size: 9.5))
                        .foregroundStyle(MagpieTheme.textMuted)
                }

                Spacer()

                if plugin.hasUpdate, let latest = plugin.latest ?? plugin.head {
                    Button {
                        if let client = app.client {
                            Task { await viewModel.upgrade(client: client, spec: plugin.spec) }
                        }
                    } label: {
                        Text(String(localized: "更新到 \(latest)"))
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(MagpieTheme.amberSoft)
                            .foregroundStyle(MagpieTheme.amber)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isOperating)
                }
            }

            if let error = plugin.error, !error.isEmpty {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(MagpieTheme.red)
                    .lineLimit(2)
            }
        }
        .magpieLiquidCard(padding: 12, cornerRadius: 18)
        .contextMenu {
            Button(role: .destructive) {
                pendingRemoval = plugin
            } label: {
                Label(String(localized: "卸载插件"), systemImage: "trash")
            }
        }
    }

    // MARK: - 商店
    private var discoverSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            localStorageField

            HStack {
                MagpieSectionLabel(
                    title: String(localized: "推荐插件"),
                    detail: filteredListings.isEmpty ? nil : "\(filteredListings.count)"
                )
                Spacer()
                if viewModel.isLoading && viewModel.listings.isEmpty {
                    ProgressView().controlSize(.small)
                }
            }

            if filteredListings.isEmpty {
                emptyState(
                    icon: "sparkles",
                    title: String(localized: "没有找到推荐插件"),
                    subtitle: String(localized: "换一个关键词，或点击搜索按钮到 npm 全量搜索。")
                )
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(filteredListings) { listing in
                        listingCard(listing)
                    }
                }
            }

            if !viewModel.searchHits.isEmpty {
                MagpieSectionLabel(
                    title: String(localized: "npm 搜索结果"),
                    detail: "\(viewModel.searchHits.count)"
                )
                LazyVStack(spacing: 10) {
                    ForEach(viewModel.searchHits) { hit in
                        searchHitCard(hit)
                    }
                }
            }
        }
    }

    private var localStorageField: some View {
        HStack(spacing: 8) {
            Button {
                submitSearch()
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(MagpieTheme.textMuted)
            }
            .buttonStyle(.plain)

            TextField(String(localized: "搜索插件、作者或提供商…"), text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onSubmit { submitSearch() }

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    viewModel.searchHits = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(MagpieTheme.textMuted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(MagpieTheme.card.opacity(0.72), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(MagpieTheme.borderSubtle, lineWidth: 0.8)
        )
    }

    private func submitSearch() {
        guard let client = app.client else { return }
        Task { await viewModel.search(client: client, query: searchText) }
    }

    private func searchHitCard(_ hit: PluginSearchHitDTO) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 11) {
                MagpieIconView(icon: hit.icon, name: hit.packageName, size: 34, cornerRadius: 8)

                VStack(alignment: .leading, spacing: 2) {
                    Text(hit.packageName)
                        .font(.system(size: 13.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(MagpieTheme.textPrimary)
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        if let version = hit.version {
                            Text("v\(version)")
                        }
                        if let publisher = hit.publisher, !publisher.isEmpty {
                            Text("· \(publisher)")
                        }
                        if let weekly = hit.weekly, weekly > 0 {
                            Text("· \(weekly) / 周")
                        }
                    }
                    .font(.system(size: 9.5))
                    .foregroundStyle(MagpieTheme.textMuted)
                }

                Spacer(minLength: 4)

                if viewModel.isInstalled(packageName: hit.packageName) {
                    Text(String(localized: "已安装"))
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(MagpieTheme.greenSoft)
                        .foregroundStyle(MagpieTheme.green)
                        .clipShape(Capsule())
                } else {
                    Button {
                        if let client = app.client {
                            Task { await viewModel.install(client: client, spec: hit.packageName) }
                        }
                    } label: {
                        Text(String(localized: "安装"))
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                    }
                    .buttonStyle(MagpiePrimaryButtonStyle(tint: Color(hex: "ec4899")))
                    .disabled(viewModel.isOperating)
                }
            }

            if let description = hit.description, !description.isEmpty {
                Text(description)
                    .font(.caption2)
                    .foregroundStyle(MagpieTheme.textSecondary)
                    .lineLimit(2)
            }
        }
        .magpieCard(padding: 12)
    }

    private func listingCard(_ listing: PluginListingDTO) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 11) {
                MagpieIconView(icon: listing.icon ?? listing.npm?.icon, name: listing.displayName, size: 38, cornerRadius: 9)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(listing.displayName)
                            .font(.system(size: 14.5, weight: .semibold))
                            .foregroundStyle(MagpieTheme.textPrimary)
                            .lineLimit(1)

                        if listing.kindLabel != nil {
                            MagpieStatusChip(text: listing.kindLabel!, color: MagpieTheme.purple)
                        }
                        if listing.community == true {
                            MagpieStatusChip(text: "COMMUNITY", color: MagpieTheme.accent)
                        }
                    }

                    Text(listing.packageName)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(MagpieTheme.textMuted)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                installButton(listing)
            }

            if !listing.summaryText.isEmpty {
                Text(listing.summaryText)
                    .font(.caption2)
                    .foregroundStyle(MagpieTheme.textSecondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
            }

            HStack(spacing: 8) {
                if let providers = listing.providers, !providers.isEmpty {
                    Text(providers.joined(separator: " · "))
                        .font(.system(size: 9.5))
                        .foregroundStyle(MagpieTheme.textMuted)
                        .lineLimit(1)
                }
                if let npm = listing.npm {
                    if let version = npm.version {
                        Text("v\(version)")
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundStyle(MagpieTheme.textMuted)
                    }
                    if let publisher = npm.publisher, !publisher.isEmpty {
                        Text("· \(publisher)")
                            .font(.system(size: 9.5))
                            .foregroundStyle(MagpieTheme.textMuted)
                            .lineLimit(1)
                    }
                    if let weekly = npm.weekly, weekly > 0 {
                        Text("· \(weekly) / 周")
                            .font(.system(size: 9.5))
                            .foregroundStyle(MagpieTheme.textMuted)
                    }
                }
                Spacer()
            }
        }
        .magpieCard(padding: 12)
    }

    @ViewBuilder
    private func installButton(_ listing: PluginListingDTO) -> some View {
        if viewModel.isInstalled(listing) {
            Text(String(localized: "已安装"))
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(MagpieTheme.greenSoft)
                .foregroundStyle(MagpieTheme.green)
                .clipShape(Capsule())
        } else {
            Button {
                if let client = app.client {
                    Task { await viewModel.install(client: client, spec: listing.packageName) }
                }
            } label: {
                Text(String(localized: "安装"))
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
            }
            .buttonStyle(MagpiePrimaryButtonStyle(tint: Color(hex: "ec4899")))
            .disabled(viewModel.isOperating)
        }
    }

    // MARK: - 更新
    private var updatesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                MagpieSectionLabel(title: String(localized: "可用更新"), detail: nil)
                Spacer()
                Button {
                    if let client = app.client {
                        Task { await viewModel.checkUpdates(client: client) }
                    }
                } label: {
                    Text(String(localized: "检查更新"))
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(MagpieTheme.accent)
                .disabled(viewModel.isOperating)
            }

            if viewModel.availableUpdates.isEmpty && viewModel.pendingWaits.isEmpty {
                emptyState(
                    icon: "checkmark.seal.fill",
                    title: String(localized: "所有插件都是最新版本"),
                    subtitle: viewModel.updates?.checked.map { String(localized: "上次检查：\($0)") } ?? String(localized: "点击「检查更新」立即询问 npm。")
                )
            } else {
                if !viewModel.availableUpdates.isEmpty {
                    Button {
                        if let client = app.client {
                            Task { await viewModel.updateAll(client: client) }
                        }
                    } label: {
                        HStack {
                            Image(systemName: "arrow.down.circle.fill")
                            Text(String(localized: "全部更新（\(viewModel.availableUpdates.count)）"))
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 14)
                    }
                    .buttonStyle(MagpiePrimaryButtonStyle(tint: MagpieTheme.amber))
                    .disabled(viewModel.isOperating)
                }

                VStack(spacing: 0) {
                    ForEach(Array(viewModel.availableUpdates.enumerated()), id: \.element.id) { index, plugin in
                        HStack(spacing: 10) {
                            MagpieIconView(icon: plugin.icon, name: plugin.displayName, size: 30, cornerRadius: 7)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(plugin.displayName)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(MagpieTheme.textPrimary)
                                Text("\(plugin.version ?? "—") → \(plugin.latest ?? plugin.head ?? "—")")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(MagpieTheme.amber)
                            }
                            Spacer()
                            Button(String(localized: "更新")) {
                                if let client = app.client {
                                    Task { await viewModel.upgrade(client: client, spec: plugin.spec) }
                                }
                            }
                            .font(.caption.weight(.semibold))
                            .buttonStyle(.plain)
                            .foregroundStyle(MagpieTheme.accent)
                            .disabled(viewModel.isOperating)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)

                        if index < viewModel.availableUpdates.count - 1 {
                            Divider().background(MagpieTheme.borderSubtle).padding(.leading, 50)
                        }
                    }
                }
                .magpieCard(padding: 0)

                if !viewModel.pendingWaits.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        MagpieSectionLabel(title: String(localized: "等待更新"))
                        ForEach(viewModel.pendingWaits) { wait in
                            HStack {
                                Text(wait.packageName)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(MagpieTheme.textSecondary)
                                Spacer()
                                Text("\(wait.version ?? "—") → \(wait.latest ?? "—")")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(MagpieTheme.textMuted)
                            }
                            .padding(.vertical, 3)
                        }
                    }
                    .magpieCard()
                }
            }

            if let updated = viewModel.updates?.updated, !updated.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    MagpieSectionLabel(title: String(localized: "最近自动更新"))
                    ForEach(updated.prefix(5)) { item in
                        HStack {
                            Text(item.packageName)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(MagpieTheme.textSecondary)
                            Spacer()
                            Text("\(item.from ?? "—") → \(item.to ?? "—")")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(MagpieTheme.textMuted)
                        }
                        .padding(.vertical, 2)
                    }
                }
                .magpieCard()
            }
        }
    }

    // MARK: - 运行环境
    private var runtimeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            MagpieSectionLabel(title: String(localized: "运行环境"))

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    iconBadge("shippingbox.fill", tint: MagpieTheme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "Bun 插件运行时"))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(MagpieTheme.textPrimary)
                        Text(viewModel.hasBun ? (viewModel.bunVersion ?? String(localized: "已就绪")) : String(localized: "安装第一个插件时自动下载"))
                            .font(.caption2)
                            .foregroundStyle(MagpieTheme.textMuted)
                    }
                    Spacer()
                    MagpieStatusChip(
                        text: viewModel.hasBun ? String(localized: "就绪") : String(localized: "未安装"),
                        color: viewModel.hasBun ? MagpieTheme.green : MagpieTheme.amber
                    )
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)

                Divider().background(MagpieTheme.borderSubtle).padding(.leading, 56)

                HStack(spacing: 12) {
                    iconBadge("network", tint: MagpieTheme.cyan)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "国内镜像"))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(MagpieTheme.textPrimary)
                        Text(String(localized: "通过国内镜像下载 npm 包与 Bun"))
                            .font(.caption2)
                            .foregroundStyle(MagpieTheme.textMuted)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { viewModel.isMirrorOn },
                        set: { on in
                            if let client = app.client {
                                Task { await viewModel.setMirror(client: client, enable: on) }
                            }
                        }
                    ))
                    .labelsHidden()
                    .tint(MagpieTheme.green)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)

                Divider().background(MagpieTheme.borderSubtle).padding(.leading, 56)

                Button {
                    registryDraft = viewModel.registry?.url ?? ""
                    showingRegistry = true
                } label: {
                    HStack(spacing: 12) {
                        iconBadge("link", tint: MagpieTheme.purple)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(localized: "npm Registry"))
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(MagpieTheme.textPrimary)
                            Text(viewModel.registry?.url ?? "https://registry.npmjs.org")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(MagpieTheme.textMuted)
                                .lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(MagpieTheme.textMuted)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .magpieCard(padding: 0)
        }
    }

    private func iconBadge(_ icon: String, tint: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tint.opacity(0.13))
                .frame(width: 30, height: 30)
            Image(systemName: icon)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(tint)
        }
    }

    // MARK: - 手动安装
    private var manualInstallSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(String(localized: "npm 包名、版本或 Git 仓库"), text: $manualSpec)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } footer: {
                    Text(String(localized: "例如 @magpie-community/foo、foo@1.2.3、github:user/repo 或本地文件夹路径。"))
                }
            }
            .navigationTitle(String(localized: "安装插件"))
            .navigationBarTitleDisplayMode(.inline)
            .scrollContentBackground(.hidden)
            .background(MagpieAuroraBackground())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "取消")) { showingManualInstall = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "安装")) {
                        installManual()
                    }
                    .disabled(manualSpec.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isOperating)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func installManual() {
        guard let client = app.client else { return }
        let spec = manualSpec.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            if await viewModel.install(client: client, spec: spec) {
                showingManualInstall = false
            }
        }
    }

    // MARK: - Registry
    private var registrySheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://registry.npmjs.org", text: $registryDraft)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                } header: {
                    Text(String(localized: "npm Registry"))
                } footer: {
                    Text(String(localized: "留空恢复自动选择：环境变量 → 登录 shell → bunfig / .npmrc → 国内镜像 → npm 官方。"))
                }
            }
            .navigationTitle(String(localized: "Registry"))
            .navigationBarTitleDisplayMode(.inline)
            .scrollContentBackground(.hidden)
            .background(MagpieAuroraBackground())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "取消")) { showingRegistry = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "保存")) {
                        guard let client = app.client else { return }
                        let url = registryDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                        Task {
                            await viewModel.setRegistry(client: client, url: url)
                            showingRegistry = false
                        }
                    }
                    .disabled(viewModel.isOperating)
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - 通用
    private func loadAll(client: MagpieAPIClient) async {
        await viewModel.load(client: client)
        await viewModel.loadMarket(client: client)
        await viewModel.loadUpdates(client: client)
    }

    private func emptyState(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 34))
                .foregroundStyle(MagpieTheme.textMuted.opacity(0.65))
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(MagpieTheme.textPrimary)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(MagpieTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .magpieCard()
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(message)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .font(.caption)
        .foregroundStyle(MagpieTheme.red)
        .frame(maxWidth: .infinity, alignment: .leading)
        .magpieCard(padding: 12)
    }
}
