import SwiftUI

/// 新建 / 编辑路由组：对齐官方 Routing 页的组编辑面板。
/// 支持策略、亲和性、成员排序、模型选择与「仅经路由组使用」。
struct GroupEditView: View {
    /// nil = 新建；否则编辑该组。
    let editing: GroupDTO?

    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var app
    @Environment(GroupsViewModel.self) private var viewModel

    @State private var nameDraft = ""
    @State private var idDraft = ""
    @State private var routingDraft = "smart"
    @State private var affinityDraft = ""
    @State private var unlistedDraft = false
    @State private var sinkDraft = false
    @State private var members: [String] = []
    @State private var showingMemberPicker = false
    @State private var showingManualMember = false
    @State private var manualMember = ""
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var primed = false
    @State private var classifierDraft = ""
    @State private var rulesDraft = ""
    @State private var showingAdvanced = false
    @State private var rulesError: String?

    private var isEditing: Bool { editing != nil }
    private var fromID: String? {
        guard let editing, !editing.isAuto else { return nil }
        return editing.id
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let saveError {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text(saveError)
                            Spacer(minLength: 0)
                        }
                        .font(.caption)
                        .foregroundStyle(MagpieTheme.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .magpieCard(padding: 12)
                    }

                    basicsCard
                    strategyCard
                    advancedCard
                    membersCard
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .magpiePageBackground()
            .navigationTitle(isEditing ? String(localized: "编辑路由组") : String(localized: "新建路由组"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "取消")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        save()
                    } label: {
                        if isSaving {
                            ProgressView().controlSize(.small)
                        } else {
                            Text(String(localized: "保存")).fontWeight(.semibold)
                        }
                    }
                    .disabled(isSaving || slugifiedID.isEmpty || nameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .sheet(isPresented: $showingMemberPicker) {
                GroupMemberPicker(models: viewModel.models, selected: $members)
            }
            .alert(String(localized: "手动添加成员"), isPresented: $showingManualMember) {
                TextField("provider/model", text: $manualMember)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button(String(localized: "取消"), role: .cancel) { manualMember = "" }
                Button(String(localized: "添加")) {
                    let value = manualMember.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !value.isEmpty, !members.contains(value) {
                        members.append(value)
                    }
                    manualMember = ""
                }
            } message: {
                Text(String(localized: "支持固定推理档（provider/model:high）、固定账号（provider/model#id）或嵌套组（group/id）。"))
            }
            .task { primeIfNeeded() }
            .onAppear { primeIfNeeded() }
        }
    }

    // MARK: - 基础信息
    private var basicsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text(String(localized: "名称"))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(MagpieTheme.textMuted)
                TextField(String(localized: "例如 Coding 主力组"), text: $nameDraft)
                    .padding(10)
                    .background(MagpieTheme.cardSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(String(localized: "ID（Agent 通过 group/ID 选择它）"))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(MagpieTheme.textMuted)
                TextField("my-group", text: $idDraft)
                    .font(.system(size: 12, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(10)
                    .background(MagpieTheme.cardSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text("group/\(slugifiedID)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(MagpieTheme.accent)
            }

            Toggle(isOn: $unlistedDraft) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "仅经路由组使用"))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(MagpieTheme.textPrimary)
                    Text(String(localized: "组的模型不直接出现在 Agent 的模型列表"))
                        .font(.caption2)
                        .foregroundStyle(MagpieTheme.textMuted)
                }
            }
            .tint(MagpieTheme.green)
        }
        .magpieCard()
    }

    // MARK: - 策略
    private var strategyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: GroupRouting.icon(routingDraft))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(MagpieTheme.accent)
                Text(String(localized: "分发策略"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MagpieTheme.textPrimary)
                Spacer()
                Picker("", selection: $routingDraft) {
                    ForEach(GroupRouting.editable, id: \.id) { item in
                        Text(item.label).tag(item.id)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .tint(MagpieTheme.accent)
            }

            Text(GroupRouting.description(routingDraft))
                .font(.caption)
                .foregroundStyle(MagpieTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider().background(MagpieTheme.borderSubtle)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "对话保持 (Affinity)"))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(MagpieTheme.textPrimary)
                    Text(String(localized: "同一会话是否固定在同一账号"))
                        .font(.caption2)
                        .foregroundStyle(MagpieTheme.textMuted)
                }
                Spacer()
                Picker("", selection: $affinityDraft) {
                    Text(String(localized: "自动")).tag("")
                    Text(String(localized: "整个会话")).tag("session")
                    Text(String(localized: "仅当前轮")).tag("turn")
                    Text(String(localized: "不保持")).tag("off")
                    Text(String(localized: "严格保持")).tag("strict")
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .tint(MagpieTheme.textSecondary)
            }

            Divider().background(MagpieTheme.borderSubtle)

            Toggle(isOn: $sinkDraft) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "限流后置"))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(MagpieTheme.textPrimary)
                    Text(String(localized: "仍有额度但被限流的账号排到后面"))
                        .font(.caption2)
                        .foregroundStyle(MagpieTheme.textMuted)
                }
            }
            .tint(MagpieTheme.green)
        }
        .magpieCard()
    }

    // MARK: - 规则与分类器
    private var advancedCard: some View {
        DisclosureGroup(isExpanded: $showingAdvanced) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "分类器"))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(MagpieTheme.textPrimary)
                        Text(String(localized: "先由它判断难度，再按规则选成员"))
                            .font(.caption2)
                            .foregroundStyle(MagpieTheme.textMuted)
                    }
                    Spacer()
                    Picker("", selection: $classifierDraft) {
                        Text(String(localized: "无")).tag("")
                        ForEach(viewModel.deciders) { model in
                            Text(model.displayName).tag(model.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .tint(MagpieTheme.accent)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(String(localized: "规则 (JSON 数组)"))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(MagpieTheme.textMuted)
                    TextEditor(text: $rulesDraft)
                        .font(.system(size: 10.5, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 110)
                        .padding(8)
                        .background(MagpieTheme.cardSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Text(String(localized: "每条形如 {\"use\":\"provider/model\",\"intent\":\"a hard task…\"}，另可带 effort 与 compact。留空则不写规则。"))
                        .font(.caption2)
                        .foregroundStyle(MagpieTheme.textMuted)
                }

                if let rulesError {
                    Text(rulesError)
                        .font(.caption)
                        .foregroundStyle(MagpieTheme.red)
                }
            }
            .padding(.top, 10)
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(MagpieTheme.purple)
                Text(String(localized: "规则与分类器"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MagpieTheme.textPrimary)
                Spacer()
                if !classifierDraft.isEmpty || !rulesDraft.isEmpty {
                    MagpieStatusChip(text: String(localized: "已配置"), color: MagpieTheme.purple)
                }
            }
        }
        .padding(14)
        .magpieCard(padding: 0)
    }

    // MARK: - 成员
    private var membersCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(String(localized: "成员（按顺序尝试）"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MagpieTheme.textMuted)
                Text("\(members.count)")
                    .font(.caption2)
                    .foregroundStyle(MagpieTheme.textMuted)
                Spacer()
                Button {
                    showingMemberPicker = true
                } label: {
                    Label(String(localized: "添加模型"), systemImage: "plus.circle.fill")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(MagpieTheme.accent)

                Button {
                    showingManualMember = true
                } label: {
                    Image(systemName: "keyboard")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(MagpieTheme.textSecondary)
            }
            .padding(.horizontal, 4)

            if members.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "square.3.layers.3d.slash")
                        .font(.system(size: 26))
                        .foregroundStyle(MagpieTheme.textMuted.opacity(0.7))
                    Text(String(localized: "还没有成员。添加至少一个模型后，组才能就绪。"))
                        .font(.caption)
                        .foregroundStyle(MagpieTheme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .magpieCard()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(members.enumerated()), id: \.element) { index, member in
                        memberRow(member, index: index)
                        if index < members.count - 1 {
                            Divider().background(MagpieTheme.borderSubtle).padding(.leading, 52)
                        }
                    }
                }
                .magpieCard(padding: 0)

                Text(String(localized: "在组内，模型会按此顺序参与故障转移；Smart / Rotate 等策略会在此基础上权衡。"))
                    .font(.caption2)
                    .foregroundStyle(MagpieTheme.textMuted)
                    .padding(.horizontal, 4)
            }
        }
    }

    private func memberRow(_ member: String, index: Int) -> some View {
        HStack(spacing: 11) {
            Text("\(index + 1)")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(index == 0 ? MagpieTheme.accent : MagpieTheme.textMuted)
                .frame(width: 20, height: 20)
                .background(index == 0 ? MagpieTheme.accentSoft : MagpieTheme.pill)
                .clipShape(Circle())

            let providerID = member.split(separator: "/").first.map(String.init) ?? member
            let info = viewModel.group(id: editing?.id ?? "")?.memberInfo?.first { $0.id == member }
            MagpieIconView(icon: info?.icon ?? providerID, name: info?.name ?? member, size: 28, cornerRadius: 6)

            VStack(alignment: .leading, spacing: 2) {
                Text(info?.displayName ?? member)
                    .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(MagpieTheme.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(member)
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(MagpieTheme.textMuted)
                        .lineLimit(1)
                    if let billing = info?.billing, !billing.isEmpty {
                        MagpieStatusChip(text: billing.uppercased(), color: billing == "plan" ? MagpieTheme.green : MagpieTheme.amber)
                    }
                }
            }

            Spacer(minLength: 4)

            Button {
                moveMember(index, by: -1)
            } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(index == 0 ? MagpieTheme.textMuted.opacity(0.3) : MagpieTheme.textSecondary)
            }
            .buttonStyle(.plain)
            .disabled(index == 0)

            Button {
                moveMember(index, by: 1)
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(index == members.count - 1 ? MagpieTheme.textMuted.opacity(0.3) : MagpieTheme.textSecondary)
            }
            .buttonStyle(.plain)
            .disabled(index == members.count - 1)

            Button {
                members.remove(at: index)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(MagpieTheme.red.opacity(0.85))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - 逻辑
    private var slugifiedID: String {
        let lowered = idDraft.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-.")
        var out = ""
        for scalar in lowered.unicodeScalars {
            if allowed.contains(scalar) { out.unicodeScalars.append(scalar) }
            else if scalar == " " || scalar == "_" || scalar == "/" { out.append("-") }
        }
        while out.contains("--") { out = out.replacingOccurrences(of: "--", with: "-") }
        return out.trimmingCharacters(in: CharacterSet(charactersIn: "-."))
    }

    private func moveMember(_ index: Int, by offset: Int) {
        let target = index + offset
        guard members.indices.contains(index), members.indices.contains(target) else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            members.swapAt(index, target)
        }
        MagpieHaptics.light()
    }

    private func primeIfNeeded() {
        guard !primed else { return }
        primed = true
        guard let editing else {
            nameDraft = ""
            idDraft = ""
            routingDraft = "smart"
            return
        }
        nameDraft = editing.isAuto ? "\(editing.name)" : editing.name
        idDraft = editing.isAuto ? slugifiedCopyID(editing) : editing.id
        routingDraft = editing.routing ?? "smart"
        affinityDraft = editing.affinity ?? ""
        unlistedDraft = editing.unlists ?? false
        sinkDraft = editing.sink ?? false
        members = editing.members ?? []
        classifierDraft = editing.classifier ?? ""
        rulesDraft = editing.rules?.prettyText ?? ""
    }

    private func slugifiedCopyID(_ group: GroupDTO) -> String {
        let base = group.id + "-copy"
        var candidate = base
        var index = 2
        let existing = Set(viewModel.groups.map(\.id))
        while existing.contains(candidate) {
            candidate = "\(base)-\(index)"
            index += 1
        }
        return candidate
    }

    private func save() {
        guard let client = app.client else { return }
        saveError = nil
        rulesError = nil

        var rulesValue: JSONValue?
        let rulesText = rulesDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !rulesText.isEmpty {
            guard let parsed = JSONValue.parse(rulesText) else {
                rulesError = String(localized: "规则不是合法的 JSON。")
                showingAdvanced = true
                return
            }
            if case .array = parsed {
                rulesValue = parsed
            } else {
                rulesError = String(localized: "规则需要是一个 JSON 数组。")
                showingAdvanced = true
                return
            }
        }

        isSaving = true
        let trimmedName = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let classifier = classifierDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let draft = GroupDraft(
            id: slugifiedID,
            name: trimmedName,
            members: members,
            routing: routingDraft,
            affinity: affinityDraft,
            unlists: unlistedDraft,
            sink: sinkDraft,
            keys: editing?.keys,
            accounts: editing?.accounts,
            classifier: classifier.isEmpty ? nil : classifier,
            rules: rulesValue
        )
        Task {
            let ok = await viewModel.save(client: client, draft: draft, from: fromID)
            isSaving = false
            if ok { dismiss() } else { saveError = viewModel.errorMessage ?? String(localized: "保存失败") }
        }
    }
}

// MARK: - 成员选择器
private struct GroupMemberPicker: View {
    let models: [GroupModelRefDTO]
    @Binding var selected: [String]
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var filtered: [GroupModelRefDTO] {
        guard !searchText.isEmpty else { return models }
        let q = searchText.lowercased()
        return models.filter {
            $0.id.lowercased().contains(q)
                || $0.displayName.lowercased().contains(q)
                || ($0.providerName?.lowercased().contains(q) ?? false)
        }
    }

    private var grouped: [(provider: String, items: [GroupModelRefDTO])] {
        let dict = Dictionary(grouping: filtered) { $0.providerName ?? $0.provider ?? "—" }
        return dict.keys.sorted().map { key in
            (key, dict[key]!.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending })
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Text(String(localized: "已选 \(selected.count) 个成员"))
                            .font(.caption)
                            .foregroundStyle(MagpieTheme.textSecondary)
                        Spacer()
                        Button(String(localized: "清空")) { selected.removeAll() }
                            .font(.caption.weight(.semibold))
                    }
                }

                ForEach(grouped.indices, id: \.self) { groupIndex in
                    let group = grouped[groupIndex]
                    Section {
                        ForEach(group.items) { model in
                            Button {
                                toggle(model.id)
                            } label: {
                                HStack(spacing: 10) {
                                    MagpieIconView(icon: model.icon ?? model.provider, name: model.providerName ?? model.provider ?? "model", size: 22, cornerRadius: 5)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(model.displayName)
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundStyle(MagpieTheme.textPrimary)
                                        Text(model.id)
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundStyle(MagpieTheme.textMuted)
                                    }
                                    Spacer()
                                    if selected.contains(model.id) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(MagpieTheme.accent)
                                    } else {
                                        Image(systemName: "circle")
                                            .foregroundStyle(MagpieTheme.textMuted.opacity(0.5))
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text(group.provider)
                    }
                }
            }
            .searchable(text: $searchText, prompt: String(localized: "搜索模型或提供方…"))
            .navigationTitle(String(localized: "选择成员模型"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "完成")) { dismiss() }
                }
            }
        }
    }

    private func toggle(_ id: String) {
        if let index = selected.firstIndex(of: id) {
            selected.remove(at: index)
        } else {
            selected.append(id)
        }
        MagpieHaptics.light()
    }
}
