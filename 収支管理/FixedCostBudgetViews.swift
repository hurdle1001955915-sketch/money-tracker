import SwiftUI
import UserNotifications

struct FixedCostSettingView: View {
    @EnvironmentObject var dataStore: DataStore

    @State private var showAddSheet = false
    @State private var editingTemplate: FixedCostTemplate?

    private var expenseTemplates: [FixedCostTemplate] {
        dataStore.fixedCostTemplates.filter { $0.type == .expense }.sorted { $0.amount > $1.amount }
    }

    private var incomeTemplates: [FixedCostTemplate] {
        dataStore.fixedCostTemplates.filter { $0.type == .income }.sorted { $0.amount > $1.amount }
    }

    /// Current month key in "YYYY-MM" format for comparison with lastProcessedMonth
    private var currentMonthKey: String {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: Date())
        guard let year = comps.year, let month = comps.month else { return "" }
        return "\(year)-\(String(format: "%02d", month))"
    }

    var body: some View {
        List {
            Section("固定費") {
                if expenseTemplates.isEmpty {
                    Text("固定費がありません")
                        .foregroundStyle(.secondary)
                        .frame(minHeight: 44)
                } else {
                    ForEach(expenseTemplates) { template in
                        templateRow(template)
                    }
                }
            }

            Section("定期収入") {
                if incomeTemplates.isEmpty {
                    Text("定期収入がありません")
                        .foregroundStyle(.secondary)
                        .frame(minHeight: 44)
                } else {
                    ForEach(incomeTemplates) { template in
                        templateRow(template)
                    }
                }
            }

            Section {
                Text("固定費は毎月自動で取引として記録されます")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("固定費・定期収入")
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
            FixedCostEditView(template: nil)
        }
        .sheet(item: $editingTemplate) { template in
            FixedCostEditView(template: template)
        }
    }

    private func templateRow(_ template: FixedCostTemplate) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(template.name)
                    .fontWeight(.medium)

                HStack {
                    // カテゴリ名解決
                    Text(dataStore.categoryName(for: template.categoryId))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text("・")
                        .foregroundStyle(.secondary)
                    Text("毎月\(template.dayOfMonthDisplay)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // 最終処理インジケータ
                HStack(spacing: 4) {
                    if template.lastProcessedMonth == currentMonthKey {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption2)
                            .accessibilityLabel("処理済み")
                    }
                    if template.lastProcessedMonth.isEmpty {
                        Text("最終処理: 未処理")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    } else {
                        Text("最終処理: \(formatMonthKey(template.lastProcessedMonth))")
                            .font(.caption2)
                            .foregroundStyle(template.lastProcessedMonth == currentMonthKey ? .green : .secondary)
                    }
                }
            }

            Spacer()

            Text(template.amount.currencyFormatted)
                .foregroundStyle(template.isEnabled ? .primary : .secondary)

            Toggle("", isOn: Binding(
                get: { template.isEnabled },
                set: { newValue in
                    var updated = template
                    updated.isEnabled = newValue
                    dataStore.updateFixedCostTemplate(updated)
                }
            ))
            .labelsHidden()
            .accessibilityLabel("有効化")
        }
        .frame(minHeight: 50)
        .contentShape(Rectangle())
        .onTapGesture {
            editingTemplate = template
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                deleteTemplate(template)
            } label: {
                Label("削除", systemImage: "trash")
                    .accessibilityLabel("削除")
            }
        }
    }

    /// Format "YYYY-MM" to "YYYY年M月"
    private func formatMonthKey(_ monthKey: String) -> String {
        let parts = monthKey.split(separator: "-")
        guard parts.count == 2,
              let year = Int(parts[0]),
              let month = Int(parts[1]) else {
            return monthKey
        }
        return "\(year)年\(month)月"
    }

    private func deleteTemplate(_ template: FixedCostTemplate) {
        withAnimation {
            dataStore.deleteFixedCostTemplate(template)
        }
        // ハプティックフィードバック
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
}

struct FixedCostEditView: View {
    @EnvironmentObject var dataStore: DataStore
    @Environment(\.dismiss) private var dismiss

    let template: FixedCostTemplate?

    @State private var name = ""
    @State private var type: TransactionType = .expense
    @State private var amountText = ""
    @State private var selectedCategoryId: UUID? = nil
    @State private var dayOfMonth = 1
    @State private var memo = ""

    @State private var pendingType: TransactionType?
    @State private var showTypeChangeAlert = false

    private var categories: [Category] {
        dataStore.categories(for: type)
    }

    private var isValid: Bool {
        // カテゴリ必須
        !name.isEmpty && !amountText.isEmpty && Int(amountText) != nil && selectedCategoryId != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("種類", selection: Binding(
                        get: { type },
                        set: { newValue in
                            guard newValue != type else { return }
                            if selectedCategoryId != nil {
                                pendingType = newValue
                                showTypeChangeAlert = true
                            } else {
                                type = newValue
                            }
                        }
                    )) {
                        Text("支出").tag(TransactionType.expense)
                        Text("収入").tag(TransactionType.income)
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    TextField("名前（例：家賃）", text: $name)
                        .textInputAutocapitalization(.never)
                        .frame(minHeight: 44)

                    HStack {
                        Text("金額")
                        Spacer()
                        TextField("0", text: $amountText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .font(.system(size: 24, weight: .semibold, design: .rounded))
                            .frame(width: 120)
                        Text("円")
                            .foregroundStyle(.secondary)
                    }
                    .frame(minHeight: 44)

                    Picker("カテゴリー", selection: $selectedCategoryId) {
                        ForEach(categories) { category in
                            Text(category.name).tag(Optional(category.id))
                        }
                    }
                    .frame(minHeight: 44)

                    Picker("引き落とし日", selection: $dayOfMonth) {
                        ForEach(1...28, id: \.self) { day in
                            Text("\(day)日").tag(day)
                        }
                        Label("末日（月末）", systemImage: "calendar").tag(0)
                    }
                    .frame(minHeight: 44)

                    TextField("メモ（任意）", text: $memo)
                        .textInputAutocapitalization(.never)
                        .frame(minHeight: 44)
                }
            }
            .navigationTitle(template == nil ? "新規追加" : "編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") {
                        save()
                    }
                    .disabled(!isValid)
                }
            }
            .onAppear {
                if let t = template {
                    name = t.name
                    type = t.type
                    amountText = String(t.amount)
                    selectedCategoryId = t.categoryId
                    dayOfMonth = t.dayOfMonth
                    memo = t.memo
                    // IDがない場合は、originalCategoryNameから解決試行（すでにMigration済みのはずだが）
                    if selectedCategoryId == nil, let original = t.originalCategoryName {
                        selectedCategoryId = dataStore.findCategory(name: original, type: t.type)?.id
                    }
                } else {
                    if let first = categories.first {
                        selectedCategoryId = first.id
                    }
                }
            }
            .alert("種類の変更", isPresented: $showTypeChangeAlert) {
                Button("変更する", role: .destructive) {
                    if let newType = pendingType {
                        type = newType
                        let newCategories = dataStore.categories(for: newType)
                        selectedCategoryId = newCategories.first?.id
                    }
                    pendingType = nil
                }
                Button("キャンセル", role: .cancel) {
                    pendingType = nil
                }
            } message: {
                Text("種類を変更するとカテゴリ選択がリセットされます。変更しますか？")
            }
        }
    }

    private func save() {
        guard let amount = Int(amountText) else { return }

        if let existing = template {
            var updated = existing
            updated.name = name
            updated.type = type
            updated.amount = amount
            updated.categoryId = selectedCategoryId
            updated.originalCategoryName = nil // ID指定で更新するため
            updated.dayOfMonth = dayOfMonth
            updated.memo = memo
            dataStore.updateFixedCostTemplate(updated)
        } else {
            let newTemplate = FixedCostTemplate(
                name: name,
                type: type,
                amount: amount,
                categoryId: selectedCategoryId,
                originalCategoryName: nil,
                dayOfMonth: dayOfMonth,
                memo: memo
            )
            dataStore.addFixedCostTemplate(newTemplate)
        }

        // ハプティックフィードバック
        UINotificationFeedbackGenerator().notificationOccurred(.success)

        dismiss()
    }
}

// MARK: - Budget Progress Bar Component

struct BudgetProgressBar: View {
    let spent: Int
    let budget: Int
    var barHeight: CGFloat = 8

    private var ratio: Double {
        guard budget > 0 else { return 0 }
        return Double(spent) / Double(budget)
    }

    private var isOverBudget: Bool {
        ratio > 1.0
    }

    /// 100%までの部分に使う色
    private var baseBarColor: Color {
        if ratio > 1.0 {
            return .red
        } else if ratio >= 0.8 {
            return .orange
        } else {
            return .green
        }
    }

    /// 進捗率テキスト（例: "85%", "112%"）
    private var percentageText: String {
        let pct = Int((ratio * 100).rounded())
        return "\(pct)%"
    }

    /// アクセシビリティ用ラベル
    private var accessibilityText: String {
        let pct = Int((ratio * 100).rounded())
        if isOverBudget {
            return "予算を\(pct - 100)%超過しています"
        } else {
            return "予算の\(pct)%を使用"
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            GeometryReader { geo in
                let totalWidth = geo.size.width

                ZStack(alignment: .leading) {
                    // 背景: 超過時は薄い赤、通常はグレー
                    RoundedRectangle(cornerRadius: barHeight / 2)
                        .fill(isOverBudget ? Color.red.opacity(0.15) : Color(.systemGray5))
                        .frame(height: barHeight)

                    // 100%までの通常バー
                    RoundedRectangle(cornerRadius: barHeight / 2)
                        .fill(baseBarColor)
                        .frame(
                            width: max(0, totalWidth * min(ratio, 1.0)),
                            height: barHeight
                        )

                    // 超過分バー（100%超過時のみ描画）
                    if isOverBudget {
                        let overageRatio = min(ratio - 1.0, 1.0)
                        RoundedRectangle(cornerRadius: barHeight / 2)
                            .fill(Color.red.opacity(0.85))
                            .frame(
                                width: max(0, totalWidth * overageRatio),
                                height: barHeight
                            )
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: barHeight / 2))
            }
            .frame(height: barHeight)

            // 超過時の警告アイコン
            if isOverBudget {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.red)
            }

            // 進捗率テキスト
            Text(percentageText)
                .font(.caption2)
                .foregroundStyle(isOverBudget ? .red : .secondary)
                .monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }
}

// MARK: - Budget Setting View

struct BudgetSettingView: View {
    @EnvironmentObject var dataStore: DataStore

    @State private var totalBudgetText = ""
    // UUID (category.id) -> String (amount)
    @State private var categoryBudgets: [UUID: String] = [:]
    @State private var isCategoryBreakdownExpanded = false

    private var expenseCategories: [Category] {
        dataStore.expenseCategories
    }

    // MARK: - Current Month Spending

    private var currentMonthTransactions: [Transaction] {
        let cal = Calendar.current
        let now = Date()
        guard let startOfMonth = cal.dateInterval(of: .month, for: now)?.start else { return [] }
        return dataStore.transactions.filter { t in
            t.type == .expense && t.date >= startOfMonth && t.date <= now
        }
    }

    private var totalMonthSpending: Int {
        currentMonthTransactions.reduce(0) { $0 + $1.amount }
    }

    private func spendingForCategory(_ categoryId: UUID) -> Int {
        currentMonthTransactions
            .filter { $0.categoryId == categoryId }
            .reduce(0) { $0 + $1.amount }
    }

    private var hasBudgets: Bool {
        dataStore.totalBudget() != nil || dataStore.budgets.contains(where: { $0.categoryId != nil })
    }

    var body: some View {
        List {
            // MARK: - Budget Progress Section
            if hasBudgets {
                budgetProgressSection
            }

            Section("全体予算") {
                HStack {
                    Text("月間予算")
                    Spacer()
                    TextField("未設定", text: $totalBudgetText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 120)
                        .onChange(of: totalBudgetText) { _, newValue in
                            saveTotalBudget(newValue)
                        }
                    Text("円")
                        .foregroundStyle(.secondary)
                }
                .frame(minHeight: 44)
            }

            Section("カテゴリー別予算") {
                ForEach(expenseCategories) { category in
                    HStack {
                        Circle()
                            .fill(category.color)
                            .frame(width: 12, height: 12)

                        Text(category.name)

                        Spacer()

                        TextField("未設定", text: Binding(
                            get: { categoryBudgets[category.id] ?? "" },
                            set: { newValue in
                                categoryBudgets[category.id] = newValue
                                saveCategoryBudget(category.id, newValue)
                            }
                        ))
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)

                        Text("円")
                            .foregroundStyle(.secondary)
                    }
                    .frame(minHeight: 44)
                }
            }

            Section {
                Text("予算は自動的に保存されます")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("予算設定")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadBudgets()
        }
    }

    // MARK: - Budget Progress Section

    @ViewBuilder
    private var budgetProgressSection: some View {
        Section {
            // Total budget progress
            if let totalBudget = dataStore.totalBudget() {
                let remaining = totalBudget.amount - totalMonthSpending
                let usagePercent = totalBudget.amount > 0
                    ? Int(Double(totalMonthSpending) / Double(totalBudget.amount) * 100)
                    : 0

                VStack(alignment: .leading, spacing: 8) {
                    // 改善1: 残額を大フォントで最上部表示 + 改善2: 使用率%併記
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        if remaining >= 0 {
                            Text("残り \(remaining.currencyFormatted)円")
                                .font(.system(size: 34, weight: .bold, design: .rounded))
                                .foregroundStyle(.primary)
                        } else {
                            Text("\(abs(remaining).currencyFormatted)円 超過")
                                .font(.system(size: 34, weight: .bold, design: .rounded))
                                .foregroundStyle(.red)
                        }

                        Text("(\(usagePercent)%)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    // 支出/予算の詳細
                    Text("\(totalMonthSpending.currencyFormatted) / \(totalBudget.amount.currencyFormatted)円")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    BudgetProgressBar(
                        spent: totalMonthSpending,
                        budget: totalBudget.amount,
                        barHeight: 10
                    )
                }
                .padding(.vertical, 4)
            }

            // 改善3: カテゴリ別を折りたたみ（DisclosureGroup）
            let categoryBudgetList = dataStore.budgets.filter { $0.categoryId != nil }
            if !categoryBudgetList.isEmpty {
                DisclosureGroup(
                    isExpanded: $isCategoryBreakdownExpanded
                ) {
                    ForEach(categoryBudgetList) { budget in
                        if let catId = budget.categoryId {
                            let spent = spendingForCategory(catId)
                            let catName = dataStore.categoryName(for: catId)
                            let catColor = dataStore.category(for: catId)?.color ?? .gray

                            HStack(spacing: 10) {
                                Circle()
                                    .fill(catColor)
                                    .frame(width: 8, height: 8)

                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(catName)
                                            .font(.caption)
                                            .fontWeight(.medium)
                                        Spacer()
                                        Text("\(spent.currencyFormatted) / \(budget.amount.currencyFormatted)円")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    BudgetProgressBar(
                                        spent: spent,
                                        budget: budget.amount,
                                        barHeight: 6
                                    )
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                } label: {
                    Text("カテゴリ別の内訳（\(categoryBudgetList.count)件）")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
            }
        } header: {
            Text("今月の予算進捗")
        }
    }

    private func loadBudgets() {
        if let total = dataStore.totalBudget() {
            totalBudgetText = String(total.amount)
        }

        for budget in dataStore.budgets where budget.categoryId != nil {
            categoryBudgets[budget.categoryId!] = String(budget.amount)
        }
    }

    private func saveTotalBudget(_ amountText: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if let amount = Int(amountText), amount > 0 {
                if let existing = dataStore.totalBudget() {
                    var updated = existing
                    updated.amount = amount
                    dataStore.updateBudget(updated)
                } else {
                    let newBudget = Budget(amount: amount)
                    dataStore.addBudget(newBudget)
                }
            } else if amountText.isEmpty, let existing = dataStore.totalBudget() {
                dataStore.deleteBudget(existing)
            }
        }
    }

    private func saveCategoryBudget(_ categoryId: UUID, _ amountText: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let existingBudget = dataStore.categoryBudget(for: categoryId)

            if let amount = Int(amountText), amount > 0 {
                if let existing = existingBudget {
                    var updated = existing
                    updated.amount = amount
                    dataStore.updateBudget(updated)
                } else {
                    let newBudget = Budget(categoryId: categoryId, originalCategoryName: nil, amount: amount)
                    dataStore.addBudget(newBudget)
                }
            } else if amountText.isEmpty, let existing = existingBudget {
                dataStore.deleteBudget(existing)
            }
        }
    }
}

struct ReminderSettingView: View {
    @EnvironmentObject var settings: AppSettings
    @State private var showPermissionAlert = false

    var body: some View {
        List {
            Section {
                Toggle("入れ忘れ防止通知", isOn: Binding(
                    get: { settings.reminderEnabled },
                    set: { newValue in
                        if newValue {
                            checkNotificationPermission()
                        } else {
                            settings.reminderEnabled = false
                            cancelNotification()
                        }
                    }
                ))
                .accessibilityHint("オンにすると毎日指定時刻に入力リマインダーを送信します")
                .frame(minHeight: 44)
            }

            if settings.reminderEnabled {
                Section {
                    DatePicker(
                        "通知時刻",
                        selection: $settings.reminderTime,
                        displayedComponents: .hourAndMinute
                    )
                    .accessibilityLabel("通知時刻")
                    .frame(minHeight: 44)
                    .onChange(of: settings.reminderTime) { _, _ in
                        scheduleNotification()
                    }
                }
            }

            Section {
                Text("毎日設定した時刻に、支出の入力を促す通知が届きます。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel("毎日設定した時刻に支出の入力を促す通知が届きます")
            }
        }
        .navigationTitle("入れ忘れ防止通知")
        .navigationBarTitleDisplayMode(.inline)
        .alert("通知の許可が必要です", isPresented: $showPermissionAlert) {
            Button("設定を開く") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("通知を受け取るには、設定アプリで通知を許可してください。")
        }
    }

    private func checkNotificationPermission() {
        UNUserNotificationCenter.current().getNotificationSettings { notificationSettings in
            DispatchQueue.main.async {
                switch notificationSettings.authorizationStatus {
                case .authorized, .provisional:
                    settings.reminderEnabled = true
                    scheduleNotification()
                case .denied:
                    showPermissionAlert = true
                case .notDetermined:
                    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
                        DispatchQueue.main.async {
                            settings.reminderEnabled = granted
                            if granted {
                                scheduleNotification()
                            } else {
                                showPermissionAlert = true
                            }
                        }
                    }
                @unknown default:
                    break
                }
            }
        }
    }

    private func scheduleNotification() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["daily_reminder"])

        let content = UNMutableNotificationContent()
        content.title = "家計簿"
        content.body = "今日の支出を入力しましょう"
        content.sound = .default

        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: settings.reminderTime)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)

        let request = UNNotificationRequest(identifier: "daily_reminder", content: content, trigger: trigger)
        center.add(request)
    }

    private func cancelNotification() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["daily_reminder"])
    }
}
