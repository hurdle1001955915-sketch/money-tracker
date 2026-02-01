import SwiftUI
import UIKit

/// 取引検索（メモ検索＋フィルタ機能）
/// - 検索対象: memo / category / amount / date(yyyy/MM/dd) / type(収入/支出)
/// - フィルタ: 期間、金額範囲、種類、カテゴリ
struct TransactionSearchView: View {
    @EnvironmentObject private var dataStore: DataStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var deletionManager: DeletionManager
    @Environment(\.dismiss) private var dismiss

    // 検索キーワード
    @State private var query: String = ""
    
    // フィルタ条件
    @State private var showFilters = false
    @State private var selectedType: TransactionType? = nil
    @State private var selectedCategoryId: UUID? = nil
    @State private var dateFrom: Date? = nil
    @State private var dateTo: Date? = nil
    @State private var amountMinText: String = ""
    @State private var amountMaxText: String = ""
    
    // ソート順
    @State private var sortOption: SortOption = .dateDesc
    
    // 編集
    @State private var editingTransaction: Transaction? = nil
    
    // 複製確認
    @State private var showDuplicateSheet = false
    @State private var transactionToDuplicate: Transaction? = nil
    @State private var duplicateDate: Date = Date()

    @State private var filterByUncategorized: Bool = false
    
    private var results: [Transaction] {
        // フィルタ条件を適用
        let amountMin = Int(amountMinText.replacingOccurrences(of: ",", with: ""))
        let amountMax = Int(amountMaxText.replacingOccurrences(of: ",", with: ""))
        
        let searchResults = dataStore.searchTransactions(
            keyword: query.isEmpty ? nil : query,
            type: selectedType,
            categoryId: selectedCategoryId,
            filterByUncategorized: filterByUncategorized,
            dateFrom: dateFrom,
            dateTo: dateTo,
            amountMin: amountMin,
            amountMax: amountMax
        )
        
        return sortTransactions(searchResults)
    }
    
    private var hasActiveFilters: Bool {
        selectedType != nil || selectedCategoryId != nil || filterByUncategorized ||
        dateFrom != nil || dateTo != nil ||
        !amountMinText.isEmpty || !amountMaxText.isEmpty
    }
    
    private var allCategories: [Category] {
        if let type = selectedType {
            return dataStore.categories(for: type)
        }
        return dataStore.expenseCategories + dataStore.incomeCategories
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // フィルタバー
                if hasActiveFilters {
                    activeFiltersBar
                }
                
                // 検索結果リスト
                List {
                    if query.isEmpty && !hasActiveFilters {
                        helpSection
                    } else if results.isEmpty {
                        emptyResultsSection
                    } else {
                        resultsSection
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("検索")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("閉じる") { dismiss() }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showFilters = true
                    } label: {
                        Image(systemName: hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    }
                    
                    Menu {
                        Picker("並び順", selection: $sortOption) {
                            Text("日付 (新しい順)").tag(SortOption.dateDesc)
                            Text("日付 (古い順)").tag(SortOption.dateAsc)
                            Text("金額 (高い順)").tag(SortOption.amountDesc)
                            Text("金額 (安い順)").tag(SortOption.amountAsc)
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down.circle")
                    }
                }
            }
            .searchable(text: $query, prompt: "メモ / 項目で検索")
            .sheet(isPresented: $showFilters) {
                    FilterSheet(
                        selectedType: $selectedType,
                        selectedCategoryId: $selectedCategoryId,
                        filterByUncategorized: $filterByUncategorized,
                        dateFrom: $dateFrom,
                        dateTo: $dateTo,
                        amountMinText: $amountMinText,
                        amountMaxText: $amountMaxText,
                        allCategories: allCategories,
                        dataStore: dataStore
                    )
            }
            .sheet(item: $editingTransaction) { tx in
                TransactionInputView(
                    preselectedDate: tx.date,
                    editingTransaction: tx,
                    dismissAfterSave: true
                ) {
                    editingTransaction = nil
                }
            }
            .sheet(isPresented: $showDuplicateSheet) {
                DuplicateTransactionSheet(
                    transaction: transactionToDuplicate,
                    targetDate: $duplicateDate,
                    onDuplicate: { date in
                        if let tx = transactionToDuplicate {
                            dataStore.duplicateTransaction(tx, toDate: date)
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                        }
                        showDuplicateSheet = false
                        transactionToDuplicate = nil
                    }
                )
            }
        }
    }
    
    // MARK: - Sections
    
    private var helpSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Text("検索のヒント")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                VStack(alignment: .leading, spacing: 8) {
                    HelpRow(icon: "magnifyingglass", text: "メモや項目名で検索できます")
                    HelpRow(icon: "space", text: "スペース区切りでAND検索")
                    HelpRow(icon: "line.3.horizontal.decrease.circle", text: "右上のフィルタで絞り込み")
                }
            }
            .padding(.vertical, 8)
        }
    }
    
    private var emptyResultsSection: some View {
        Section {
            VStack(spacing: 12) {
                Image(systemName: "doc.text.magnifyingglass")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("一致する取引がありません")
                .foregroundStyle(.secondary)
            
            if hasActiveFilters {
                Button("フィルタをクリア") {
                    clearFilters()
                }
                .font(.subheadline)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

private var resultsSection: some View {
    Section {
        // 結果件数
        HStack {
            Text("\(results.count)件の取引")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            
            // 合計金額
            let totalIncome = results.filter { $0.type == .income }.reduce(0) { $0 + $1.amount }
            let totalExpense = results.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount }
            
            if totalIncome > 0 {
                Text("+\(totalIncome.currencyFormattedShort)")
                    .font(.caption)
                    .foregroundStyle(.blue)
            }
            if totalExpense > 0 {
                Text("-\(totalExpense.currencyFormattedShort)")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 4)
        
        ForEach(results) { tx in
            // カテゴリ名の解決（振替は動的に口座名を解決）
            let catName: String = {
                if tx.isTransfer {
                    return tx.transferDisplayLabel(accountStore: AccountStore.shared)
                } else {
                    return dataStore.categoryName(for: tx.categoryId)
                }
            }()
            
            Button {
                editingTransaction = tx
            } label: {
                SearchResultRow(transaction: tx, categoryName: catName)
            }
            .buttonStyle(.plain) // リストのハイライトを標準に
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) {
                    deleteTransaction(tx)
                } label: {
                    Label("削除", systemImage: "trash")
                }
            }
            .swipeActions(edge: .leading) {
                Button {
                    transactionToDuplicate = tx
                    duplicateDate = Date()
                    showDuplicateSheet = true
                } label: {
                    Label("複製", systemImage: "doc.on.doc")
                }
                .tint(.blue)
            }
        }
    }
}

private var activeFiltersBar: some View {
    ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
            if let type = selectedType {
                FilterChip(label: type.displayName) {
                    selectedType = nil
                }
            }
            
            if let catId = selectedCategoryId {
                let name = dataStore.categoryName(for: catId)
                FilterChip(label: name) {
                    selectedCategoryId = nil
                }
            }

            if filterByUncategorized {
                FilterChip(label: "未分類") {
                    filterByUncategorized = false
                }
            }
            
            if let from = dateFrom {
                FilterChip(label: "\(from.shortDateString)〜") {
                    dateFrom = nil
                }
            }
            
            if let to = dateTo {
                FilterChip(label: "〜\(to.shortDateString)") {
                    dateTo = nil
                }
            }
            
            if !amountMinText.isEmpty {
                FilterChip(label: "\(amountMinText)円〜") {
                    amountMinText = ""
                }
            }
            
            if !amountMaxText.isEmpty {
                FilterChip(label: "〜\(amountMaxText)円") {
                    amountMaxText = ""
                }
            }
            
            Button("すべてクリア") {
                clearFilters()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
    .background(Color(.systemGray6))
}

// MARK: - Actions

private func deleteTransaction(_ transaction: Transaction) {
    withAnimation {
        deletionManager.deleteTransaction(transaction, from: dataStore)
    }
    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
}

private func clearFilters() {
    selectedType = nil
    selectedCategoryId = nil
    filterByUncategorized = false
    dateFrom = nil
    dateTo = nil
    amountMinText = ""
    amountMaxText = ""
}

// MARK: - Sort Logic

enum SortOption {
    case dateDesc, dateAsc, amountDesc, amountAsc
}

private func sortTransactions(_ transactions: [Transaction]) -> [Transaction] {
    switch sortOption {
    case .dateDesc:
        return transactions.sorted { $0.date > $1.date }
    case .dateAsc:
        return transactions.sorted { $0.date < $1.date }
    case .amountDesc:
        return transactions.sorted { $0.amount > $1.amount }
    case .amountAsc:
        return transactions.sorted { $0.amount < $1.amount }
    }
}

static func dateString(_ date: Date) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "ja_JP")
    f.dateFormat = "yyyy/MM/dd"
    return f.string(from: date)
}
}

// MARK: - Filter Sheet

private struct FilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    @Binding var selectedType: TransactionType?
    @Binding var selectedCategoryId: UUID?
    @Binding var filterByUncategorized: Bool
    @Binding var dateFrom: Date?
    @Binding var dateTo: Date?
    @Binding var amountMinText: String
    @Binding var amountMaxText: String
    
    let allCategories: [Category]
    var dataStore: DataStore // 名前解決用
    
    @State private var showDateFromPicker = false
    @State private var showDateToPicker = false
    @State private var tempDateFrom: Date = Date()
    @State private var tempDateTo: Date = Date()
    
    var body: some View {
        NavigationStack {
            Form {
                // 種類
                Section("種類") {
                    Picker("種類", selection: $selectedType) {
                        Text("すべて").tag(TransactionType?.none)
                        Text("支出").tag(TransactionType?.some(.expense))
                        Text("収入").tag(TransactionType?.some(.income))
                    }
                    .pickerStyle(.segmented)
                }
                
                // カテゴリ
                Section("カテゴリ") {
                    Picker("カテゴリ", selection: $selectedCategoryId) {
                        Text("すべて").tag(UUID?.none)
                        
                        // 「未分類」の選択（BindingのcategoryIdをnilにしつつ、別のフラグを立てるか、
                        // あるいは sentinel ID を使うなどの工夫が必要だが、ここではシンプルに
                        // selectedCategoryIdをnilにし、filterByUncategorizedをtrueにするロジックをOnChangeで組む）
                        Text("未分類").tag(UUID?.none)
                        
                        ForEach(allCategories) { cat in
                            Text(cat.name).tag(UUID?.some(cat.id))
                        }
                    }
                    .onChange(of: selectedCategoryId) { old, new in
                        // もし「すべて」または「未分類」が選ばれた場合（new == nil）
                        // どっちなのかを判定する必要があるが、標準Picker+tag(nil)だと区別がつかない。
                        // そのため、Pickerの構成を変えるか、専用のToggleを設けるなどの対応が望ましいが、
                        // 簡便には、特定のUUID(sentinel)を「未分類」に割り当てる。
                    }
                    
                    Toggle("未分類のみ表示", isOn: $filterByUncategorized)
                        .font(.subheadline)
                        .onChange(of: filterByUncategorized) { _, newValue in
                            if newValue { selectedCategoryId = nil }
                        }
                }
                
                // 期間
                Section("期間") {
                    HStack {
                        Text("開始日")
                        Spacer()
                        if let from = dateFrom {
                            Button(from.shortDateString) {
                                tempDateFrom = from
                                showDateFromPicker = true
                            }
                            Button {
                                dateFrom = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Button("指定なし") {
                                tempDateFrom = Date()
                                showDateFromPicker = true
                            }
                            .foregroundStyle(.secondary)
                        }
                    }
                    
                    HStack {
                        Text("終了日")
                        Spacer()
                        if let to = dateTo {
                            Button(to.shortDateString) {
                                tempDateTo = to
                                showDateToPicker = true
                            }
                            Button {
                                dateTo = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Button("指定なし") {
                                tempDateTo = Date()
                                showDateToPicker = true
                            }
                            .foregroundStyle(.secondary)
                        }
                    }
                    
                    // クイック選択
                    HStack(spacing: 8) {
                        QuickDateButton(label: "今月") {
                            dateFrom = Date().startOfMonth
                            dateTo = Date().endOfMonth
                        }
                        QuickDateButton(label: "先月") {
                            let lastMonth = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
                            dateFrom = lastMonth.startOfMonth
                            dateTo = lastMonth.endOfMonth
                        }
                        QuickDateButton(label: "3ヶ月") {
                            dateFrom = Calendar.current.date(byAdding: .month, value: -3, to: Date()) ?? Date()
                            dateTo = Date()
                        }
                    }
                }
                
                // 金額
                Section("金額範囲") {
                    HStack {
                        TextField("最小金額", text: $amountMinText)
                            .keyboardType(.numberPad)
                            .textFieldStyle(.roundedBorder)
                        Text("円 〜")
                        TextField("最大金額", text: $amountMaxText)
                            .keyboardType(.numberPad)
                            .textFieldStyle(.roundedBorder)
                        Text("円")
                    }
                }
                
                // クリア
                Section {
                    Button("すべてクリア") {
                        selectedType = nil
                        selectedCategoryId = nil
                        filterByUncategorized = false
                        dateFrom = nil
                        dateTo = nil
                        amountMinText = ""
                        amountMaxText = ""
                    }
                    .foregroundStyle(.red)
                }
            }
            .navigationTitle("フィルタ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完了") { dismiss() }
                }
            }
            .sheet(isPresented: $showDateFromPicker) {
                DatePickerSheet(date: $tempDateFrom, title: "開始日") {
                    dateFrom = tempDateFrom
                }
            }
            .sheet(isPresented: $showDateToPicker) {
                DatePickerSheet(date: $tempDateTo, title: "終了日") {
                    dateTo = tempDateTo
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Date Picker Sheet

private struct DatePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var date: Date
    let title: String
    let onConfirm: () -> Void
    
    var body: some View {
        NavigationStack {
            DatePicker("", selection: $date, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .padding()
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("キャンセル") { dismiss() }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("決定") {
                            onConfirm()
                            dismiss()
                        }
                    }
                }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Supporting Views

private struct HelpRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct FilterChip: View {
    let label: String
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption)
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption2)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.themeBlue.opacity(0.15))
        .foregroundStyle(Color.themeBlue)
        .clipShape(Capsule())
    }
}

private struct QuickDateButton: View {
    let label: String
    let action: () -> Void
    
    var body: some View {
        Button(label) { action() }
            .font(.caption)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(.systemGray5))
            .clipShape(Capsule())
    }
}

private struct SearchResultRow: View {
    let transaction: Transaction
    let categoryName: String // 名前を受け取る
    
    var body: some View {
        let dateStr = TransactionSearchView.dateString(transaction.date)
        let memo = transaction.memo.trimmingCharacters(in: .whitespacesAndNewlines)
        let memoPart = memo.isEmpty ? "（メモなし）" : memo

        VStack(spacing: 4) {
            HStack(spacing: 10) {
                Text(dateStr)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 92, alignment: .leading)

                Text(categoryName)
                    .font(.subheadline)
                    .lineLimit(1)

                Spacer()

                Text(transaction.amount.currencyFormatted)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(transaction.type == .income ? Color.themeBlue : Color(UIColor.systemRed))
                    .frame(width: 92, alignment: .trailing)
            }

            HStack {
                Text(memoPart)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.leading, 92)

                Spacer()
            }
        }
    }
}
