import SwiftUI

/// Sessions › 管理：录制、读取来源、按 Agent 删除会话、回收站恢复。
struct SessionsManageSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var app
    @State private var viewModel = SessionsManageViewModel()

    @State private var selectedIDs: Set<String> = []
    @State private var confirmingPurgeAll = false
    @State private var confirmingDelete = false
    @State private var primed = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    recordingCard
                    readsCard
                    agentsPicker
                    sessionsCard
                    trashCard
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .padding(.bottom, 40)
            }
            .magpiePageBackground()
            .navigationTitle(String(localized: "会话管理"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "完成")) { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    if viewModel.isSaving {
                        ProgressView().controlSize(.small)
                    }
                }
            }
            .task {
                guard !primed else { return }
                primed = true
                guard let client = app.client else { return }
                await viewModel.load(client: client)
            }
            .confirmationDialog(
                String(localized: "删除选中的 \(selectedIDs.count) 个会话？"),
                isPresented: $confirmingDelete,
                titleVisibility: .visible
            ) {
                Button(String(localized: "删除"), role: .destructive) {
                    deleteSelected()
                }
                Button(String(localized: "取消"), role: .cancel) {}
            } message: {
                Text(String(localized: "会话会移入 magpie 的回收站，可以再恢复。"))
            }
            .confirmationDialog(
                String(localized: "清空所有会话？"),
                isPresented: $confirmingPurgeAll,
                titleVisibility: .visible
            ) {
                Button(String(localized: "全部清空"), role: .destructive) {
                    guard let client = app.client else { return }
                    Task { await viewModel.purgeAll(client: client) }
                }
                Button(String(localized: "取消"), role: .cancel) {}
            } message: {
                Text(String(localized: "所有 Agent 的会话都会被移入回收站。"))
            }
        }
    }

    // MARK: - 录制

    private var recordingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "record.circle")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(MagpieTheme.red)
                    .frame(width: 34, height: 34)
                    .background(MagpieTheme.red.opacity(0.13), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "记录会话"))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(MagpieTheme.textPrimary)
                    Text(String(localized: "记录各 Agent 的对话用于统计与回看"))
                        .font(.caption2)
                        .foregroundStyle(MagpieTheme.textMuted)
                }

                Spacer(minLength: 8)

                Toggle("", isOn: Binding(
                    get: { viewModel.recording },
                    set: { on in
                        guard let client = app.client else { return }
                        Task { await viewModel.setRecording(client: client, on: on) }
                    }
                ))
                .labelsHidden()
                .tint(MagpieTheme.red)
            }

            if viewModel.data?.recorded == true {
                Button(String(localized: "清除已记录的数据")) {
                    guard let client = app.client else { return }
                    Task { await viewModel.clearRecording(client: client) }
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.plain)
                .foregroundStyle(MagpieTheme.red)
            }
        }
        .magpieCard(padding: 14, cornerRadius: 18)
    }

    // MARK: - 读取来源

    @ViewBuilder
    private var readsCard: some View {
        let reads = viewModel.reads
        let found = reads?.found ?? []
        if !found.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(MagpieTheme.cyan)
                        .frame(width: 34, height: 34)
                        .background(MagpieTheme.cyan.opacity(0.13), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "读取会话的 Agent"))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(MagpieTheme.textPrimary)
                        Text(String(localized: "关闭后该 Agent 的会话不出现在统计里"))
                            .font(.caption2)
                            .foregroundStyle(MagpieTheme.textMuted)
                    }

                    Spacer(minLength: 8)

                    Toggle("", isOn: Binding(
                        get: { reads?.all ?? true },
                        set: { all in
                            guard let client = app.client else { return }
                            Task {
                                await viewModel.setReads(
                                    client: client,
                                    all: all,
                                    agents: found.filter { $0.on == true }.compactMap(\.agent)
                                )
                            }
                        }
                    ))
                    .labelsHidden()
                    .tint(MagpieTheme.cyan)
                }

                if reads?.all != true {
                    ForEach(found) { source in
                        HStack(spacing: 8) {
                            MagpieIconView(icon: source.icon, name: source.displayName, size: 20, cornerRadius: 5)
                            Text(source.displayName)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(MagpieTheme.textPrimary)
                            if source.isNew == true {
                                MagpieStatusChip(text: String(localized: "新检测"), color: MagpieTheme.amber)
                            }
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { source.on ?? false },
                                set: { on in
                                    guard let client = app.client else { return }
                                    var agents = found.filter { $0.on == true }.compactMap(\.agent)
                                    if let id = source.agent {
                                        if on {
                                            if !agents.contains(id) { agents.append(id) }
                                        } else {
                                            agents.removeAll { $0 == id }
                                        }
                                    }
                                    Task {
                                        await viewModel.setReads(client: client, all: false, agents: agents)
                                    }
                                }
                            ))
                            .labelsHidden()
                            .tint(MagpieTheme.cyan)
                            .scaleEffect(0.85)
                        }
                    }
                }
            }
            .magpieCard(padding: 14, cornerRadius: 18)
        }
    }

    // MARK: - Agent 选择

    private var agentsPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(viewModel.agents) { agent in
                    Button {
                        selectedIDs = []
                        guard let client = app.client else { return }
                        Task { await viewModel.load(client: client, agent: agent.agent) }
                    } label: {
                        HStack(spacing: 5) {
                            MagpieIconView(icon: agent.icon, name: agent.displayName, size: 16, cornerRadius: 4)
                            Text(agent.displayName)
                                .font(.caption.weight(.medium))
                            Text("\(agent.count ?? 0)")
                                .font(.system(size: 9.5, design: .monospaced))
                                .foregroundStyle(MagpieTheme.textMuted)
                        }
                        .magpieChip(isSelected: viewModel.selectedAgent == agent.agent)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
        }
        .scrollClipDisabled()
    }

    // MARK: - 会话

    private var sessionsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                MagpieSectionLabel(
                    title: String(localized: "会话"),
                    detail: String(localized: "\(viewModel.sessions.count) 个")
                )
                Spacer()
                if !viewModel.sessions.isEmpty {
                    Button(selectedIDs.count == viewModel.sessions.count
                           ? String(localized: "取消全选")
                           : String(localized: "全选")) {
                        if selectedIDs.count == viewModel.sessions.count {
                            selectedIDs = []
                        } else {
                            selectedIDs = Set(viewModel.sessions.map(\.id))
                        }
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(MagpieTheme.accent)
                }
            }

            if viewModel.isLoading && viewModel.sessions.isEmpty {
                ProgressView(String(localized: "读取会话…"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else if viewModel.sessions.isEmpty {
                Text(String(localized: "这个 Agent 没有可管理的会话。"))
                    .font(.caption)
                    .foregroundStyle(MagpieTheme.textMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else {
                ForEach(viewModel.sessions) { session in
                    sessionRow(session)
                }

                if !selectedIDs.isEmpty {
                    HStack(spacing: 10) {
                        Text(String(localized: "已选 \(selectedIDs.count) 个"))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(MagpieTheme.textSecondary)
                        Spacer()
                        Button(String(localized: "删除")) {
                            confirmingDelete = true
                        }
                        .buttonStyle(MagpiePrimaryButtonStyle(tint: MagpieTheme.red))
                    }
                    .padding(.top, 4)
                }

                Button(String(localized: "清空所有会话…")) {
                    confirmingPurgeAll = true
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.plain)
                .foregroundStyle(MagpieTheme.red)
                .padding(.top, 4)
            }
        }
    }

    private func sessionRow(_ session: SessionManageItemDTO) -> some View {
        Button {
            if selectedIDs.contains(session.id) {
                selectedIDs.remove(session.id)
            } else {
                selectedIDs.insert(session.id)
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: selectedIDs.contains(session.id) ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17))
                    .foregroundStyle(selectedIDs.contains(session.id) ? MagpieTheme.accent : MagpieTheme.border)

                VStack(alignment: .leading, spacing: 3) {
                    Text(session.title?.isEmpty == false ? session.title! : String(localized: "未命名会话"))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(MagpieTheme.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        if let last = session.last {
                            Text(SessionDate.short(last))
                        }
                        if let messages = session.messages, messages > 0 {
                            Text("· \(messages) 条消息")
                        }
                        if let size = session.size, size > 0 {
                            Text("· " + ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(MagpieTheme.textMuted)
                    .lineLimit(1)
                }

                Spacer(minLength: 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .magpieCard(padding: 12, cornerRadius: 16)
        }
        .buttonStyle(MagpiePressableStyle())
        .disabled(session.deletable == false)
        .opacity(session.deletable == false ? 0.5 : 1)
    }

    // MARK: - 回收站

    @ViewBuilder
    private var trashCard: some View {
        let trash = viewModel.trash
        if !trash.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                MagpieSectionLabel(
                    title: String(localized: "回收站"),
                    detail: trash.count > 20
                        ? String(localized: "\(trash.count) 个，显示最近 20 个")
                        : String(localized: "\(trash.count) 个可恢复")
                )

                ForEach(trash.prefix(20), id: \.key) { item in
                    HStack(spacing: 10) {
                        Image(systemName: "trash")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(MagpieTheme.textMuted)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title?.isEmpty == false ? item.title! : String(localized: "未命名会话"))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(MagpieTheme.textPrimary)
                                .lineLimit(1)
                            Text([item.agent, item.last.map(SessionDate.short)]
                                .compactMap { $0 }
                                .joined(separator: " · "))
                                .font(.caption2)
                                .foregroundStyle(MagpieTheme.textMuted)
                        }

                        Spacer(minLength: 4)

                        Button(String(localized: "恢复")) {
                            guard let client = app.client else { return }
                            Task { await viewModel.restore(client: client, key: item.key) }
                        }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.plain)
                        .foregroundStyle(MagpieTheme.green)
                    }
                    .magpieCard(padding: 12, cornerRadius: 16)
                }
            }
        }
    }

    private func deleteSelected() {
        guard let client = app.client, let agent = viewModel.selectedAgent else { return }
        let ids = Array(selectedIDs)
        selectedIDs = []
        Task {
            await viewModel.delete(client: client, agent: agent, ids: ids)
            await viewModel.load(client: client, agent: agent)
        }
    }
}

/// 会话时间戳的展示格式（服务端为 ISO8601 字符串）。
private enum SessionDate {
    static func short(_ iso: String) -> String {
        String(iso.prefix(16)).replacingOccurrences(of: "T", with: " ")
    }
}
