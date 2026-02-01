import SwiftUI
import UserNotifications

struct FixedCostSettingView: View {
    @EnvironmentObject var dataStore: DataStore
    
    @State private var showAddSheet = false
    @State private var editingTemplate: FixedCostTemplate?
    
    private var expenseTemplates: [FixedCostTemplate] {
        dataStore.fixedCostTemplates.filter { $0.type == .expense }
    }
    
    private var incomeTemplates: [FixedCostTemplate] {
        dataStore.fixedCostTemplates.filter { $0.type == .income }
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
                    Text("・")
                        .foregroundStyle(.secondary)
                    Text("毎月\(template.dayOfMonthDisplay)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
            }
        }
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
                    Picker("種類", selection: $type) {
                        Text("支出").tag(TransactionType.expense)
                        Text("収入").tag(TransactionType.income)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: type) { _, _ in
                        if let first = categories.first {
                            selectedCategoryId = first.id
                        }
                    }
                }
                
                Section {
                    TextField("名前（例：家賃）", text: $name)
                        .frame(minHeight: 44)
                    
                    HStack {
                        Text("金額")
                        Spacer()
                        TextField("0", text: $amountText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
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
                        Text("末日").tag(0)
                    }
                    .frame(minHeight: 44)
                    
                    TextField("メモ（任意）", text: $memo)
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

struct BudgetSettingView: View {
    @EnvironmentObject var dataStore: DataStore
    
    @State private var totalBudgetText = ""
    // UUID (category.id) -> String (amount)
    @State private var categoryBudgets: [UUID: String] = [:]
    
    private var expenseCategories: [Category] {
        dataStore.expenseCategories
    }
    
    var body: some View {
        List {
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
    
    private func loadBudgets() {
        if let total = dataStore.totalBudget() {
            totalBudgetText = String(total.amount)
        }
        
        for budget in dataStore.budgets where budget.categoryId != nil {
            categoryBudgets[budget.categoryId!] = String(budget.amount)
        }
    }
    
    private func saveTotalBudget(_ amountText: String) {
        // デバウンスのため、少し遅延させる
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
        // デバウンスのため、少し遅延させる
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
                .frame(minHeight: 44)
            }
            
            if settings.reminderEnabled {
                Section {
                    DatePicker(
                        "通知時刻",
                        selection: $settings.reminderTime,
                        displayedComponents: .hourAndMinute
                    )
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
