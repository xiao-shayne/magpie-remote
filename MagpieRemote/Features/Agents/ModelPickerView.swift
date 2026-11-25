import SwiftUI

/// 可搜索的模型/字段选择器（全局复用）。点选项即写入，支持输入列表外的自定义值。
struct ModelPickerView: View {
    let agentID: String
    let fieldKey: String

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = AgentsViewModel()
    @State private var searchText = ""

    private var agent: AgentDTO? { app.state?.agents.first { $0.id == agentID } }
    private var field: FieldDTO? { agent?.fields.first { $0.key == fieldKey } }
    private nonisolated static let effortOrder = ["off", "none", "minimal", "low", "medium", "high", "xhigh", "max"]

    private var isEffortField: Bool {
        guard let field else { return false }
        let key = field.key.lowercased()
        let label = field.label.lowercased()
        return key == "effort" || key.hasSuffix("_effort") || label == "effort" || label == "thinking" || label.contains("effort")
    }

    private var options: [ModelOption] {
        guard let field, let state = app.state else { return [] }
        let raw = state.options(for: field)
        guard isEffortField else { return raw }
        return Self.orderedEffortOptions(raw, currentValue: field.value)
    }

    /// 对齐 upstream `levelOrder` / `effortStops`：推理档按从低到高排列，当前未在列表内的值也插回其对应档位。
    nonisolated static func orderedEffortOptions(_ options: [ModelOption], currentValue: String) -> [ModelOption] {
        var ranked = options.filter { effortOrder.contains($0.value.lowercased()) }
        ranked.sort {
            (effortOrder.firstIndex(of: $0.value.lowercased()) ?? Int.max)
                < (effortOrder.firstIndex(of: $1.value.lowercased()) ?? Int.max)
        }
        var iter = ranked.makeIterator()
        var ordered = options.map { opt -> ModelOption in
            effortOrder.contains(opt.value.lowercased()) ? (iter.next() ?? opt) : opt
        }
        let cur = currentValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cur.isEmpty, !ordered.contains(where: { $0.value == cur }) else { return ordered }
        let held = ModelOption(value: cur, label: cur, note: String(localized: "当前值"))
        if let rank = effortOrder.firstIndex(of: cur.lowercased()) {
            if let idx = ordered.firstIndex(where: {
                guard let r = effortOrder.firstIndex(of: $0.value.lowercased()) else { return false }
                return r > rank
            }) {
                ordered.insert(held, at: idx)
            } else {
                ordered.append(held)
            }
        } else {
            ordered.insert(held, at: 0)
        }
        return ordered
    }

    private var unservedGroups: [UnservedGroupDTO] {
        let all = field?.unserved ?? []
        guard !searchText.isEmpty else { return all }
        let query = searchText.lowercased()
        return all.filter {
            $0.label.lowercased().contains(query)
                || $0.ref.lowercased().contains(query)
                || $0.value.lowercased().contains(query)
                || $0.why.lowercased().contains(query)
        }
    }

    private var filtered: [ModelOption] {
        guard !searchText.isEmpty else { return options }
        let query = searchText.lowercased()
        return options.filter {
            $0.value.lowercased().contains(query)
                || ($0.label?.lowercased().contains(query) ?? false)
        }
    }

    /// 输入了列表中不存在的值时，提供「使用自定义值」入口。
    private var customValue: String? {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let exact = options.contains { $0.value == trimmed }
        return exact ? nil : trimmed
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if let error = viewModel.saveError {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text(error)
                    }
                    .font(.subheadline)
                    .foregroundStyle(MagpieTheme.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .magpieCard()
                }

                if let customValue {
                    Button {
                        select(customValue)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(MagpieTheme.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(String(localized: "使用输入值"))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(MagpieTheme.textPrimary)
                                Text(customValue)
                                    .font(.caption)
                                    .foregroundStyle(MagpieTheme.accent)
                            }
                            Spacer()
                        }
                        .magpieCard()
                    }
                    .buttonStyle(.plain)
                }

                // 选项列表
                VStack(spacing: 0) {
                    ForEach(Array(filtered.enumerated()), id: \.element.id) { index, option in
                        Button {
                            select(option.value)
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(option.displayName)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(option.value == field?.value ? MagpieTheme.accent : MagpieTheme.textPrimary)

                                    if !option.value.isEmpty && option.label != nil {
                                        Text(option.value)
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundStyle(MagpieTheme.textMuted)
                                    }
                                    if let note = option.note {
                                        Text(note)
                                            .font(.caption2)
                                            .foregroundStyle(MagpieTheme.textSecondary)
                                    }
                                }
                                Spacer()
                                if option.value == field?.value {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(MagpieTheme.accent)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(option.value == field?.value ? MagpieTheme.accentSoft.opacity(0.3) : Color.clear)
                        }
                        .buttonStyle(.plain)

                        if index < filtered.count - 1 {
                            Divider()
                                .background(MagpieTheme.borderSubtle)
                        }
                    }
                }
                .magpieCard(padding: 0)

                // 未提供的路由组（upstream field.unserved）
                if !unservedGroups.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(String(localized: "未在此列表中的路由组"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(MagpieTheme.textMuted)
                            .padding(.horizontal, 4)

                        VStack(spacing: 0) {
                            ForEach(Array(unservedGroups.enumerated()), id: \.element.id) { index, item in
                                if item.isPickable {
                                    Button {
                                        selectUnserved(item)
                                    } label: {
                                        unservedRowContent(item)
                                    }
                                    .buttonStyle(.plain)
                                } else {
                                    unservedRowContent(item)
                                        .opacity(0.6)
                                }

                                if index < unservedGroups.count - 1 {
                                    Divider()
                                        .background(MagpieTheme.borderSubtle)
                                }
                            }
                        }
                        .magpieCard(padding: 0)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .magpiePageBackground()
        .searchable(text: $searchText, prompt: String(localized: "搜索模型或配置…"))
        .navigationTitle(field?.label ?? String(localized: "选择模型"))
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if viewModel.isSaving {
                ProgressView(String(localized: "正在应用…"))
                    .padding(20)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    @ViewBuilder
    private func unservedRowContent(_ item: UnservedGroupDTO) -> some View {
        HStack(spacing: 12) {
            if let firstIcon = item.icons?.first, !firstIcon.isEmpty {
                MagpieIconView(icon: firstIcon, name: item.label, size: 22, cornerRadius: 5)
            } else {
                Image(systemName: item.isPickable ? "square.stack.3d.up" : "eye.slash")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(item.isPickable ? MagpieTheme.accent : MagpieTheme.textMuted)
                    .frame(width: 22)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.label)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(item.isPickable ? MagpieTheme.textPrimary : MagpieTheme.textSecondary)
                    if item.isPickable {
                        MagpieStatusChip(text: String(localized: "可重新显示"), color: MagpieTheme.accent)
                    }
                }
                if !item.ref.isEmpty {
                    Text(item.ref)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(MagpieTheme.textMuted)
                }
                if !item.why.isEmpty {
                    Text(item.why)
                        .font(.caption2)
                        .foregroundStyle(MagpieTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }

    private func select(_ value: String) {
        guard let client = app.client else { return }
        Task {
            if await viewModel.pick(client: client, app: app, agentID: agentID, fieldKey: fieldKey, value: value) {
                dismiss()
            }
        }
    }

    private func selectUnserved(_ item: UnservedGroupDTO) {
        guard let client = app.client else { return }
        Task {
            if await viewModel.showAndPick(
                client: client,
                app: app,
                agentID: agentID,
                fieldKey: fieldKey,
                ref: item.ref,
                value: item.value
            ) {
                dismiss()
            }
        }
    }
}
