import SwiftUI
import UIKit

/// 路由组列表页：1:1 对齐官方 Web / 客户端设计。
/// 支持自动发现组与自定义组切换、策略彩色徽章（Smart / Order / Rotate / Usage / Pace）及就绪状态。
struct GroupsView: View {
    @Environment(AppModel.self) private var app
    @State private var viewModel = GroupsViewModel()
    @State private var searchText = ""
    @State private var filterTab = FilterTab.all
    @State private var showingCreate = false
    @State private var editingGroup: GroupDTO?
    @State private var deletingGroup: GroupDTO?
    @State private var sharingGroup: GroupDTO?
    @State private var showingSkipSheet = false
    @State private var showingImportSheet = false
    @Namespace private var zoomNamespace

    enum FilterTab: String, CaseIterable, Identifiable {
        case all
        case auto
        case custom

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: return String(localized: "全部")
            case .auto: return String(localized: "自动发现组")
            case .custom: return String(localized: "自定义组")
            }
        }
    }

    private var filteredGroups: [GroupDTO] {
        let base: [GroupDTO]
        switch filterTab {
        case .all: base = viewModel.groups
        case .auto: base = viewModel.groups.filter { $0.isAuto }
        case .custom: base = viewModel.groups.filter { !$0.isAuto }
        }

        if searchText.isEmpty { return base }
        return base.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.ref.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        MagpieNavigationContainer {
            ScrollView {
                VStack(spacing: 16) {
                    foundCard

                    if !viewModel.templates.isEmpty {
                        templateStrip
                    }

                    if !viewModel.pools.isEmpty {
                        poolsCard
                    }

                    // 分类 Segment
                    Picker(String(localized: "类别"), selection: $filterTab) {
                        ForEach(FilterTab.allCases) { tab in
                            Text(tab.title).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)

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

                    if filteredGroups.isEmpty {
                        emptyState
                    } else {
                        MagpieGlassGroup(spacing: 12) {
                            LazyVStack(spacing: 12) {
                                ForEach(filteredGroups) { group in
                                    NavigationLink(value: group.ref) {
                                        GroupCard(group: group)
                                    }
                                    .buttonStyle(.plain)
                                    .matchedTransitionSource(id: group.ref, in: zoomNamespace)
                                    .contextMenu {
                                        Button {
                                            editingGroup = group
                                        } label: {
                                            Label(
                                                group.isAuto ? String(localized: "复制为自定义组…") : String(localized: "编辑…"),
                                                systemImage: "pencil"
                                            )
                                        }
                                        Button {
                                            share(group)
                                        } label: {
                                            Label(String(localized: "复制分享文本"), systemImage: "square.and.arrow.up")
                                        }
                                        Button(role: .destructive) {
                                            deletingGroup = group
                                        } label: {
                                            Label(String(localized: "删除组"), systemImage: "trash")
                                        }
                                    }
                                }
                            }
                        }
                        .animation(.spring(response: 0.35, dampingFraction: 0.86), value: filteredGroups.map(\.id))
                        .transition(.magpieContent)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .padding(.bottom, 96)
            }
            .magpiePageBackground()
            .searchable(text: $searchText, prompt: String(localized: "搜索路由组名称或标识…"))
            .navigationTitle(String(localized: "Routing Groups"))
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .navigationDestination(for: String.self) { ref in
                GroupDetailView(groupRef: ref, viewModel: viewModel)
                    .environment(viewModel)
                    .navigationTransition(.zoom(sourceID: ref, in: zoomNamespace))
            }
            .overlay {
                if viewModel.isLoading && viewModel.groups.isEmpty {
                    ProgressView(String(localized: "加载路由组…"))
                }
            }
            .task {
                if let client = app.client, viewModel.groups.isEmpty {
                    await viewModel.load(client: client)
                }
            }
            .refreshable {
                if let client = app.client {
                    await viewModel.load(client: client)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button {
                            showingImportSheet = true
                        } label: {
                            Label(String(localized: "导入路由组…"), systemImage: "square.and.arrow.down")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingCreate = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.body.weight(.semibold))
                    }
                    .accessibilityLabel(String(localized: "新建路由组"))
                }
            }
            .sheet(isPresented: $showingCreate) {
                GroupEditView(editing: nil)
                    .environment(viewModel)
            }
            .sheet(isPresented: $showingImportSheet) {
                GroupImportSheet()
                    .environment(viewModel)
            }
            .sheet(item: $editingGroup) { group in
                GroupEditView(editing: group)
                    .environment(viewModel)
            }
            .sheet(item: $sharingGroup) { group in
                GroupShareSheet(group: group)
                    .environment(viewModel)
            }
            .alert(
                String(localized: "删除路由组「\(deletingGroup?.name ?? "")」？"),
                isPresented: Binding(
                    get: { deletingGroup != nil },
                    set: { if !$0 { deletingGroup = nil } }
                )
            ) {
                Button(String(localized: "删除"), role: .destructive) {
                    if let group = deletingGroup, let client = app.client {
                        Task { _ = await viewModel.delete(client: client, id: group.id) }
                    }
                    deletingGroup = nil
                }
                Button(String(localized: "取消"), role: .cancel) { deletingGroup = nil }
            } message: {
                Text(String(localized: "删除后，使用 group/\(deletingGroup?.id ?? "") 的 Agent 需要改选其它模型。"))
            }
        }
        .environment(viewModel)
    }

    // MARK: - 自动发现
    private var foundCard: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(MagpieTheme.accentSoft)
                    .frame(width: 36, height: 36)
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(MagpieTheme.accent)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "自动发现路由组"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MagpieTheme.textPrimary)
                Text(String(localized: "把多个 Provider 的同名模型合并成 auto/ 组"))
                    .font(.caption2)
                    .foregroundStyle(MagpieTheme.textMuted)
            }

            Spacer(minLength: 6)

            Button {
                showingSkipSheet = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(MagpieTheme.textMuted)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "选择参与自动发现的 Provider"))

            Toggle("", isOn: Binding(
                get: { viewModel.found },
                set: { on in
                    guard let client = app.client else { return }
                    Task { _ = await viewModel.setFound(client: client, on: on) }
                }
            ))
            .labelsHidden()
            .tint(MagpieTheme.green)
        }
        .magpieCard(padding: 13)
        .sheet(isPresented: $showingSkipSheet) {
            GroupSkipSheet(
                items: viewModel.skippable,
                current: viewModel.skip ?? []
            )
            .environment(viewModel)
        }
    }

    private func share(_ group: GroupDTO) {
        sharingGroup = group
    }

    // MARK: - 多 Key / 多账号池
    private var poolsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            MagpieSectionLabel(
                title: String(localized: "多账号池"),
                detail: String(localized: "这些 Provider 的请求会在多个 Key / 账号之间分发")
            )

            VStack(spacing: 0) {
                ForEach(Array(viewModel.pools.enumerated()), id: \.element.id) { index, pool in
                    HStack(spacing: 10) {
                        MagpieIconView(icon: pool.icon ?? pool.provider, name: pool.name, size: 28, cornerRadius: 6)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(pool.name)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(MagpieTheme.textPrimary)
                                .lineLimit(1)
                            Text(
                                (pool.kind == "account")
                                    ? String(localized: "\(pool.who?.count ?? 0) 个账号")
                                    : String(localized: "\(pool.who?.count ?? 0) 个 Key")
                            )
                            .font(.caption2)
                            .foregroundStyle(MagpieTheme.textMuted)
                        }

                        Spacer(minLength: 4)

                        HStack(spacing: 4) {
                            Image(systemName: GroupRouting.icon(pool.routing))
                            Text(GroupRouting.displayName(pool.routing))
                        }
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(MagpieTheme.accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(MagpieTheme.accentSoft)
                        .clipShape(Capsule())
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)

                    if index < viewModel.pools.count - 1 {
                        Divider().background(MagpieTheme.borderSubtle).padding(.leading, 52)
                    }
                }
            }
            .magpieCard(padding: 0)
        }
    }

    // MARK: - 官方模板
    private var templateStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            MagpieSectionLabel(
                title: String(localized: "官方模板"),
                detail: String(localized: "用你自己的模型一键生成常用组")
            )

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(viewModel.templates) { template in
                        Button {
                            addTemplate(template)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 5) {
                                    Image(systemName: templateIcon(template.kind))
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(MagpieTheme.accent)
                                    Text(templateName(template.kind))
                                        .font(.system(size: 12.5, weight: .semibold))
                                        .foregroundStyle(MagpieTheme.textPrimary)
                                }
                                Text(template.group.name)
                                    .font(.caption2)
                                    .foregroundStyle(MagpieTheme.textSecondary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                Text(String(localized: "\(template.group.members?.count ?? 0) 个成员"))
                                    .font(.system(size: 9.5, design: .monospaced))
                                    .foregroundStyle(MagpieTheme.textMuted)
                            }
                            .frame(width: 150, alignment: .leading)
                            .magpieCard(padding: 12)
                        }
                        .buttonStyle(MagpiePressableStyle())
                    }
                }
            }
            .scrollClipDisabled()
        }
    }

    private func addTemplate(_ template: GroupTemplateDTO) {
        guard let client = app.client else { return }
        MagpieHaptics.medium()
        Task {
            _ = await viewModel.addTemplate(
                client: client,
                kind: template.kind,
                name: template.group.name
            )
        }
    }

    private func templateName(_ kind: String) -> String {
        switch kind {
        case "smart": return String(localized: "难易分流")
        case "thrifty": return String(localized: "便宜优先")
        case "steady": return String(localized: "永不卡住")
        case "plan": return String(localized: "先规划")
        case "fast": return String(localized: "最快优先")
        case "even": return String(localized: "均匀分摊")
        default: return kind.capitalized
        }
    }

    private func templateIcon(_ kind: String) -> String {
        switch kind {
        case "smart": return "brain.head.profile"
        case "thrifty": return "leaf.fill"
        case "steady": return "shield.lefthalf.filled"
        case "plan": return "list.clipboard.fill"
        case "fast": return "bolt.fill"
        case "even": return "scale.3d"
        default: return "square.3.layers.3d"
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 72, height: 72)
                    .overlay(Circle().stroke(.white.opacity(0.16), lineWidth: 0.8))
                    .shadow(color: MagpieTheme.accent.opacity(0.1), radius: 10, y: 4)
                Image(systemName: "square.3.layers.3d.slash")
                    .font(.system(size: 28))
                    .foregroundStyle(MagpieTheme.textMuted)
            }
            Text(String(localized: "暂无路由组"))
                .font(.headline)
                .foregroundStyle(MagpieTheme.textPrimary)
            Text(String(localized: "当有多个提供方支持相同模型，或在 Web 端配置了自定义路由组时，将在此汇总展示。"))
                .font(.subheadline)
                .foregroundStyle(MagpieTheme.textSecondary)
                .multilineTextAlignment(.center)

            Button {
                showingCreate = true
            } label: {
                Label(String(localized: "新建路由组"), systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
            }
            .buttonStyle(MagpiePrimaryButtonStyle(tint: MagpieTheme.accent))
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

// MARK: - 自动发现排除项
private struct GroupSkipSheet: View {
    let items: [GroupSkippableDTO]
    let current: [String]
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var app
    @Environment(GroupsViewModel.self) private var viewModel
    @State private var excluded: Set<String> = []
    @State private var defaultSink = false
    @State private var firstToken = 0
    @State private var patience = 0
    @State private var working = false
    @State private var errorMessage: String?
    @State private var primed = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(items) { item in
                        Button {
                            if excluded.contains(item.id) {
                                excluded.remove(item.id)
                            } else {
                                excluded.insert(item.id)
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: excluded.contains(item.id) ? "xmark.circle.fill" : "checkmark.circle")
                                    .foregroundStyle(excluded.contains(item.id) ? MagpieTheme.textMuted : MagpieTheme.green)
                                Text(item.name)
                                    .foregroundStyle(MagpieTheme.textPrimary)
                                Spacer()
                                Text(item.id)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(MagpieTheme.textMuted)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text(String(localized: "勾掉不参与自动发现组的三方"))
                } footer: {
                    Text(String(localized: "被排除的 Provider 仍可手动加入自定义组。"))
                }

                Section {
                    Toggle(isOn: $defaultSink) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(localized: "限流后置"))
                            Text(String(localized: "仍有额度但被限流的账号排到后面"))
                                .font(.caption2)
                                .foregroundStyle(MagpieTheme.textMuted)
                        }
                    }
                    .tint(MagpieTheme.green)

                    Stepper(value: $firstToken, in: 0...600, step: 5) {
                        Text(String(localized: "首 Token 等待：\(firstToken) 秒"))
                    }

                    Stepper(value: $patience, in: 0...600, step: 5) {
                        Text(String(localized: "耐心：\(patience) 秒"))
                    }
                } header: {
                    Text(String(localized: "所有组的默认值"))
                } footer: {
                    Text(String(localized: "0 表示不限制；单个组可在编辑页里覆盖。"))
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(MagpieTheme.red)
                    }
                }
            }
            .navigationTitle(String(localized: "自动发现与默认值"))
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
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
                excluded = Set(current)
                defaultSink = viewModel.defaults.sink ?? false
                firstToken = viewModel.defaults.firstToken ?? 0
                patience = viewModel.defaults.patience ?? 0
            }
        }
    }

    private func save() {
        guard let client = app.client else { return }
        working = true
        errorMessage = nil
        Task {
            let skipOK = await viewModel.setSkip(client: client, skip: Array(excluded).sorted())
            let defaultsOK = await viewModel.setDefaults(
                client: client,
                sink: defaultSink,
                firstToken: firstToken,
                patience: patience
            )
            working = false
            if skipOK && defaultsOK {
                dismiss()
            } else {
                errorMessage = viewModel.errorMessage ?? String(localized: "保存失败")
            }
        }
    }
}

// MARK: - 导入路由组
private struct GroupImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var app
    @Environment(GroupsViewModel.self) private var viewModel

    @State private var text = ""
    @State private var replaceExisting = false
    @State private var working = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $text)
                        .font(.system(size: 10.5, design: .monospaced))
                        .frame(minHeight: 160)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text(String(localized: "分享文本"))
                } footer: {
                    Text(String(localized: "把另一台 magpie 里「分享路由组」复制的文本粘贴到这里。"))
                }

                Section {
                    Toggle(String(localized: "覆盖同 ID 的现有组"), isOn: $replaceExisting)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(MagpieTheme.red)
                    }
                }
            }
            .navigationTitle(String(localized: "导入路由组"))
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
            .scrollContentBackground(.hidden)
            .background(MagpieAuroraBackground())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "取消")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        importGroup()
                    } label: {
                        if working {
                            ProgressView().controlSize(.small)
                        } else {
                            Text(String(localized: "导入")).fontWeight(.semibold)
                        }
                    }
                    .disabled(working || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func importGroup() {
        guard let client = app.client else { return }
        working = true
        errorMessage = nil
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            let ok = await viewModel.importGroup(
                client: client,
                text: value,
                replaceExisting: replaceExisting
            )
            working = false
            if ok {
                dismiss()
            } else {
                errorMessage = viewModel.errorMessage ?? String(localized: "导入失败，请检查文本。")
            }
        }
    }
}

// MARK: - 分享 / 导入
private struct GroupShareSheet: View {
    let group: GroupDTO
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var app
    @Environment(GroupsViewModel.self) private var viewModel
    @State private var text: String?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(String(localized: "把下面的文本粘贴到另一台 magpie 的「导入路由组」即可完整复刻这个组（不含任何密钥）。"))
                        .font(.caption)
                        .foregroundStyle(MagpieTheme.textSecondary)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(MagpieTheme.red)
                    }

                    if let text {
                        Text(text)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(MagpieTheme.textPrimary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(MagpieTheme.cardSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                        Button {
                            UIPasteboard.general.string = text
                            MagpieHaptics.success()
                        } label: {
                            Label(String(localized: "复制到剪贴板"), systemImage: "doc.on.doc.fill")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(MagpiePrimaryButtonStyle(tint: MagpieTheme.accent))
                    } else {
                        ProgressView(String(localized: "生成分享文本…"))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                    }
                }
                .padding(16)
            }
            .magpiePageBackground()
            .navigationTitle(String(localized: "分享「\(group.name)」"))
            .navigationBarTitleDisplayMode(.inline)
            .scrollContentBackground(.hidden)
            .background(MagpieAuroraBackground())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "完成")) { dismiss() }
                }
            }
            .task {
                guard text == nil, let client = app.client else { return }
                if let shared = await viewModel.share(client: client, id: group.id) {
                    text = shared
                } else {
                    errorMessage = viewModel.errorMessage ?? String(localized: "生成分享文本失败")
                }
            }
        }
    }
}

// MARK: - 原版风格 Group 卡片
private struct GroupCard: View {
    let group: GroupDTO

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                // 图标
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(group.isAuto ? MagpieTheme.accentSoft : MagpieTheme.pill)
                        .frame(width: 36, height: 36)
                    Image(systemName: group.isAuto ? "wand.and.stars" : "square.stack.3d.up")
                        .font(.system(size: 16))
                        .foregroundStyle(group.isAuto ? MagpieTheme.accent : MagpieTheme.textSecondary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(group.name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(MagpieTheme.textPrimary)

                        if group.isAuto {
                            Text("AUTO")
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(MagpieTheme.accentSoft)
                                .foregroundStyle(MagpieTheme.accent)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }

                    Text(group.ref)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(MagpieTheme.textMuted)
                        .lineLimit(1)
                }

                Spacer()

                if group.ready == true {
                    HStack(spacing: 4) {
                        MagpiePulseDot(color: MagpieTheme.green)
                        Text(String(localized: "就绪"))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(MagpieTheme.green)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(MagpieTheme.greenSoft)
                    .clipShape(Capsule())
                }

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MagpieTheme.textMuted)
            }

            Divider()
                .background(MagpieTheme.borderSubtle)

            // 底部策略、成员头像与状态
            HStack(spacing: 8) {
                if let routing = group.routing, !routing.isEmpty {
                    strategyBadge(routing: routing, title: group.routingDisplayName)
                }

                if group.unlists == true {
                    MagpieStatusChip(text: String(localized: "仅路由组"), color: MagpieTheme.cyan)
                }

                memberAvatars

                Spacer(minLength: 0)

                if let members = group.members {
                    Text("\(members.count)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(MagpieTheme.textMuted)
                    Image(systemName: "square.stack.3d.up")
                        .font(.system(size: 9))
                        .foregroundStyle(MagpieTheme.textMuted)
                }
            }
        }
        .magpieLiquidCard(padding: 14, cornerRadius: 20)
    }

    /// 组成员的前几个品牌图标，直观显示一个组由谁支撑。
    private var memberAvatars: some View {
        HStack(spacing: -6) {
            let info = group.memberInfo ?? []
            ForEach(Array(info.prefix(4).enumerated()), id: \.element.id) { _, member in
                MagpieIconView(
                    icon: member.icon ?? member.provider,
                    name: member.name ?? member.id,
                    size: 20,
                    cornerRadius: 5
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(MagpieTheme.card, lineWidth: 1.5)
                )
            }
            if info.count > 4 {
                Text("+\(info.count - 4)")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(MagpieTheme.textSecondary)
                    .frame(width: 20, height: 20)
                    .background(MagpieTheme.pill)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(MagpieTheme.card, lineWidth: 1.5)
                    )
            }
        }
    }

    @ViewBuilder
    private func strategyBadge(routing: String, title: String) -> some View {
        let fg = strategyColor(for: routing)
        HStack(spacing: 3) {
            Image(systemName: GroupRouting.icon(routing))
            Text(title)
        }
        .font(.system(size: 10.5, weight: .semibold))
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(fg.opacity(0.13))
        .foregroundStyle(fg)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(fg.opacity(0.16), lineWidth: 0.5))
    }

    private func strategyColor(for routing: String) -> Color {
        switch routing {
        case "smart": return MagpieTheme.green
        case "order": return MagpieTheme.accent
        case "rotate": return Color(hex: "8b5cf6")
        case "usage": return MagpieTheme.amber
        case "pace": return Color(hex: "ec4899")
        case "fast": return MagpieTheme.cyan
        case "manual": return MagpieTheme.textSecondary
        default: return MagpieTheme.textSecondary
        }
    }
}
