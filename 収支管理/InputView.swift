import SwiftUI

/// 入力タブ用の画面
/// - Note: 既存の本体実装は `TransactionInputView`。TabView から呼び出すための薄いラッパーです。
struct InputView: View {
    var body: some View {
        TransactionInputView()
    }
}

/// 取引の追加/編集画面
struct TransactionInputView: View {
    @EnvironmentObject private var dataStore: DataStore
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    @Environment(\.locale) private var locale
    @Environment(\.calendar) private var calendar
    @Environment(\.colorScheme) private var colorScheme

    let preselectedDate: Date?
    let editingTransaction: Transaction?
    let dismissAfterSave: Bool
    let onClose: (() -> Void)?

    // 入力状態
    @State private var date: Date = Date()
    @State private var type: TransactionType = .expense
    @State private var amountText: String = ""
    
    // カテゴリID（新仕様）
    @State private var categoryId: UUID? = nil
    
    @State private var memo: String = ""
    @State private var isRecurring: Bool = false
    @State private var isSaving: Bool = false

    // UI制御
    @State private var isDatePickerExpanded = false
    
    // シート制御
    @State private var showTransferSheet = false
    @State private var showSplitSheet = false
    @State private var showReceiptScanner = false
    @State private var showCalculator = false

    @State private var showSuccessOverlay = false

    // 予算スナックバー
    @State private var showBudgetSnackbar = false
    @State private var budgetSnackbarInfo: BudgetSnackbarInfo?

    // フォーカス制御
    private enum Field: Hashable { case amount, memo }
    @FocusState private var focusedField: Field?

    // バリデーション
    @State private var showValidationError = false
    @State private var validationMessage = ""

    // よく使うカテゴリ（初期表示時に固定）
    @State private var cachedFrequentCategories: [Category] = []

    init(
        preselectedDate: Date? = nil,
        editingTransaction: Transaction? = nil,
        dismissAfterSave: Bool = false,
        onClose: (() -> Void)? = nil
    ) {
        self.preselectedDate = preselectedDate
        self.editingTransaction = editingTransaction
        self.dismissAfterSave = dismissAfterSave
        self.onClose = onClose
    }

    private var categories: [Category] { dataStore.categories(for: type) }
    // frequentCategoriesは初期化時にキャッシュしたものを使用（選択時の画面ジャンプ防止）
    private var frequentCategories: [Category] { cachedFrequentCategories }
    private var isEditing: Bool { editingTransaction != nil }
    private var isTransfer: Bool { editingTransaction?.type == .transfer }

    private var canSave: Bool {
        let trimmed = amountText
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return false }
        
        // 数式を評価してみる
        if let amount = evaluateExpression(trimmed), amount > 0 {
            return true
        }
        return false
    }

    /// 数式を評価してIntで返す
    private func evaluateExpression(_ text: String) -> Int? {
        // カンマを除去
        let cleaned = text.replacingOccurrences(of: ",", with: "")
        
        // 許可される文字のみかチェック (数字と記号)
        let allowed = CharacterSet(charactersIn: "0123456789+-*/. ")
        if cleaned.unicodeScalars.allSatisfy({ allowed.contains($0) }) == false {
            return nil
        }

        let expression = NSExpression(format: cleaned.replacingOccurrences(of: " ", with: ""))
        if let result = expression.expressionValue(with: nil, context: nil) as? NSNumber {
            return Int(result.doubleValue)
        }
        return nil
    }

    private var dateString: String {
        let f = DateFormatter()
        f.locale = locale
        f.calendar = calendar
        f.dateFormat = "yyyy/MM/dd (E)"
        return f.string(from: date)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    // 1. クイックアクション (新規時のみ)
                    if !isEditing {
                        quickActionRow
                    }

                    // 2. 日付 & 区分
                    VStack(spacing: 12) {
                        // 日付ボタン
                        Button {
                            withAnimation(.spring(response: 0.3)) {
                                isDatePickerExpanded.toggle()
                            }
                            focusedField = nil
                        } label: {
                            HStack {
                                Image(systemName: "calendar")
                                    .foregroundStyle(Color.themeBlue)
                                Text(dateString)
                                    .fontWeight(.semibold)
                                    .monospacedDigit()
                                Spacer()
                                Image(systemName: "chevron.down")
                                    .rotationEffect(isDatePickerExpanded ? .degrees(180) : .zero)
                                    .foregroundStyle(.secondary)
                            }
                            .padding()
                            .background(Color.secondaryBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)

                        // インラインカレンダー
                        if isDatePickerExpanded {
                            DatePicker(
                                "",
                                selection: $date,
                                displayedComponents: .date
                            )
                            .datePickerStyle(.graphical)
                            .padding()
                            .background(Color.secondaryBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .transition(.move(edge: .top).combined(with: .opacity))
                            .onChange(of: date) { _, _ in
                                // 日付選択時にカレンダーを閉じる
                                withAnimation(.spring(response: 0.3)) {
                                    isDatePickerExpanded = false
                                }
                            }
                        }

                        // 区分セグメント
                        Picker("区分", selection: $type) {
                            Text("支出").tag(TransactionType.expense)
                            Text("収入").tag(TransactionType.income)
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: type) { _, newType in
                            normalizeCategoryIfNeeded()
                            // タイプ変更時によく使うカテゴリのキャッシュを更新
                            cachedFrequentCategories = dataStore.frequentlyUsedCategories(for: newType, limit: 5)
                        }
                    }

                    // 3. 金額入力
                    VStack(alignment: .leading, spacing: 8) {
                        Text("金額")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 4)
                        
                        HStack(spacing: 8) {
                            // Calculator button
                            Button {
                                showCalculator = true
                            } label: {
                                Image(systemName: "plus.forwardslash.minus")
                                    .font(.title3)
                                    .foregroundStyle(Color.themeBlue)
                                    .frame(width: 44, height: 44)
                                    .background(Color.secondaryBackground)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                            
                            Spacer()
                            TextField("0", text: $amountText)
                                .font(.system(size: 28, weight: .semibold, design: .rounded))
                                .keyboardType(.numbersAndPunctuation) // 演算子を入力可能に
                                .focused($focusedField, equals: .amount)
                                .multilineTextAlignment(.trailing)
                            Text("円")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                        .background(Color.secondaryBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(focusedField == .amount ? Color.themeBlue : Color.clear, lineWidth: 2)
                        )
                    }

                    // 4. よく使うカテゴリ + カテゴリ選択
                    VStack(alignment: .leading, spacing: 8) {
                        // よく使うカテゴリ（上位5件）
                        if !frequentCategories.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("よく使う")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.leading, 4)

                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(frequentCategories) { cat in
                                            Button {
                                                categoryId = cat.id
                                                HapticManager.shared.selection()
                                            } label: {
                                                HStack(spacing: 4) {
                                                    Circle()
                                                        .fill(cat.color)
                                                        .frame(width: 10, height: 10)
                                                    Text(cat.name)
                                                        .font(.subheadline)
                                                }
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 8)
                                                .background(
                                                    categoryId == cat.id
                                                        ? Color.themeBlue.opacity(0.15)
                                                        : Color.secondaryBackground
                                                )
                                                .foregroundStyle(
                                                    categoryId == cat.id
                                                        ? Color.themeBlue
                                                        : Color.primary
                                                )
                                                .clipShape(Capsule())
                                                .overlay(
                                                    Capsule()
                                                        .stroke(
                                                            categoryId == cat.id
                                                                ? Color.themeBlue
                                                                : Color.clear,
                                                            lineWidth: 1.5
                                                        )
                                                )
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    .padding(.horizontal, 4)
                                }
                            }
                        }

                        // カテゴリ選択（全カテゴリ）
                        Text("カテゴリ")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 4)

                        HierarchicalCategoryPicker(
                            type: type,
                            selectedCategoryId: $categoryId
                        )
                    }

                    // 5. メモ
                    VStack(alignment: .leading, spacing: 8) {
                        Text("メモ")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 4)
                        
                        TextField("メモを入力（任意）", text: $memo)
                            .padding()
                            .background(Color.secondaryBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .focused($focusedField, equals: .memo)
                    }

                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 12)
            }
            .background(Color.primaryBackground) // ダークモード対応背景
            .navigationTitle(isEditing ? (isTransfer ? "振替編集" : "編集") : "入力")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("キャンセル") { close() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "更新" : "保存") {
                        save()
                    }
                    .disabled(!canSave || isSaving)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完了") {
                        focusedField = nil
                    }
                }
            }
            // ★ ハーフモーダル対応（.medium: 半分, .large: 全画面）
            .presentationDetents([.medium, .large])
            // .visibleだとキーボードが出た時に自動で広がる
            .presentationDragIndicator(.visible)
            .onAppear { setupInitialValues() }
            .alert("入力エラー", isPresented: $showValidationError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(validationMessage)
            }
            .sheet(isPresented: $showTransferSheet) {
                TransferInputView {
                    showTransferSheet = false
                    if dismissAfterSave { close() }
                }
            }
            .sheet(isPresented: $showSplitSheet) {
                SplitTransactionView()
            }
            .sheet(isPresented: $showReceiptScanner) {
                ReceiptScannerView()
            }
            .sheet(isPresented: $showCalculator) {
                CalculatorInputView(value: $amountText)
            }
            .overlay {
                if showSuccessOverlay {
                    VStack {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 70))
                            .foregroundStyle(.green)
                            .shadow(radius: 5)
                        Text("保存しました")
                            .font(.headline)
                            .padding(.top, 8)
                    }
                    .padding(40)
                    .background(.ultraThinMaterial)
                    .cornerRadius(20)
                    .transition(.scale.combined(with: .opacity))
                    .zIndex(1)
                }
            }
            .overlay(alignment: .bottom) {
                if showBudgetSnackbar, let info = budgetSnackbarInfo {
                    BudgetSnackbarView(info: info)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.bottom, 20)
                        .zIndex(2)
                }
            }
        }
    }

    // MARK: - Subviews

    private var quickActionRow: some View {
        HStack(spacing: 8) {
            quickActionButton(
                title: "振替",
                icon: "arrow.left.arrow.right",
                color: .orange
            ) { showTransferSheet = true }

            quickActionButton(
                title: "分割",
                icon: "square.split.2x1",
                color: .purple
            ) { showSplitSheet = true }

            quickActionButton(
                title: "レシート",
                icon: "doc.text.viewfinder",
                color: .green
            ) { showReceiptScanner = true }
        }
    }

    private func quickActionButton(title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.footnote)
                    Text(title)
                        .font(.caption2)
                        .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(color.opacity(0.1))
            .foregroundStyle(color)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    // MARK: - Logic

    private func setupInitialValues() {
        if let edit = editingTransaction {
            date = edit.date
            type = edit.type == .transfer ? .expense : edit.type
            amountText = String(edit.amount)
            categoryId = edit.categoryId
            memo = edit.memo
            isRecurring = edit.isRecurring

            // カテゴリIDがnil（未分類等）なら、初期化ロジックを走らせるか？
            // 編集モードなら、nilならnilのままで良い場合もあるが、カテゴリエラーを防ぐなら初期値入れたほうが親切。
            // しかし、意図的に未分類にしているかもしれないので、強制セットは避ける？
            // -> 入力画面では必ずカテゴリを選ぶUIになっているため、空ならデフォルトを入れてあげるのが自然。
            normalizeCategoryIfNeeded()
            // よく使うカテゴリをキャッシュ（編集時のタイプに合わせる）
            cachedFrequentCategories = dataStore.frequentlyUsedCategories(for: type, limit: 5)
            return
        }

        if let d = preselectedDate { date = d }
        normalizeCategoryIfNeeded(forceToFirstIfEmpty: true)
        // よく使うカテゴリをキャッシュ（初期表示時に固定して、選択時の画面ジャンプを防止）
        cachedFrequentCategories = dataStore.frequentlyUsedCategories(for: type, limit: 5)
        focusedField = nil
    }
    
    private func normalizeCategoryIfNeeded(forceToFirstIfEmpty: Bool = false) {
        let validIds = Set(categories.map { $0.id })
        
        // 選択中のIDが無効（削除済み）または空の場合
        if let current = categoryId {
             if !validIds.contains(current) {
                 categoryId = categories.first?.id
             }
        } else {
             if forceToFirstIfEmpty {
                 categoryId = categories.first?.id
             }
        }
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }

        let cleaned = amountText
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let amount = evaluateExpression(cleaned), amount > 0 else {
            validationMessage = "金額を正しく入力してください（例: 100+250）。"
            showValidationError = true
            return
        }

        // カテゴリが未選択ならデフォルトを設定
        if categoryId == nil {
            normalizeCategoryIfNeeded(forceToFirstIfEmpty: true)
        }
        
        // Haptic Feedback
        HapticManager.shared.impact()

        if let old = editingTransaction {
            let updated = Transaction(
                id: old.id,
                date: date,
                type: type,
                amount: amount,
                categoryId: categoryId,
                originalCategoryName: nil, // 編集で保存するならID解決済み
                memo: memo,
                isRecurring: isRecurring,
                templateId: old.templateId,
                createdAt: old.createdAt
            )
            dataStore.updateTransaction(updated)
            // ルール学習 (カテゴリIDがある場合のみ)
            if categoryId != nil {
                ClassificationRulesStore.shared.learn(from: updated)
            }
        } else {
            let tx = Transaction(
                date: date,
                type: type,
                amount: amount,
                categoryId: categoryId,
                originalCategoryName: nil,
                memo: memo,
                isRecurring: false
            )
            dataStore.addTransaction(tx)
            // ルール学習
            if categoryId != nil {
                ClassificationRulesStore.shared.learn(from: tx)
            }

            // 成功アニメーション
            withAnimation(.spring()) {
                showSuccessOverlay = true
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                withAnimation {
                    showSuccessOverlay = false
                }
                // 成功オーバーレイ後に予算スナックバーを表示
                showBudgetSnackbarIfNeeded(for: tx)
            }

            if !dismissAfterSave { clearForm(keepDate: true) }
        }

        if dismissAfterSave { close() }
    }

    private func clearForm(keepDate: Bool = false) {
        if !keepDate { date = preselectedDate ?? Date() }
        type = .expense
        amountText = ""
        memo = ""
        isRecurring = false
        // カテゴリリセット
        normalizeCategoryIfNeeded(forceToFirstIfEmpty: true)
        focusedField = nil
    }

    private func close() {
        focusedField = nil
        onClose?()
        dismiss()
    }

    /// 予算スナックバーの情報を計算して表示
    private func showBudgetSnackbarIfNeeded(for transaction: Transaction) {
        // 支出のみ、かつ予算が設定されている場合に表示
        guard transaction.type == .expense,
              let catId = transaction.categoryId,
              let budget = dataStore.categoryBudget(for: catId) else {
            return
        }

        let spent = dataStore.categoryTotal(categoryId: catId, type: .expense, month: transaction.date)
        let remaining = budget.amount - spent
        let progress = budget.amount > 0 ? min(Double(spent) / Double(budget.amount), 1.0) : 0

        let categoryName = dataStore.categoryName(for: catId)

        budgetSnackbarInfo = BudgetSnackbarInfo(
            categoryName: categoryName,
            budgetAmount: budget.amount,
            spentAmount: spent,
            remainingAmount: remaining,
            progress: progress
        )

        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            showBudgetSnackbar = true
        }

        // 3秒後に自動で非表示
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
            withAnimation(.easeOut(duration: 0.3)) {
                showBudgetSnackbar = false
            }
        }
    }
}

// MARK: - Budget Snackbar Info

struct BudgetSnackbarInfo {
    let categoryName: String
    let budgetAmount: Int
    let spentAmount: Int
    let remainingAmount: Int
    let progress: Double

    var isOverBudget: Bool { remainingAmount < 0 }
    var progressColor: Color {
        if progress >= 1.0 { return .red }
        if progress >= 0.8 { return .orange }
        return .green
    }
}

// MARK: - Budget Snackbar View

struct BudgetSnackbarView: View {
    let info: BudgetSnackbarInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: info.isOverBudget ? "exclamationmark.triangle.fill" : "chart.bar.fill")
                    .foregroundStyle(info.isOverBudget ? .red : .green)

                Text(info.categoryName)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Spacer()

                if info.isOverBudget {
                    Text("予算超過")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.red)
                }
            }

            // プログレスバー
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 8)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(info.progressColor)
                        .frame(width: geo.size.width * CGFloat(min(info.progress, 1.0)), height: 8)
                }
            }
            .frame(height: 8)

            HStack {
                Text("使用: \(info.spentAmount.currencyFormatted)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Text("残り: \(info.remainingAmount.currencyFormatted)")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(info.isOverBudget ? .red : .primary)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.secondaryBackground)
                .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
        )
        .padding(.horizontal, 16)
    }
}
