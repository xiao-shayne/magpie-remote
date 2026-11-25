import SwiftUI

/// Library 市场：技能（skills.sh）与 MCP 服务器（Registry + magpie 精选）的浏览与安装。
struct LibraryMarketSheet: View {
    var initialKind: String = "skills"

    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var app
    @Environment(LibraryViewModel.self) private var viewModel

    @State private var kind = "skills"
    @State private var searchText = ""
    @State private var installingID: String?
    @State private var serverFormItem: LibraryMarketItemDTO?
    @State private var errorMessage: String?
    @State private var primed = false

    private var items: [LibraryMarketItemDTO] { viewModel.marketItems }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $kind) {
                    Text(String(localized: "技能市场")).tag("skills")
                    Text(String(localized: "MCP 市场")).tag("servers")
                    Text(String(localized: "Claude 插件")).tag("claude")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(MagpieTheme.textMuted)
                    TextField(String(localized: "搜索市场…"), text: $searchText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit { load() }
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                            load()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(MagpieTheme.textMuted)
                        }
                        .buttonStyle(.plain)
                    }
                    Button(String(localized: "搜索")) {
                        load()
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(MagpieTheme.accent)
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 9)
                .background(MagpieTheme.card.opacity(0.7), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(MagpieTheme.borderSubtle, lineWidth: 0.8)
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 10)

                if let error = viewModel.marketError ?? errorMessage {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(MagpieTheme.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                }

                if viewModel.marketLoading && items.isEmpty {
                    ProgressView(String(localized: "读取市场…"))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if items.isEmpty {
                    ContentUnavailableView(
                        String(localized: "没有可显示的条目"),
                        systemImage: "storefront",
                        description: Text(String(localized: "换一个关键词，或稍后再试。"))
                    )
                    .frame(maxHeight: .infinity)
                } else {
                    List {
                        ForEach(items) { item in
                            marketRow(item)
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .magpiePageBackground()
            .navigationTitle(String(localized: "Library 市场"))
            .navigationBarTitleDisplayMode(.inline)
            .scrollContentBackground(.hidden)
            .background(MagpieAuroraBackground())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "完成")) { dismiss() }
                }
            }
            .task {
                guard !primed else { return }
                primed = true
                kind = initialKind
                await loadAsync()
            }
            .onChange(of: kind) { _, _ in
                load()
            }
            .sheet(item: $serverFormItem) { item in
                MarketServerInputsSheet(item: item) { values in
                    await install(item, values: values)
                }
            }
        }
    }

    private func marketRow(_ item: LibraryMarketItemDTO) -> some View {
        HStack(alignment: .top, spacing: 11) {
            marketLogo(item)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(item.displayName)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(MagpieTheme.textPrimary)
                        .lineLimit(1)
                    if item.official == true {
                        MagpieStatusChip(text: String(localized: "官方"), color: MagpieTheme.green)
                    }
                    if item.optIn == true {
                        MagpieStatusChip(text: String(localized: "按需"), color: MagpieTheme.amber)
                    }
                }

                if let description = item.description, !description.isEmpty {
                    Text(description)
                        .font(.caption2)
                        .foregroundStyle(MagpieTheme.textSecondary)
                        .lineLimit(2)
                }

                HStack(spacing: 6) {
                    if let publisher = item.publisher, !publisher.isEmpty {
                        Text(publisher)
                    } else if let source = item.source, !source.isEmpty {
                        Text(source)
                    }
                    if let installs = item.installs, installs > 0 {
                        Text("· \(UsageDTO.formatTokens(installs)) \(String(localized: "次安装"))")
                    }
                    if let transport = item.transport, !transport.isEmpty {
                        Text("· \(transport.uppercased())")
                    }
                }
                .font(.caption2)
                .foregroundStyle(MagpieTheme.textMuted)
                .lineLimit(1)
            }

            Spacer(minLength: 4)

            if item.isAdded {
                MagpieStatusChip(text: String(localized: "已添加"), color: MagpieTheme.green)
            } else if installingID == item.displayName {
                ProgressView().controlSize(.small)
            } else {
                Button(String(localized: "添加")) {
                    add(item)
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.plain)
                .foregroundStyle(MagpieTheme.accent)
            }
        }
        .padding(.vertical, 4)
    }

    private func marketLogo(_ item: LibraryMarketItemDTO) -> some View {
        Group {
            if let icon = item.icon, !icon.isEmpty,
               let base = app.activeURL,
               let url = URL(string: "/api/library/icon?u=\(icon.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? icon)", relativeTo: base) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFit()
                    } else {
                        fallbackLogo(item)
                    }
                }
            } else {
                fallbackLogo(item)
            }
        }
        .frame(width: 32, height: 32)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func fallbackLogo(_ item: LibraryMarketItemDTO) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(MagpieTheme.accentSoft)
            Text(String(item.displayName.prefix(1)).uppercased())
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(MagpieTheme.accent)
        }
    }

    private func add(_ item: LibraryMarketItemDTO) {
        if kind == "servers", item.needsInputs || item.optIn == true {
            serverFormItem = item
        } else {
            Task { _ = await install(item, values: [:]) }
        }
    }

    private func install(_ item: LibraryMarketItemDTO, values: [String: String]) async -> Bool {
        guard let client = app.client else { return false }
        installingID = item.displayName
        defer { installingID = nil }
        let agents = viewModel.activeAgents.map(\.id)
        let ok: Bool
        if kind == "skills" {
            ok = await viewModel.installMarketSkill(client: client, item: item, agents: agents)
        } else if kind == "claude" {
            ok = await viewModel.installMarketClaudePlugin(client: client, item: item, agents: agents)
        } else {
            ok = await viewModel.installMarketServer(
                client: client,
                item: item,
                values: values,
                agents: agents
            )
        }
        if ok {
            serverFormItem = nil
        } else {
            errorMessage = viewModel.marketError
        }
        return ok
    }

    private func load() {
        Task { await loadAsync() }
    }

    private func loadAsync() async {
        guard let client = app.client else { return }
        await viewModel.loadMarket(client: client, kind: kind, query: searchText)
    }
}

// MARK: - 市场服务器的输入表单
private struct MarketServerInputsSheet: View {
    let item: LibraryMarketItemDTO
    let onAdd: ([String: String]) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var values: [String: String] = [:]
    @State private var working = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                if let description = item.description, !description.isEmpty {
                    Section {
                        Text(description)
                            .font(.caption)
                            .foregroundStyle(MagpieTheme.textSecondary)
                    }
                }

                ForEach(item.inputs ?? []) { input in
                    Section {
                        if input.secret == true {
                            SecureField(input.placeholder ?? input.key, text: binding(input.key))
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        } else {
                            TextField(input.placeholder ?? input.key, text: binding(input.key))
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                    } header: {
                        Text(input.displayLabel + (input.required == true ? "" : String(localized: "（可选）")))
                    } footer: {
                        if let description = input.description, !description.isEmpty {
                            Text(description)
                        }
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(MagpieTheme.red)
                    }
                }
            }
            .navigationTitle(item.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .scrollContentBackground(.hidden)
            .background(MagpieAuroraBackground())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "取消")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        add()
                    } label: {
                        if working {
                            ProgressView().controlSize(.small)
                        } else {
                            Text(String(localized: "添加")).fontWeight(.semibold)
                        }
                    }
                    .disabled(working || !canAdd)
                }
            }
        }
    }

    private var canAdd: Bool {
        for input in item.inputs ?? [] where input.required == true {
            if (values[input.key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return false
            }
        }
        return true
    }

    private func binding(_ key: String) -> Binding<String> {
        Binding(
            get: { values[key] ?? "" },
            set: { values[key] = $0 }
        )
    }

    private func add() {
        working = true
        errorMessage = nil
        var trimmed: [String: String] = [:]
        for (key, value) in values {
            let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { trimmed[key] = text }
        }
        Task {
            let ok = await onAdd(trimmed)
            working = false
            if ok { dismiss() } else { errorMessage = String(localized: "添加失败，请检查填写内容。") }
        }
    }
}
