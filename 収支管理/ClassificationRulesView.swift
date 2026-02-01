import SwiftUI

// MARK: - Classification Rules View

struct ClassificationRulesView: View {
    @StateObject private var store = ClassificationRulesStore.shared
    @EnvironmentObject var dataStore: DataStore

    @State private var showAddSheet = false
    @State private var editingRule: ClassificationRule?
    @State private var showResetAlert = false

    var body: some View {
        List {
            Section {
                Text("メモや店舗名に含まれるキーワードから、自動でカテゴリを割り当てます。CSVインポート時や手動入力時に適用されます。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // 支出ルール
            Section("支出ルール") {
                let expenseRules = store.rules.filter { $0.transactionType == .expense }
                if expenseRules.isEmpty {
                    Text("ルールがありません")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(expenseRules) { rule in
                        RuleRow(rule: rule, dataStore: dataStore) {
                            editingRule = rule
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                store.deleteRule(rule)
                            } label: {
                                Label("削除", systemImage: "trash")
                            }
                        }
                    }
                }
            }

            // 収入ルール
            Section("収入ルール") {
                let incomeRules = store.rules.filter { $0.transactionType == .income }
                if incomeRules.isEmpty {
                    Text("ルールがありません")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(incomeRules) { rule in
                        RuleRow(rule: rule, dataStore: dataStore) {
                            editingRule = rule
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                store.deleteRule(rule)
                            } label: {
                                Label("削除", systemImage: "trash")
                            }
                        }
                    }
                }
            }

            // リセット
            Section {
                Button(role: .destructive) {
                    showResetAlert = true
                } label: {
                    HStack {
                        Spacer()
                        Text("すべてのルールを削除")
                        Spacer()
                    }
                }
            }
        }
        .navigationTitle("自動分類ルール")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            RuleEditView(rule: nil)
                .environmentObject(dataStore)
        }
        .sheet(item: $editingRule) { rule in
            RuleEditView(rule: rule)
                .environmentObject(dataStore)
        }
        .alert("すべてのルールを削除", isPresented: $showResetAlert) {
            Button("キャンセル", role: .cancel) {}
            Button("削除", role: .destructive) {
                store.clearAllRules()
            }
        } message: {
            Text("すべてのルールを削除します。この操作は取り消せません。")
        }
    }
}

// MARK: - Rule Row

private struct RuleRow: View {
    let rule: ClassificationRule
    let dataStore: DataStore
    let onTap: () -> Void

    private var categoryName: String {
        if let id = rule.targetCategoryId {
            return dataStore.categoryName(for: id)
        }
        return rule.targetCategoryName ?? "未設定"
    }

    var body: some View {
        Button(action: onTap) {
            HStack {
                // 有効/無効インジケータ
                Circle()
                    .fill(rule.isEnabled ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text("「\(rule.keyword)」")
                            .fontWeight(.medium)
                        Text(rule.matchType.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 4) {
                        Image(systemName: "arrow.right")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(categoryName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Rule Edit View

struct RuleEditView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store = ClassificationRulesStore.shared
    @EnvironmentObject var dataStore: DataStore

    let rule: ClassificationRule?

    @State private var keyword = ""
    @State private var matchType: ClassificationRule.MatchType = .contains
    @State private var transactionType: TransactionType = .expense
    @State private var selectedCategoryId: UUID?
    @State private var isEnabled = true
    @State private var priority = 5

    private var isEditing: Bool { rule != nil }

    private var categories: [Category] {
        dataStore.categories(for: transactionType)
    }

    private var isValid: Bool {
        !keyword.trimmingCharacters(in: .whitespaces).isEmpty && selectedCategoryId != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("キーワード") {
                    TextField("例: コンビニ、スタバ", text: $keyword)

                    Picker("マッチ方法", selection: $matchType) {
                        ForEach(ClassificationRule.MatchType.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                }

                Section("分類先") {
                    Picker("種類", selection: $transactionType) {
                        Text("支出").tag(TransactionType.expense)
                        Text("収入").tag(TransactionType.income)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: transactionType) { _, _ in
                        // カテゴリをリセット
                        if let first = categories.first {
                            selectedCategoryId = first.id
                        } else {
                            selectedCategoryId = nil
                        }
                    }

                    Picker("カテゴリ", selection: $selectedCategoryId) {
                        Text("選択してください").tag(UUID?.none)
                        ForEach(categories) { category in
                            Text(category.name).tag(UUID?.some(category.id))
                        }
                    }
                }

                Section("オプション") {
                    Toggle("有効", isOn: $isEnabled)

                    Stepper("優先度: \(priority)", value: $priority, in: 1...10)

                    Text("優先度が高いルールが先に適用されます")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // テスト
                Section("テスト") {
                    TestRuleView(
                        keyword: keyword,
                        matchType: matchType,
                        targetCategoryId: selectedCategoryId,
                        dataStore: dataStore
                    )
                }
            }
            .navigationTitle(isEditing ? "ルール編集" : "新規ルール")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") { save() }
                        .disabled(!isValid)
                }
            }
            .onAppear {
                if let r = rule {
                    keyword = r.keyword
                    matchType = r.matchType
                    transactionType = r.transactionType
                    selectedCategoryId = r.targetCategoryId
                    isEnabled = r.isEnabled
                    priority = r.priority
                } else {
                    if let first = categories.first {
                        selectedCategoryId = first.id
                    }
                }
            }
        }
    }

    private func save() {
        guard let catId = selectedCategoryId else { return }

        let newRule = ClassificationRule(
            id: rule?.id ?? UUID(),
            keyword: keyword.trimmingCharacters(in: .whitespaces),
            matchType: matchType,
            targetCategoryId: catId,
            transactionType: transactionType,
            isEnabled: isEnabled,
            priority: priority,
            createdAt: rule?.createdAt ?? Date()
        )

        if isEditing {
            store.updateRule(newRule)
        } else {
            store.addRule(newRule)
        }

        dismiss()
    }
}

// MARK: - Test Rule View

private struct TestRuleView: View {
    let keyword: String
    let matchType: ClassificationRule.MatchType
    let targetCategoryId: UUID?
    let dataStore: DataStore

    @State private var testInput = ""

    private var testRule: ClassificationRule {
        ClassificationRule(
            keyword: keyword,
            matchType: matchType,
            targetCategoryId: targetCategoryId
        )
    }

    private var isMatch: Bool {
        testRule.matches(testInput)
    }

    private var categoryName: String {
        dataStore.categoryName(for: targetCategoryId)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("テスト文字列を入力", text: $testInput)

            if !testInput.isEmpty {
                HStack {
                    Image(systemName: isMatch ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(isMatch ? .green : .red)

                    Text(isMatch ? "マッチします → \(categoryName)" : "マッチしません")
                        .font(.caption)
                        .foregroundStyle(isMatch ? .green : .secondary)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        ClassificationRulesView()
            .environmentObject(DataStore.shared)
    }
}
