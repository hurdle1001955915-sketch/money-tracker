import Foundation
import Combine

#if canImport(SwiftData)
import SwiftData
#endif

// MARK: - CSV Export Types

/// CSVエクスポートの列定義
enum CSVExportColumn: String, CaseIterable, Identifiable, Codable {
    // 基本列（必須・順序固定、OFF不可）
    case date = "日付"
    case type = "種類"
    case amount = "金額"
    case category = "カテゴリ"
    case memo = "メモ"

    // 拡張列（選択可能）
    case transactionId = "取引ID"
    case categoryId = "カテゴリID"
    case accountName = "支払元口座"
    case accountId = "支払元口座ID"
    case toAccountName = "振替先口座"
    case toAccountId = "振替先口座ID"
    case transferId = "振替ペアID"
    case classificationSource = "分類元"
    case classificationRuleId = "分類ルールID"
    case classificationConfidence = "分類信頼度"
    case classificationReason = "分類理由"
    case suggestedCategoryId = "自動提案カテゴリID"
    case suggestedCategoryName = "自動提案カテゴリ名"
    case createdAt = "作成日時"
    case source = "インポート元"
    case sourceId = "インポート元ID"
    case importId = "インポートバッチID"
    case sourceHash = "ソースハッシュ"
    case parentId = "親取引ID"
    case isSplit = "分割フラグ"
    case isRecurring = "定期フラグ"
    case templateId = "テンプレートID"

    var id: String { rawValue }

    /// 必須列かどうか（OFF不可）
    var isRequired: Bool {
        switch self {
        case .date, .type, .amount, .category, .memo:
            return true
        default:
            return false
        }
    }

    /// 基本列（先頭5列）
    static var basicColumns: [CSVExportColumn] {
        [.date, .type, .amount, .category, .memo]
    }

    /// 拡張列
    static var extendedColumns: [CSVExportColumn] {
        allCases.filter { !$0.isRequired }
    }

    /// デフォルト（全列）
    static var defaultSet: Set<CSVExportColumn> {
        Set(allCases)
    }

    /// 最小セット（基本列のみ）
    static var minimalSet: Set<CSVExportColumn> {
        Set(basicColumns)
    }
}

/// 改行コード
enum CSVLineEnding: String, Codable, CaseIterable {
    case crlf = "CRLF"  // Windows互換
    case lf = "LF"      // Unix/Mac

    var string: String {
        switch self {
        case .crlf: return "\r\n"
        case .lf: return "\n"
        }
    }

    var displayName: String {
        switch self {
        case .crlf: return "CRLF (Windows)"
        case .lf: return "LF (Mac/Unix)"
        }
    }
}

/// CSVエクスポートオプション
struct CSVExportOptions: Codable {
    /// 出力する列のセット
    var columns: Set<CSVExportColumn>

    /// BOM付きUTF-8（Excel互換）
    var includeBOM: Bool

    /// 改行コード
    var lineEnding: CSVLineEnding

    /// 日付フォーマット
    var dateFormat: String

    init(
        columns: Set<CSVExportColumn> = CSVExportColumn.defaultSet,
        includeBOM: Bool = true,
        lineEnding: CSVLineEnding = .crlf,
        dateFormat: String = "yyyy/MM/dd"
    ) {
        self.columns = columns
        self.includeBOM = includeBOM
        self.lineEnding = lineEnding
        self.dateFormat = dateFormat
    }

    /// 出力列を順序付きで取得（基本列を先頭に固定）
    var orderedColumns: [CSVExportColumn] {
        var result = CSVExportColumn.basicColumns
        for col in CSVExportColumn.extendedColumns {
            if columns.contains(col) {
                result.append(col)
            }
        }
        return result
    }

    /// 従来互換の最小セット
    static var minimal: CSVExportOptions {
        CSVExportOptions(
            columns: CSVExportColumn.minimalSet,
            includeBOM: false,
            lineEnding: .lf,
            dateFormat: "yyyy/MM/dd"
        )
    }

    /// 全列出力（デフォルト推奨）
    static var full: CSVExportOptions {
        CSVExportOptions(
            columns: CSVExportColumn.defaultSet,
            includeBOM: true,
            lineEnding: .crlf,
            dateFormat: "yyyy/MM/dd"
        )
    }

    // MARK: - UserDefaults保存

    private static let storageKey = "csv_export_options_v1"

    static func load() -> CSVExportOptions {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let options = try? JSONDecoder().decode(CSVExportOptions.self, from: data) else {
            return .full
        }
        return options
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: CSVExportOptions.storageKey)
        }
    }
}

@MainActor
final class DataStore: ObservableObject {
    static let shared = DataStore()

    // SwiftData ModelContext - will be injected from App
    private var modelContext: ModelContext?

    // Stored data (memory cache, loaded from SwiftData)
    @Published private(set) var transactions: [Transaction] = []
    @Published private(set) var categoryGroups: [CategoryGroup] = []
    @Published private(set) var categoryItems: [CategoryItem] = []
    @Published private(set) var fixedCostTemplates: [FixedCostTemplate] = []
    @Published private(set) var budgets: [Budget] = []

    // 互換性維持のためのフラットリスト
    var expenseCategories: [Category] {
        categoryItems.filter { $0.type == .expense || $0.type == .transfer }.sorted { $0.order < $1.order }.map { $0.toCategory() }
    }
    var incomeCategories: [Category] {
        categoryItems.filter { $0.type == .income }.sorted { $0.order < $1.order }.map { $0.toCategory() }
    }

    private init() {
        // 初期化時にはまだModelContextがないので、ロードはsetModelContext後に行う
    }

    // MARK: - ModelContext Injection

    /// ModelContextを注入してSwiftDataからデータをロード
    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
        loadAllFromSwiftData()
        ensureDefaultCategoriesIfNeeded()
        performCategoryIdMigration()
    }
    
    // MARK: - Category ID Migration (in-memory, saved to SwiftData)

    private func performCategoryIdMigration() {
        migrateTransactionCategoryIds()
        migrateRuleCategoryIds()
        migrateFixedCostCategoryIds()
        migrateBudgetCategoryIds()
    }

    /// トランザクションのカテゴリID移行
    private func migrateTransactionCategoryIds() {
        var changed = false
        for i in transactions.indices {
            if transactions[i].categoryId == nil, let originalName = transactions[i].originalCategoryName {
                if let cat = findCategory(name: originalName, type: transactions[i].type) {
                    transactions[i].categoryId = cat.id
                    transactions[i].originalCategoryName = nil
                    changed = true
                }
            }
        }
        if changed {
            saveAllTransactionsToSwiftData()
            Diagnostics.shared.log("Migrated transactions to ID-based categories", category: .migration)
        }
    }

    /// ルールのカテゴリID移行
    private func migrateRuleCategoryIds() {
        let allCategories = expenseCategories + incomeCategories

        // v2マイグレーション: キーワードベースの推測を優先するため、一度だけ強制再マイグレーション
        let migrationKey = "rule_migration_v2_completed"
        let needsForceRemigrate = !UserDefaults.standard.bool(forKey: migrationKey)

        ClassificationRulesStore.shared.migrateRules(with: allCategories, forceRemigrate: needsForceRemigrate)

        if needsForceRemigrate {
            UserDefaults.standard.set(true, forKey: migrationKey)
            print("[DataStore] Rule migration v2 completed (force remigration)")
        }
    }

    /// 固定費テンプレートのカテゴリID移行
    private func migrateFixedCostCategoryIds() {
        var changed = false
        for i in fixedCostTemplates.indices {
            if fixedCostTemplates[i].categoryId == nil, let originalName = fixedCostTemplates[i].originalCategoryName {
                if let cat = findCategory(name: originalName, type: fixedCostTemplates[i].type) {
                    fixedCostTemplates[i].categoryId = cat.id
                    fixedCostTemplates[i].originalCategoryName = nil
                    changed = true
                }
            }
        }
        if changed {
            saveAllFixedCostsToSwiftData()
            Diagnostics.shared.log("Migrated fixed costs to ID-based categories", category: .migration)
        }
    }

    /// 予算のカテゴリID移行
    private func migrateBudgetCategoryIds() {
        var changed = false
        for i in budgets.indices {
            if budgets[i].categoryId == nil, let originalName = budgets[i].originalCategoryName {
                if let cat = expenseCategories.first(where: { $0.name == originalName }) {
                    budgets[i].categoryId = cat.id
                    budgets[i].originalCategoryName = nil
                    changed = true
                }
            }
        }
        if changed {
            saveAllBudgetsToSwiftData()
            Diagnostics.shared.log("Migrated budgets to ID-based categories", category: .migration)
        }
    }

    // MARK: - Categories Helpers
    
    func category(for id: UUID?) -> Category? {
        guard let id = id else { return nil }
        return categoryItems.first(where: { $0.id == id })?.toCategory()
    }
    
    func categoryName(for id: UUID?) -> String {
        guard let id = id else { return "未分類" }
        return categoryItems.first(where: { $0.id == id })?.name ?? "不明なカテゴリ"
    }
    
    func findCategory(name: String, type: TransactionType) -> Category? {
        let normalizedInput = TextNormalizer.normalize(name)
        return categoryItems.first(where: { 
            $0.type == type && TextNormalizer.normalize($0.name) == normalizedInput 
        })?.toCategory()
    }

    func categories(for type: TransactionType) -> [Category] {
        return categoryItems.filter { $0.type == type }.sorted { $0.order < $1.order }.map { $0.toCategory() }
    }

    /// よく使うカテゴリを取得（直近の取引から上位N件）
    func frequentlyUsedCategories(for type: TransactionType, limit: Int = 5) -> [Category] {
        // 直近90日間の取引からカテゴリ使用頻度を集計
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? Date()

        let recentTransactions = transactions.filter {
            $0.type == type &&
            $0.categoryId != nil &&
            !$0.isDeleted &&
            $0.date >= cutoffDate
        }

        // カテゴリIDごとの使用回数をカウント
        var categoryCount: [UUID: Int] = [:]
        for tx in recentTransactions {
            if let catId = tx.categoryId {
                categoryCount[catId, default: 0] += 1
            }
        }

        // 使用回数の多い順にソートして上位N件のカテゴリを取得
        let topCategoryIds = categoryCount
            .sorted { $0.value > $1.value }
            .prefix(limit)
            .map { $0.key }

        // カテゴリIDからCategoryオブジェクトを取得（順序を保持）
        return topCategoryIds.compactMap { id in
            categoryItems.first(where: { $0.id == id })?.toCategory()
        }
    }

    // MARK: - Hierarchical Category Helpers
    
    func groups(for type: TransactionType) -> [CategoryGroup] {
        categoryGroups.filter { $0.type == type }.sorted { $0.order < $1.order }
    }
    
    func items(for groupId: UUID) -> [CategoryItem] {
        categoryItems.filter { $0.groupId == groupId }.sorted { $0.order < $1.order }
    }

    func addCategory(_ category: Category) {
        // CategoryをCategoryItemに変換して追加
        // デフォルトグループを探す、なければ作成
        let groupId = findOrCreateDefaultGroup(for: category.type)
        let newItem = CategoryItem(
            id: category.id,
            name: category.name,
            groupId: groupId,
            type: category.type,
            order: categoryItems.filter { $0.type == category.type }.count,
            colorHex: category.colorHex
        )
        categoryItems.append(newItem)
        saveCategoryItemToSwiftData(newItem)
    }

    func updateCategory(_ category: Category) {
        if let idx = categoryItems.firstIndex(where: { $0.id == category.id }) {
            categoryItems[idx].name = category.name
            categoryItems[idx].colorHex = category.colorHex
            saveCategoryItemToSwiftData(categoryItems[idx])
        }
    }

    func deleteCategory(_ category: Category) {
        // 1. 削除対象カテゴリを使用している取引を「その他」に移動
        let targetOtherId = findOrCreateOtherCategory(for: category.type)
        for i in transactions.indices {
            if transactions[i].categoryId == category.id {
                transactions[i].categoryId = targetOtherId
                updateTransactionInSwiftData(transactions[i])
            }
        }
        
        // 2. カテゴリを削除
        categoryItems.removeAll { $0.id == category.id }
        deleteCategoryItemFromSwiftData(category.id)
    }
    
    private func findOrCreateOtherCategory(for type: TransactionType) -> UUID {
        // 既存の「その他」カテゴリを探す
        if let other = categoryItems.first(where: { $0.type == type && $0.name == "その他" }) {
            return other.id
        }
        // なければ作成
        let groupId = findOrCreateDefaultGroup(for: type)
        let newItem = CategoryItem(
            name: "その他",
            groupId: groupId,
            type: type,
            order: 999,
            colorHex: "#9E9E9E"
        )
        categoryItems.append(newItem)
        saveCategoryItemToSwiftData(newItem)
        return newItem.id
    }

    private func findOrCreateDefaultGroup(for type: TransactionType) -> UUID {
        // 「その他」または「未分類」グループを探す、なければ最初のグループを返す
        if let group = categoryGroups.first(where: { $0.type == type && ($0.name == "その他" || $0.name == "未分類") }) {
            return group.id
        }
        if let group = categoryGroups.first(where: { $0.type == type }) {
            return group.id
        }
        // グループがない場合は作成
        let newGroup = CategoryGroup(name: "未分類", type: type, order: 999)
        categoryGroups.append(newGroup)
        saveCategoryGroupToSwiftData(newGroup)
        return newGroup.id
    }

    func reorderCategories(type: TransactionType, from: IndexSet, to: Int) {
        // ... (Implement for categoryItems if needed, but for now flat reorder is fine)
        // This method might need a more complex implementation for hierarchical reordering
    }

    private func moveElements<T>(in array: inout [T], fromOffsets: IndexSet, toOffset: Int) {
        guard !fromOffsets.isEmpty else { return }
        let moving = fromOffsets.sorted().map { array[$0] }
        for i in fromOffsets.sorted(by: >) { array.remove(at: i) }
        var insertIndex = toOffset
        let adjustment = fromOffsets.filter { $0 < toOffset }.count
        insertIndex -= adjustment
        array.insert(contentsOf: moving, at: max(0, min(insertIndex, array.count)))
    }

    // MARK: - Transactions
    func addTransaction(_ tx: Transaction) {
        transactions.append(tx)
        insertTransactionToSwiftData(tx)
        updateWidget()
        // iCloud同期（Feature Flagで無効化可能）
        if AppFeatureFlags.cloudSyncEnabled {
            Task {
                try? await CloudKitSyncManager.shared.uploadTransaction(tx)
            }
        }
    }

    func updateTransaction(_ tx: Transaction) {
        if let idx = transactions.firstIndex(where: { $0.id == tx.id }) {
            let oldTx = transactions[idx]
            transactions[idx] = tx
            updateTransactionInSwiftData(tx, oldTx: oldTx)
            updateWidget()
            // iCloud同期（Feature Flagで無効化可能）
            if AppFeatureFlags.cloudSyncEnabled {
                Task {
                    try? await CloudKitSyncManager.shared.uploadTransaction(tx)
                }
            }
        } else {
            addTransaction(tx)
        }
    }

    func deleteTransaction(_ tx: Transaction) {
        transactions.removeAll { $0.id == tx.id }
        deleteTransactionFromSwiftData(tx.id, originalTx: tx)
        updateWidget()
        // iCloud同期（Feature Flagで無効化可能）
        if AppFeatureFlags.cloudSyncEnabled {
            Task {
                try? await CloudKitSyncManager.shared.deleteTransaction(tx)
            }
        }
    }

    /// 複数取引を一括削除（インポート取り消し等）
    func deleteTransactions(ids: [UUID]) {
        guard !ids.isEmpty else { return }
        let set = Set(ids)
        let originalTxs = transactions.filter { set.contains($0.id) }
        transactions.removeAll { set.contains($0.id) }
        deleteTransactionsFromSwiftData(ids: ids, originalTransactions: originalTxs)
        updateWidget()
        // iCloud同期（Feature Flagで無効化可能）
        if AppFeatureFlags.cloudSyncEnabled {
            Task {
                try? await CloudKitSyncManager.shared.deleteTransactions(ids: ids)
            }
        }
    }

    // MARK: - Transfer (振替) ペア作成 (Phase3-1)

    /// 振替ペアを作成して保存
    /// - Parameters:
    ///   - date: 振替日
    ///   - amount: 振替金額（正の値）
    ///   - fromAccountId: 出金元口座ID
    ///   - toAccountId: 入金先口座ID
    ///   - memo: メモ
    ///   - categoryId: カテゴリID（オプション）
    /// - Returns: 作成された2件のTransaction（出金、入金）のタプル
    @discardableResult
    func createTransferPair(
        date: Date,
        amount: Int,
        fromAccountId: UUID,
        toAccountId: UUID,
        memo: String = "",
        categoryId: UUID? = nil
    ) -> (outgoing: Transaction, incoming: Transaction) {
        let transferId = UUID().uuidString

        // 出金側（fromAccountから減る）
        let outgoing = Transaction(
            date: date,
            type: .transfer,
            amount: amount,  // 正の値で保存（type=transferで出金を表現）
            categoryId: categoryId,
            memo: memo,
            accountId: fromAccountId,
            toAccountId: toAccountId,
            transferId: transferId
        )

        // 入金側（toAccountに増える）
        let incoming = Transaction(
            date: date,
            type: .transfer,
            amount: amount,  // 正の値で保存（type=transferで入金を表現）
            categoryId: categoryId,
            memo: memo,
            accountId: toAccountId,
            toAccountId: fromAccountId,  // 逆向き参照
            transferId: transferId
        )

        addTransaction(outgoing)
        addTransaction(incoming)

        return (outgoing, incoming)
    }

    /// 振替ペアを削除
    /// - Parameter transferId: 振替ペアのID
    func deleteTransferPair(transferId: String) {
        let pairIds = transactions.filter { $0.transferId == transferId }.map { $0.id }
        deleteTransactions(ids: pairIds)
    }

    /// 振替ペアを取得
    /// - Parameter transferId: 振替ペアのID
    /// - Returns: ペアのTransaction配列（通常2件）
    func getTransferPair(transferId: String) -> [Transaction] {
        transactions.filter { $0.transferId == transferId }
    }

    func transactionsForDate(_ date: Date) -> [Transaction] {
        transactions.filter { !($0.isDeleted) && Calendar.current.isDate($0.date, inSameDayAs: date) }
    }

    func sortedTransactionsForDate(_ date: Date, sortOrder: SameDaySortOrder) -> [Transaction] {
        let list = transactionsForDate(date)
        switch sortOrder {
        case .createdDesc:
            return list.sorted { $0.createdAt > $1.createdAt }
        case .createdAsc:
            return list.sorted { $0.createdAt < $1.createdAt }
        case .amountDesc:
            return list.sorted { $0.amount > $1.amount }
        case .amountAsc:
            return list.sorted { $0.amount < $1.amount }
        }
    }

    func transactionsForMonth(_ monthDate: Date) -> [Transaction] {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: monthDate)
        return transactions.filter {
            guard !$0.isDeleted else { return false }
            let c = cal.dateComponents([.year, .month], from: $0.date)
            return c.year == comps.year && c.month == comps.month
        }
    }
    
    /// 当該月の収入合計
    func monthlyIncome(for date: Date) -> Int {
        transactionsForMonth(date).filter { $0.type == .income }.reduce(0) { $0 + $1.amount }
    }

    /// 当該月の支出合計
    func monthlyExpense(for date: Date) -> Int {
        transactionsForMonth(date).filter { $0.type == .expense }.reduce(0) { $0 + $1.amount }
    }

    /// 前月比（前月の収支残高）
    func previousMonthBalance(before date: Date) -> Int {
        let cal = Calendar.current
        guard let prev = cal.date(byAdding: .month, value: -1, to: date) else { return 0 }
        return monthlyIncome(for: prev) - monthlyExpense(for: prev)
    }

    /// 連続入力日数（ストリーク）を計算
    func calculateStreak() -> Int {
        let cal = Calendar.current
        // 日付のみの集合を作成
        let dates = Set(transactions.map { cal.startOfDay(for: $0.date) })
        let sortedDates = dates.sorted(by: >)
        
        guard let lastDate = sortedDates.first else { return 0 }
        
        let today = cal.startOfDay(for: Date())
        let yesterday = cal.date(byAdding: .day, value: -1, to: today) ?? today
        
        // 最終入力が今日でも昨日でもなければストリークは途切れている
        if lastDate != today && lastDate != yesterday {
            return 0
        }
        
        var streak = 0
        var checkDate = lastDate
        
        // 遡ってカウント
        for _ in 0...dates.count {
            if dates.contains(checkDate) {
                streak += 1
                // 1日前へ
                guard let prev = cal.date(byAdding: .day, value: -1, to: checkDate) else { break }
                checkDate = prev
            } else {
                break
            }
        }
        
        return streak
    }

    /// カテゴリ別集計（IDベース）
    func categoryTotal(categoryId: UUID, type: TransactionType, month: Date) -> Int {
        transactionsForMonth(month)
            .filter { $0.type == type && $0.categoryId == categoryId }
            .reduce(0) { $0 + $1.amount }
    }
    
    /// カテゴリ別集計（Backward Compatibility / Unclassified）
    /// 名前指定の場合は、マッチするカテゴリIDを探して集計 + 名前が一致する未分類レコードも含む？
    /// 基本はIDで呼ぶべき。
    func categoryTotal(categoryName: String, type: TransactionType, month: Date) -> Int {
        // 名前からIDを引く
        if let cat = findCategory(name: categoryName, type: type) {
            return categoryTotal(categoryId: cat.id, type: type, month: month)
        }
        // マスタにない場合（＝未分類扱い、または削除されたカテゴリ）
        // originalCategoryName での一致を確認
        return transactionsForMonth(month)
            .filter { $0.type == type && $0.categoryId == nil && $0.originalCategoryName == categoryName }
            .reduce(0) { $0 + $1.amount }
    }

    // MARK: - Fixed Costs
    func addFixedCostTemplate(_ t: FixedCostTemplate) {
        fixedCostTemplates.append(t)
        saveFixedCostToSwiftData(t)
    }

    func updateFixedCostTemplate(_ t: FixedCostTemplate) {
        if let idx = fixedCostTemplates.firstIndex(where: { $0.id == t.id }) {
            fixedCostTemplates[idx] = t
            saveFixedCostToSwiftData(t)
        }
    }

    func deleteFixedCostTemplate(_ t: FixedCostTemplate) {
        fixedCostTemplates.removeAll { $0.id == t.id }
        deleteFixedCostFromSwiftData(t.id)
    }

    /// アプリ起動時などに呼び出し、現在までの未処理分の固定費を生成する（過去12ヶ月分）
    func processAllFixedCostsUntilNow() {
        let now = Date()
        let cal = Calendar.current
        
        // 過去12ヶ月分を遡って処理
        // memo: processFixedCosts内で lastProcessedMonth のチェックがあるため、
        // 既に処理済みの月はスキップされるので安全。
        for i in (0..<12).reversed() {
            if let date = cal.date(byAdding: .month, value: -i, to: now) {
                processFixedCosts(for: date)
            }
        }
    }

    /// 指定月の固定費を処理する
    func processFixedCosts(for monthDate: Date) {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: monthDate)
        guard let year = comps.year, let month = comps.month else { return }
        let monthKey = "\(year)-\(String(format: "%02d", month))"

        for i in fixedCostTemplates.indices {
            var template = fixedCostTemplates[i]

            // 無効または既に処理済みの月はスキップ
            guard template.isEnabled else { continue }
            guard template.lastProcessedMonth != monthKey else { continue }

            // 対象月の日付を決定
            let day: Int
            if template.dayOfMonth == 0 {
                day = Date.daysInMonth(year: year, month: month)
            } else {
                day = min(template.dayOfMonth, Date.daysInMonth(year: year, month: month))
            }
            let txDate = Date.createDate(year: year, month: month, day: day)

            // 取引を作成
            // テンプレートが持つ categoryId を使用
            // categoryIdがなければ名前から引く（migrationで基本ID化されているはず）
            var catId = template.categoryId
            if catId == nil, let original = template.originalCategoryName {
                catId = findCategory(name: original, type: template.type)?.id
            }

            let tx = Transaction(
                date: txDate,
                type: template.type,
                amount: template.amount,
                categoryId: catId,
                originalCategoryName: (catId == nil) ? template.originalCategoryName : nil,
                memo: template.memo.isEmpty ? template.name : template.memo,
                isRecurring: true,
                templateId: template.id
            )
            transactions.append(tx)

            // 処理済みをマーク
            template.lastProcessedMonth = monthKey
            fixedCostTemplates[i] = template

            // SwiftDataに保存
            insertTransactionToSwiftData(tx)
            saveFixedCostToSwiftData(template)
        }

        updateWidget()
    }

    // MARK: - Budgets
    func totalBudget() -> Budget? {
        budgets.first(where: { $0.categoryId == nil })
    }

    func categoryBudget(for categoryId: UUID) -> Budget? {
        budgets.first(where: { $0.categoryId == categoryId })
    }
    
    // Legacy support for calling by name (if necessary)
    func categoryBudget(for categoryName: String) -> Budget? {
        guard let cat = expenseCategories.first(where: { $0.name == categoryName }) else { return nil }
        return categoryBudget(for: cat.id)
    }

    func addBudget(_ b: Budget) {
        budgets.append(b)
        saveBudgetToSwiftData(b)
    }

    func updateBudget(_ b: Budget) {
        if let idx = budgets.firstIndex(where: { $0.id == b.id }) {
            budgets[idx] = b
            saveBudgetToSwiftData(b)
        }
    }

    func deleteBudget(_ b: Budget) {
        budgets.removeAll { $0.id == b.id }
        deleteBudgetFromSwiftData(b.id)
    }

    func saveBudgets() {
        saveAllBudgetsToSwiftData()
    }

    // MARK: - CSV Export

    /// 従来の簡易CSVエクスポート（互換性維持）
    func generateCSV() -> String {
        return generateCSV(options: CSVExportOptions.minimal)
    }

    /// オプション指定可能なCSVエクスポート
    func generateCSV(options: CSVExportOptions) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "ja_JP")
        df.dateFormat = options.dateFormat

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        // ヘッダー生成
        let headerColumns = options.orderedColumns.map { $0.rawValue }
        var lines: [String] = [headerColumns.joined(separator: ",")]

        // データ行生成
        let sortedTransactions = transactions
            .filter { !$0.isDeleted }
            .sorted { $0.date < $1.date }

        for t in sortedTransactions {
            var values: [String] = []

            for col in options.orderedColumns {
                let value: String
                switch col {
                // 基本列（必須）
                case .date:
                    value = df.string(from: t.date)
                case .type:
                    value = t.type.displayName  // 支出/収入/振替
                case .amount:
                    value = String(t.amount)
                case .category:
                    value = categoryName(for: t.categoryId)
                case .memo:
                    value = t.memo

                // 拡張列
                case .transactionId:
                    value = t.id.uuidString
                case .categoryId:
                    value = t.categoryId?.uuidString ?? ""
                case .accountName:
                    value = AccountStore.shared.account(for: t.accountId)?.name ?? ""
                case .accountId:
                    value = t.accountId?.uuidString ?? ""
                case .toAccountName:
                    value = AccountStore.shared.account(for: t.toAccountId)?.name ?? ""
                case .toAccountId:
                    value = t.toAccountId?.uuidString ?? ""
                case .transferId:
                    value = t.transferId ?? ""
                case .classificationSource:
                    value = t.classificationSource?.rawValue ?? ""
                case .classificationRuleId:
                    value = t.classificationRuleId?.uuidString ?? ""
                case .classificationConfidence:
                    value = t.classificationConfidence.map { String(format: "%.2f", $0) } ?? ""
                case .classificationReason:
                    value = t.classificationReason ?? ""
                case .suggestedCategoryId:
                    value = t.suggestedCategoryId?.uuidString ?? ""
                case .suggestedCategoryName:
                    value = categoryName(for: t.suggestedCategoryId)
                case .createdAt:
                    value = isoFormatter.string(from: t.createdAt)
                case .source:
                    value = t.source ?? ""
                case .sourceId:
                    value = t.sourceId ?? ""
                case .importId:
                    value = t.importId ?? ""
                case .sourceHash:
                    value = t.sourceHash ?? ""
                case .parentId:
                    value = t.parentId?.uuidString ?? ""
                case .isSplit:
                    value = t.isSplit ? "true" : "false"
                case .isRecurring:
                    value = t.isRecurring ? "true" : "false"
                case .templateId:
                    value = t.templateId?.uuidString ?? ""
                }

                values.append(escapeCSVField(value))
            }

            lines.append(values.joined(separator: ","))
        }

        // BOM付きUTF-8の場合
        let content = lines.joined(separator: options.lineEnding.string)
        if options.includeBOM {
            return "\u{FEFF}" + content
        }
        return content
    }

    /// CSVフィールドのエスケープ処理
    private func escapeCSVField(_ value: String) -> String {
        // カンマ、ダブルクォート、改行を含む場合はクォートで囲む
        if value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") {
            let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return value
    }

    // MARK: - Search & Bulk Operations

    func searchTransactions(
        keyword: String? = nil,
        type: TransactionType? = nil,
        categoryId: UUID? = nil,
        filterByUncategorized: Bool = false, // 新規追加: 未分類のみを抽出
        dateFrom: Date? = nil,
        dateTo: Date? = nil,
        amountMin: Int? = nil,
        amountMax: Int? = nil
    ) -> [Transaction] {
        return transactions.filter { tx in
            if tx.isDeleted { return false }
            
            // キーワードフィルタ (除外検索対応)
            if let k = keyword, !k.isEmpty {
                let normalizedKeyword = TextNormalizer.normalize(k)
                
                // スペース区切りでAND検索（-始まりは除外）
                let tokens = normalizedKeyword.split(separator: " ")
                
                let memo = TextNormalizer.normalize(tx.memo)
                let catName = TextNormalizer.normalize(self.categoryName(for: tx.categoryId))
                let amountStr = String(tx.amount)
                let dateStr = TransactionSearchView.dateString(tx.date) // yyyy/MM/dd
                
                let matchesAll = tokens.allSatisfy { token in
                    if token.hasPrefix("-") && token.count > 1 {
                        // 除外検索: キーワードが含まれて「いない」こと
                        let key = String(token.dropFirst())
                        if key.isEmpty { return true } // "-"だけなら無視
                        
                        return !memo.contains(key) &&
                               !catName.contains(key) &&
                               !amountStr.contains(key) &&
                               !dateStr.contains(key)
                    } else {
                        // 通常検索: キーワードが含まれて「いる」こと
                        return memo.contains(token) || 
                               catName.contains(token) ||
                               amountStr.contains(token) ||
                               dateStr.contains(token)
                    }
                }
                if !matchesAll { return false }
            }
            
            // 種類フィルタ
            if let t = type, tx.type != t {
                return false
            }
            
            // カテゴリフィルタ
            if filterByUncategorized {
                // "未分類"を指定された場合
                if tx.categoryId != nil { return false }
            } else if let cId = categoryId {
                // 特定カテゴリを指定された場合
                if tx.categoryId != cId { return false }
            }
            
            // 期間フィルタ
            if let start = dateFrom, tx.date < start.startOfDay {
                return false
            }
            if let end = dateTo, tx.date > end.endOfDay {
                return false
            }
            
            // 金額フィルタ
            let amt = tx.amount
            if let min = amountMin, amt < min {
                return false
            }
            if let max = amountMax, amt > max {
                return false
            }
            
            return true
        }.sorted { $0.date > $1.date }
    }

    func duplicateTransaction(_ tx: Transaction, toDate: Date) {
        var newTx = tx
        newTx.id = UUID()
        newTx.date = toDate
        newTx.createdAt = Date()
        addTransaction(newTx)
    }

    /// 指定IDのうち、カテゴリが未分類の取引を返す
    func getUnclassifiedTransactions(from ids: Set<UUID>) -> [Transaction] {
        transactions.filter { tx in
            if !ids.contains(tx.id) { return false }
            return tx.categoryId == nil
        }
    }

    /// convenience（ImportResultView用）
    func getUnclassifiedTransactions(from ids: [UUID]) -> [Transaction] {
        getUnclassifiedTransactions(from: Set(ids))
    }

    @discardableResult
    func createCategoryIfNeeded(name: String, type: TransactionType) -> Category? {
        let list = categories(for: type)
        // 既存チェック
        if let existing = list.first(where: { $0.name == name }) {
            return existing
        }
        
        let nextOrder = (list.map { $0.order }.max() ?? -1) + 1
        let newCategory = Category(name: name, type: type, order: nextOrder)
        addCategory(newCategory)
        return newCategory
    }

    /// 一括カテゴリ変更（IDベース）
    func updateCategoryBatch(ids: Set<UUID>, categoryId: UUID) -> Int {
        var count = 0
        for i in transactions.indices {
            if ids.contains(transactions[i].id) {
                transactions[i].categoryId = categoryId
                transactions[i].originalCategoryName = nil // ID割り当てされるのでnilへ
                updateTransactionInSwiftData(transactions[i])
                count += 1
            }
        }
        return count
    }

    /// キーワードに基づく自動分類ルールの適用（一括）
    func applyRuleToAllTransactions(keyword: String, targetCategoryId: UUID, type: TransactionType) -> Int {
        let normalizedKeyword = TextNormalizer.normalize(keyword)
        if normalizedKeyword.isEmpty { return 0 }

        var count = 0
        for i in transactions.indices {
            // タイプが一致し、カテゴリが未設定また別カテゴリの場合
            // メモがキーワードを含む場合
            if transactions[i].type == type {
                let currentId = transactions[i].categoryId
                if currentId != targetCategoryId {
                    let memo = TextNormalizer.normalize(transactions[i].memo)
                    if memo.contains(normalizedKeyword) {
                        transactions[i].categoryId = targetCategoryId
                        transactions[i].originalCategoryName = nil
                        updateTransactionInSwiftData(transactions[i])
                        count += 1
                    }
                }
            }
        }

        return count
    }

    // MARK: - Reset
    func resetAllData() {
        // SwiftDataから全データ削除
        deleteAllFromSwiftData()

        transactions = []
        budgets = []
        fixedCostTemplates = []
        // 階層カテゴリを使用してデフォルトを再構築
        let (eGroups, eItems) = DefaultHierarchicalCategories.createDefaults(for: .expense)
        let (iGroups, iItems) = DefaultHierarchicalCategories.createDefaults(for: .income)
        categoryGroups = eGroups + iGroups
        categoryItems = eItems + iItems

        // デフォルトカテゴリをSwiftDataに保存
        saveAllCategoriesToSwiftData()
    }

    // MARK: - Backup & Restore
    private let backupKey = "ds_backup_v2"

    @discardableResult
    func createBackup() -> Bool {
        let payload = BackupPayload(
            transactions: transactions,
            expenseCategories: expenseCategories,
            incomeCategories: incomeCategories,
            fixedCostTemplates: fixedCostTemplates,
            budgets: budgets
        )
        guard let data = try? JSONEncoder().encode(payload) else { return false }
        UserDefaults.standard.set(data, forKey: backupKey)
        return true
    }

    @discardableResult
    func restoreFromBackup() -> Bool {
        guard let data = UserDefaults.standard.data(forKey: backupKey),
              let payload = try? JSONDecoder().decode(BackupPayload.self, from: data) else {
            return false
        }
        // SwiftDataから全データ削除してから復元
        deleteAllFromSwiftData()

        transactions = payload.transactions
        // 互換性維持: 旧フラットカテゴリからの復元
        restoreCategoriesFromPayload(expense: payload.expenseCategories, income: payload.incomeCategories)
        fixedCostTemplates = payload.fixedCostTemplates
        budgets = payload.budgets

        // SwiftDataに保存
        saveAllToSwiftData()
        return true
    }

    /// バックアップのフラットカテゴリから階層カテゴリを復元
    private func restoreCategoriesFromPayload(expense: [Category], income: [Category]) {
        // デフォルト階層をベースに、バックアップのカテゴリをマッピング
        let (eGroups, eItems) = DefaultHierarchicalCategories.createDefaults(for: .expense)
        let (iGroups, iItems) = DefaultHierarchicalCategories.createDefaults(for: .income)

        categoryGroups = eGroups + iGroups
        var newItems = eItems + iItems

        // バックアップのカテゴリIDを維持
        for cat in expense + income {
            if let idx = newItems.firstIndex(where: { $0.name == cat.name && $0.type == cat.type }) {
                newItems[idx].id = cat.id
                newItems[idx].colorHex = cat.colorHex
            } else {
                // 存在しないカテゴリは「その他」グループに追加
                let groupId = findOrCreateDefaultGroup(for: cat.type)
                let newItem = CategoryItem(
                    id: cat.id,
                    name: cat.name,
                    groupId: groupId,
                    type: cat.type,
                    order: 999,
                    colorHex: cat.colorHex
                )
                newItems.append(newItem)
            }
        }

        categoryItems = newItems
    }

    // MARK: - ZIP Backup & Restore

    enum ZipBackupError: LocalizedError {
        case createFailed(String)
        case restoreFailed(String)
        case invalidFormat

        var errorDescription: String? {
            switch self {
            case .createFailed(let msg): return "バックアップ作成失敗: \(msg)"
            case .restoreFailed(let msg): return "復元失敗: \(msg)"
            case .invalidFormat: return "無効なバックアップ形式です"
            }
        }
    }

    func createZipBackupData() throws -> Data {
        let payload = BackupPayload(
            transactions: transactions,
            expenseCategories: expenseCategories, // 互換性のため維持(後で削除検討)
            incomeCategories: incomeCategories,   // 同上
            fixedCostTemplates: fixedCostTemplates,
            budgets: budgets,
            accounts: AccountStore.shared.accounts,
            classificationRules: ClassificationRulesStore.shared.rules,
            categoryGroups: categoryGroups,
            categoryItems: categoryItems
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let jsonData = try? encoder.encode(payload) else {
            throw ZipBackupError.createFailed("JSONエンコードに失敗しました")
        }
        guard let zipData = createZipArchive(fileName: "backup.json", content: jsonData) else {
            throw ZipBackupError.createFailed("ZIP圧縮に失敗しました")
        }
        return zipData
    }

    @MainActor
    func restoreFromZipBackupData(_ zipData: Data) throws {
        guard let jsonData = extractFromZipArchive(zipData: zipData, fileName: "backup.json") else {
            throw ZipBackupError.invalidFormat
        }
        guard let payload = try? JSONDecoder().decode(BackupPayload.self, from: jsonData) else {
            throw ZipBackupError.restoreFailed("バックアップデータの解析に失敗しました")
        }
        
        // 1. Transaction等をSwiftDataから全削除
        deleteAllFromSwiftData()

        // 2. 基本データ復元
        transactions = payload.transactions
        fixedCostTemplates = payload.fixedCostTemplates
        budgets = payload.budgets
        
        // 3. アカウント復元 (v3 feature)
        if let accounts = payload.accounts {
            AccountStore.shared.restoreAccounts(accounts)
        }
        
        // 4. 分類ルール復元 (v3 feature)
        if let rules = payload.classificationRules {
            ClassificationRulesStore.shared.restoreRules(rules)
        }

        // 5. カテゴリ復元
        if let groups = payload.categoryGroups, let items = payload.categoryItems {
            // v3: 階層カテゴリとして復元
            categoryGroups = groups
            categoryItems = items
        } else {
            // v2互換: 旧フラットカテゴリからの復元
            restoreCategoriesFromPayload(expense: payload.expenseCategories, income: payload.incomeCategories)
        }

        // 6. SwiftDataに保存
        saveAllToSwiftData()

        // 7. 念のため復元後もID移行チェック
        performCategoryIdMigration()
    }

    // MARK: - ZIP Utilities
    private func createZipArchive(fileName: String, content: Data) -> Data? {
        var zipData = Data()
        let fileNameData = fileName.data(using: .utf8) ?? Data()
        let crc32 = content.crc32()
        
        var localHeader = Data()
        localHeader.append(contentsOf: [0x50, 0x4B, 0x03, 0x04])
        localHeader.append(contentsOf: [0x0A, 0x00])
        localHeader.append(contentsOf: [0x00, 0x00])
        localHeader.append(contentsOf: [0x00, 0x00])
        localHeader.append(contentsOf: [0x00, 0x00])
        localHeader.append(contentsOf: [0x00, 0x00])
        localHeader.append(contentsOf: crc32.littleEndianBytes)
        localHeader.append(contentsOf: UInt32(content.count).littleEndianBytes)
        localHeader.append(contentsOf: UInt32(content.count).littleEndianBytes)
        localHeader.append(contentsOf: UInt16(fileNameData.count).littleEndianBytes)
        localHeader.append(contentsOf: [0x00, 0x00])
        
        zipData.append(localHeader)
        zipData.append(fileNameData)
        zipData.append(content)
        
        let localHeaderOffset: UInt32 = 0
        var centralHeader = Data()
        centralHeader.append(contentsOf: [0x50, 0x4B, 0x01, 0x02])
        centralHeader.append(contentsOf: [0x14, 0x00])
        centralHeader.append(contentsOf: [0x0A, 0x00])
        centralHeader.append(contentsOf: [0x00, 0x00])
        centralHeader.append(contentsOf: [0x00, 0x00])
        centralHeader.append(contentsOf: [0x00, 0x00])
        centralHeader.append(contentsOf: [0x00, 0x00])
        centralHeader.append(contentsOf: crc32.littleEndianBytes)
        centralHeader.append(contentsOf: UInt32(content.count).littleEndianBytes)
        centralHeader.append(contentsOf: UInt32(content.count).littleEndianBytes)
        centralHeader.append(contentsOf: UInt16(fileNameData.count).littleEndianBytes)
        centralHeader.append(contentsOf: [0x00, 0x00])
        centralHeader.append(contentsOf: [0x00, 0x00])
        centralHeader.append(contentsOf: [0x00, 0x00])
        centralHeader.append(contentsOf: [0x00, 0x00])
        centralHeader.append(contentsOf: [0x00, 0x00, 0x00, 0x00])
        centralHeader.append(contentsOf: localHeaderOffset.littleEndianBytes)

        let centralDirOffset = UInt32(zipData.count)
        zipData.append(centralHeader)
        zipData.append(fileNameData)
        let centralDirSize = UInt32(centralHeader.count + fileNameData.count)

        var endRecord = Data()
        endRecord.append(contentsOf: [0x50, 0x4B, 0x05, 0x06])
        endRecord.append(contentsOf: [0x00, 0x00])
        endRecord.append(contentsOf: [0x00, 0x00])
        endRecord.append(contentsOf: [0x01, 0x00])
        endRecord.append(contentsOf: [0x01, 0x00])
        endRecord.append(contentsOf: centralDirSize.littleEndianBytes)
        endRecord.append(contentsOf: centralDirOffset.littleEndianBytes)
        endRecord.append(contentsOf: [0x00, 0x00])

        zipData.append(endRecord)
        return zipData
    }

    private func extractFromZipArchive(zipData: Data, fileName: String) -> Data? {
        guard zipData.count > 30, zipData[0] == 0x50, zipData[1] == 0x4B else { return nil }
        let fileNameLength = UInt16(zipData[26]) | (UInt16(zipData[27]) << 8)
        let extraFieldLength = UInt16(zipData[28]) | (UInt16(zipData[29]) << 8)
        let compressedSize = UInt32(zipData[18]) | (UInt32(zipData[19]) << 8) | (UInt32(zipData[20]) << 16) | (UInt32(zipData[21]) << 24)
        
        let headerEnd = 30 + Int(fileNameLength) + Int(extraFieldLength)
        guard zipData.count >= headerEnd + Int(compressedSize) else { return nil }
        
        let dataStart = headerEnd
        let dataEnd = dataStart + Int(compressedSize)
        return Data(zipData[dataStart..<dataEnd])
    }

    // MARK: - Persistence
    
    // MARK: - Legacy Persistence (Deprecated - kept for compatibility)

    private func loadAll() {
        // Legacy: JSONからの読み込み（マイグレーション用）
        loadTransactions()
        loadCategories()
        loadFixedCosts()
        loadBudgets()
    }

    private func saveAll() {
        // Now uses SwiftData
        saveAllToSwiftData()
    }

    // Wrappers (deprecated - use setModelContext instead)
    func loadAllFromUserDefaults() {
        loadAll()
        ensureDefaultCategoriesIfNeeded()
        performCategoryIdMigration()
    }

    func saveAllToUserDefaults() {
        saveAllToSwiftData()
    }

    // MARK: - iCloud Sync (Simplified)
    func performiCloudSync() async throws {
        guard AppFeatureFlags.cloudSyncEnabled else { return }
        let syncManager = CloudKitSyncManager.shared
        let merged = try await syncManager.performFullSync(localTransactions: transactions)
        transactions = merged
        saveAllTransactionsToSwiftData()
    }

    func uploadAllTransactionsToiCloud() async throws {
        guard AppFeatureFlags.cloudSyncEnabled else { return }
        try await CloudKitSyncManager.shared.uploadTransactions(transactions)
    }

    private func ensureDefaultCategoriesIfNeeded() {
        if categoryGroups.isEmpty || categoryItems.isEmpty {
            let (eGroups, eItems) = DefaultHierarchicalCategories.createDefaults(for: .expense)
            let (iGroups, iItems) = DefaultHierarchicalCategories.createDefaults(for: .income)
            categoryGroups = eGroups + iGroups
            categoryItems = eItems + iItems
            saveAllCategoriesToSwiftData()
        }
    }
    
    // File URLs
    private var applicationSupportDirectory: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    private var transactionsFileURL: URL { applicationSupportDirectory.appendingPathComponent("transactions.json") }
    private var categoryGroupsFileURL: URL { applicationSupportDirectory.appendingPathComponent("category_groups.json") }
    private var categoryItemsFileURL: URL { applicationSupportDirectory.appendingPathComponent("category_items.json") }
    private var fixedCostsFileURL: URL { applicationSupportDirectory.appendingPathComponent("fixed_costs.json") }
    private var budgetsFileURL: URL { applicationSupportDirectory.appendingPathComponent("budgets.json") }
    
    private func loadTransactions() {
        if let data = try? Data(contentsOf: transactionsFileURL),
           let arr = try? JSONDecoder().decode([Transaction].self, from: data) {
            transactions = arr
        }
    }
    
    private func saveTransactions() {
        if let data = try? JSONEncoder().encode(transactions) {
            try? data.write(to: transactionsFileURL, options: .atomic)
        }
        updateWidget()
    }
    
    private func loadCategories() {
        if let data = try? Data(contentsOf: categoryGroupsFileURL), let arr = try? JSONDecoder().decode([CategoryGroup].self, from: data) {
            categoryGroups = arr
        }
        if let data = try? Data(contentsOf: categoryItemsFileURL), let arr = try? JSONDecoder().decode([CategoryItem].self, from: data) {
            categoryItems = arr
        }
        
        // 旧仕様からの移行（ファイルが存在する場合）
        let oldExpenseURL = applicationSupportDirectory.appendingPathComponent("expense_categories.json")
        let oldIncomeURL = applicationSupportDirectory.appendingPathComponent("income_categories.json")
        
        if categoryGroups.isEmpty && categoryItems.isEmpty {
            if FileManager.default.fileExists(atPath: oldExpenseURL.path) || FileManager.default.fileExists(atPath: oldIncomeURL.path) {
                print("DataStore: Migrating from old categories to hierarchical...")
                migrateFromOldCategories()
            }
        }
    }
    
    private func saveCategories() {
        if let data = try? JSONEncoder().encode(categoryGroups) { try? data.write(to: categoryGroupsFileURL, options: .atomic) }
        if let data = try? JSONEncoder().encode(categoryItems) { try? data.write(to: categoryItemsFileURL, options: .atomic) }
    }
    
    /// 旧カテゴリ（平坦）から新階層カテゴリへの強制移行（初回のみ）
    private func migrateFromOldCategories() {
        let oldExpenseURL = applicationSupportDirectory.appendingPathComponent("expense_categories.json")
        let oldIncomeURL = applicationSupportDirectory.appendingPathComponent("income_categories.json")
        
        var oldExpense: [Category] = []
        var oldIncome: [Category] = []
        
        if let data = try? Data(contentsOf: oldExpenseURL), let arr = try? JSONDecoder().decode([Category].self, from: data) {
            oldExpense = arr
        }
        if let data = try? Data(contentsOf: oldIncomeURL), let arr = try? JSONDecoder().decode([Category].self, from: data) {
            oldIncome = arr
        }
        
        // デフォルトの階層構造をベースにしつつ、既存のIDを維持する
        let (eGroups, eItems) = DefaultHierarchicalCategories.createDefaults(for: .expense)
        let (iGroups, iItems) = DefaultHierarchicalCategories.createDefaults(for: .income)
        
        self.categoryGroups = eGroups + iGroups
        var newItems = eItems + iItems
        
        // 既存の平坦カテゴリに存在したIDを持つアイテムがあれば、その名前やIDを優先的にマッピングしたいが、
        // 階層化で構成が変わるため、基本は「名前一致」でIDを上書きする
        let allOld = oldExpense + oldIncome
        for i in newItems.indices {
            if let old = allOld.first(where: { $0.name == newItems[i].name }) {
                newItems[i].id = old.id // IDを維持
                newItems[i].colorHex = old.colorHex
            }
        }
        
        // 既存にあって新規にないものは「未分類」グループに追加する
        let newNames = Set(newItems.map { $0.name })
        for old in allOld {
            if !newNames.contains(old.name) {
                let groupName = "未分類"
                if let groupId = categoryGroups.first(where: { $0.name == groupName && $0.type == old.type })?.id {
                    let newItem = CategoryItem(id: old.id, name: old.name, groupId: groupId, type: old.type, order: 999, colorHex: old.colorHex)
                    newItems.append(newItem)
                }
            }
        }
        
        self.categoryItems = newItems
        saveAllCategoriesToSwiftData()

        // 旧ファイルをリネームしてバックアップ
        try? FileManager.default.moveItem(at: oldExpenseURL, to: oldExpenseURL.appendingPathExtension("bak"))
        try? FileManager.default.moveItem(at: oldIncomeURL, to: oldIncomeURL.appendingPathExtension("bak"))
    }
    
    private func loadFixedCosts() {
        if let data = try? Data(contentsOf: fixedCostsFileURL), let arr = try? JSONDecoder().decode([FixedCostTemplate].self, from: data) {
            fixedCostTemplates = arr
        }
    }
    
    private func saveFixedCosts() {
        if let data = try? JSONEncoder().encode(fixedCostTemplates) { try? data.write(to: fixedCostsFileURL, options: .atomic) }
    }
    
    private func loadBudgets() {
        if let data = try? Data(contentsOf: budgetsFileURL), let arr = try? JSONDecoder().decode([Budget].self, from: data) {
            budgets = arr
        }
    }
    
    private func persistBudgets() {
        if let data = try? JSONEncoder().encode(budgets) { try? data.write(to: budgetsFileURL, options: .atomic) }
    }
    
    // MARK: - Widget Update
    private func updateWidget() {
        let now = Date()
        // 今日の支出
        let todayExpense = transactions.filter {
            $0.type == .expense && Calendar.current.isDateInToday($0.date)
        }.reduce(0) { $0 + $1.amount }
        
        // 当月の収支
        let income = monthlyIncome(for: now)
        let expense = monthlyExpense(for: now)
        
        // 直近の取引 (4件)
        let recent = transactions
            .sorted { $0.date > $1.date || ($0.date == $1.date && $0.createdAt > $1.createdAt) }
            .prefix(4)
            .map { tx -> (id: UUID, date: Date, category: String, amount: Int, isExpense: Bool) in
                let name = self.categoryName(for: tx.categoryId)
                return (tx.id, tx.date, name, tx.amount, tx.type == .expense)
            }
            
        WidgetDataProvider.updateWidgetData(
            todayExpense: todayExpense,
            monthExpense: expense,
            monthIncome: income,
            recentTransactions: Array(recent)
        )
    }
}

// MARK: - CSV Import Extension
extension DataStore {
    func importCSV(_ csvText: String, format: CSVImportFormat, manualMapping: CSVManualMapping? = nil) -> CSVImportResult {
        Diagnostics.shared.logCSVImportStart(format: format.rawValue)

        var text = csvText.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        if !text.contains(",") && text.contains("\t") { text = text.replacingOccurrences(of: "\t", with: ",") }

        let rows = CSVParser.parse(text)
        guard !rows.isEmpty else { return CSVImportResult(added: 0, skipped: 0, errors: ["CSVが空です"], addedTransactionIds: [], duplicateSkipped: 0, invalidSkipped: 0, unclassifiedSamples: []) }

        var actualFormat = format
        if format == .cardGeneric && AmazonCardDetector.detect(rows: rows) { actualFormat = .amazonCard }
        else if (format == .bankGeneric || format == .cardGeneric) && PayPayDetector.detect(rows: rows) { actualFormat = .payPay }
        else if (format == .bankGeneric || format == .cardGeneric) && ResonaDetector.detect(rows: rows) { actualFormat = .resonaBank }

        var existing = Set(transactions.map { txKey($0) })
        var added = 0
        var skipped = 0
        var duplicateSkipped = 0
        var invalidSkipped = 0
        var errors: [String] = []
        var toAppend: [Transaction] = []
        
        // Phase1: このインポートの一意識別子を生成
        let currentImportId = UUID().uuidString
        print("[CSVImport] 開始: importId=\(currentImportId), format=\(actualFormat.rawValue)")
        
        // ログ用カウンタ
        var suggestedCount = 0       // suggestCategoryIdでカテゴリが決まった件数
        var fallbackToOtherCount = 0 // 「その他」にフォールバックした件数
        var categoryIdSetCount = 0   // 保存直前でcategoryIdがnilでない件数
        var categoryIdNilCount = 0   // 保存直前でcategoryIdがnilの件数

        let firstRow = rows[0]
        var hasHeader = looksLikeHeader(firstRow)
        var startIndex = hasHeader ? 1 : 0
        if actualFormat == .amazonCard && AmazonCardDetector.isPersonalInfoRow(firstRow) {
            hasHeader = false
            startIndex = 1
        }
        let header = hasHeader ? firstRow : []
        var map = ColumnMap.build(fromHeader: header, format: actualFormat)
        if let manual = manualMapping { map.apply(manual) }

        for i in startIndex..<rows.count {
            let r = rows[i]
            if r.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) { continue }
            if actualFormat == .amazonCard && AmazonCardDetector.isTotalRow(r) { continue }
            
            let buildResult = buildTransaction(from: r, format: actualFormat, map: map)
            
            switch buildResult {
            case .success(var tx):
                // 【重要】buildTransaction内でsuggestCategoryIdにより categoryId が設定されている場合がある
                // その場合は originalCategoryName による上書きを行わない（ルール優先）
                
                // buildTransactionでsuggestCategoryIdにより設定された場合をカウント
                let wasSuggestedByRule = tx.categoryId != nil
                if wasSuggestedByRule {
                    suggestedCount += 1
                }
                
                // categoryIdがnilの場合のみ、originalCategoryNameからカテゴリを作成/取得する
                if tx.categoryId == nil, let originalName = tx.originalCategoryName {
                    // カテゴリ作成 or 取得
                    if let cat = createCategoryIfNeeded(name: originalName, type: tx.type) {
                        tx.categoryId = cat.id
                        tx.originalCategoryName = nil
                        // 「その他」にフォールバックした場合をカウント
                        if cat.name == "その他" {
                            fallbackToOtherCount += 1
                        }
                    }
                } else if tx.categoryId != nil {
                    // ルールでカテゴリが決定済みの場合、originalCategoryNameをクリア
                    tx.originalCategoryName = nil
                }
                
                // 保存直前のcategoryId状況をカウント
                if tx.categoryId != nil {
                    categoryIdSetCount += 1
                } else {
                    categoryIdNilCount += 1
                }
                
                // 重複チェック
                // txKeyは categoryId優先で判定するよう実装（後述）
                let key = txKey(tx)
                if existing.contains(key) {
                    skipped += 1
                    duplicateSkipped += 1
                    continue
                }
                existing.insert(key)
                
                // Phase1: importIdを付与
                tx.importId = currentImportId
                
                toAppend.append(tx)
                added += 1
                
            case .failure(let reason):
                skipped += 1
                invalidSkipped += 1
                if errors.count < 30 { errors.append("行\(i+1): \(reason.localizedDescription)") }
            }
        }

        if !toAppend.isEmpty {
            transactions.append(contentsOf: toAppend)
            // SwiftDataに一括保存
            for tx in toAppend {
                insertTransactionToSwiftData(tx)
            }
            updateWidget()
        }
        
        // 未分類の抽出（IDなし、または その他）
        let addedIds = toAppend.map { $0.id }
        let unclassifiedSamples: [String] = {
            var seen = Set<String>()
            var out: [String] = []
            for tx in toAppend {
                if tx.categoryId == nil || self.categoryName(for: tx.categoryId) == "その他" {
                    let memo = tx.memo.trimmingCharacters(in: .whitespacesAndNewlines)
                    let s = memo.isEmpty ? "(メモなし) \(tx.amount)円" : memo
                    if !seen.contains(s) {
                        seen.insert(s)
                        out.append(s)
                    }
                }
                if out.count >= 50 { break }
            }
            return out
        }()

        let result = CSVImportResult(
            added: added,
            skipped: skipped,
            errors: errors,
            addedTransactionIds: addedIds,
            duplicateSkipped: duplicateSkipped,
            invalidSkipped: invalidSkipped,
            unclassifiedSamples: unclassifiedSamples,
            importId: currentImportId
        )

        // カテゴリ分類状況のログ出力
        print("[CSVImport] カテゴリ分類結果: suggestedByRule=\(suggestedCount), fallbackToOther=\(fallbackToOtherCount), categoryIdSet=\(categoryIdSetCount), categoryIdNil=\(categoryIdNilCount)")
        print("[CSVImport] 完了: importId=\(currentImportId), added=\(added), skipped=\(skipped), total_transactions=\(transactions.count)")
        
        Diagnostics.shared.logCSVImportResult(
            added: result.added,
            skipped: result.skipped,
            duplicateSkipped: result.duplicateSkipped,
            invalidSkipped: result.invalidSkipped,
            errors: result.errors
        )

        return result
    }

    private func txKey(_ t: Transaction) -> String {
        // カテゴリ名を解決（ID→名前）して統一的に比較
        let catName = categoryName(for: t.categoryId) ?? t.originalCategoryName ?? ""
        return fingerprintKeyWithCategoryName(t, categoryName: catName)
    }
    
    private func fingerprintKeyWithCategoryName(_ t: Transaction, categoryName: String) -> String {
        let cal = Calendar(identifier: .gregorian)
        let day = cal.startOfDay(for: t.date)
        let catStr = TextNormalizer.normalize(categoryName)
        
        var components: [String] = [
            "\(day.timeIntervalSince1970)",
            t.type.rawValue,
            "\(t.amount)",
            catStr,
            TextNormalizer.normalize(t.memo)
        ]
        
        // 振替の場合は口座情報も含める
        if t.type == .transfer {
            components.append(t.accountId?.uuidString ?? "")
            components.append(t.toAccountId?.uuidString ?? "")
        } else if let accId = t.accountId {
            components.append(accId.uuidString)
        }
        
        // source/sourceId情報
        if let source = t.source {
            components.append(TextNormalizer.normalize(source))
        }
        if let sourceId = t.sourceId {
            components.append(sourceId)
        }
        
        return components.joined(separator: "|")
    }

    private func looksLikeHeader(_ row: [String]) -> Bool {
        let joined = row.joined(separator: ",").lowercased()
        let keywords = ["日付", "種類", "金額", "カテゴリ", "メモ", "category", "date"]
        return keywords.contains(where: { joined.contains($0.lowercased()) })
    }

    private enum CSVImportError: Error {
        case parseError(String)
        
        var localizedDescription: String {
            switch self {
            case .parseError(let message): return message
            }
        }
    }

    private func buildTransaction(from row: [String], format: CSVImportFormat, map: ColumnMap) -> Result<Transaction, CSVImportError> {
        // 基本的に Transaction(...) init を呼ぶが、category: String 引数がない
        // originalCategoryName に入れる
        var date: Date
        var type: TransactionType
        var amount: Int
        var memo: String
        var catName: String

        switch format {
        case .appExport:
            guard row.count >= 3 else { return .failure(.parseError("列数が不足しています (3列以上必要)")) }
            guard let d = DateParser.parse(row[safe: 0] ?? "") else { return .failure(.parseError("日付の形式が不正です: \(row[safe: 0] ?? "")")) }
            guard let (t, a) = parseAppTypeAmount(typeStr: row[safe: 1] ?? "", amountStr: row[safe: 2] ?? "") else { return .failure(.parseError("金額または種別が不正です: \(row[safe: 1] ?? "") / \(row[safe: 2] ?? "")")) }
            date = d; type = t; amount = a
            catName = (row[safe: 3] ?? "").isEmpty ? defaultCategoryName(for: type) : (row[safe: 3] ?? "")
            memo = row[safe: 4] ?? ""

        case .bankGeneric, .cardGeneric:
            guard let ds = map.pickDate(from: row), let d = DateParser.parse(ds) else {
                return .failure(.parseError("日付が見つからないか形式が不正です"))
            }
            guard let (t, a) = map.pickTypeAmount(from: row, format: format) else {
                return .failure(.parseError("金額または入出金種別を特定できませんでした"))
            }
            date = d; type = t; amount = a
            memo = map.pickMemo(from: row) ?? ""
            catName = map.pickCategory(from: row) ?? defaultCategoryName(for: type)

        case .amazonCard:
            guard row.count >= 3 else { return .failure(.parseError("列数が不足しています")) }
            guard let d = DateParser.parse(row[safe: 0] ?? "") else { return .failure(.parseError("日付の形式が不正です: \(row[safe: 0] ?? "")")) }
            guard let a = AmountParser.parse(row[safe: 2] ?? ""), a > 0 else { return .failure(.parseError("金額が不正です: \(row[safe: 2] ?? "")")) }
            date = d; type = .expense; amount = a
            let raw = row[safe: 1] ?? ""
            memo = TextNormalizer.normalize(raw)
            if memo.uppercased().contains("AMAZON.CO.JP") { memo = "Amazonでの購入" }
            catName = defaultCategoryName(for: .expense)

        case .resonaBank:
            // 1. レガシー形式（固定列 14,15,16）のパースを試行
            if row.count > 19,
               let y = row[safe: 14], let m = row[safe: 15], let d = row[safe: 16],
               let dateVal = DateParser.parse("\(y)/\(m)/\(d)"),
               let a = AmountParser.parse(row[safe: 17] ?? ""), a > 0 {
                
                // レガシーパース成功
                let typeStr = row[safe: 13]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                type = (typeStr.contains("入金") || typeStr.contains("預入") || typeStr.contains("受取")) ? .income : .expense
                amount = a
                memo = TextNormalizer.normalize(row[safe: 19] ?? "")
                catName = defaultCategoryName(for: type)
                date = dateVal
            } else {
                // 2. フォールバック: ColumnMapを使用した汎用パース（新形式対応）
                guard let d = map.pickDateValue(from: row) else { return .failure(.parseError("Resona: 日付を特定できませんでした")) }
                date = d
                
                // 金額・種類
                if let (t, a) = map.pickAmountFromDebitCredit(from: row) {
                    type = t; amount = a
                } else if let a = map.pickAmount(from: row) {
                    amount = a
                    if let typeVal = map.pickType(from: row) {
                        type = typeVal
                    } else {
                        type = .expense
                    }
                } else {
                    return .failure(.parseError("Resona: 金額を特定できませんでした"))
                }
                
                memo = TextNormalizer.normalize(map.pickMemoString(from: row))
                catName = map.pickCategory(from: row) ?? defaultCategoryName(for: type)
            }

        case .payPay:
            guard row.count > 8 else { return .failure(.parseError("PayPay: 列数が不足しています")) }
            guard let d = DateParser.parse(row[safe: 0] ?? "") else { return .failure(.parseError("PayPay: 日付不正: \(row[safe: 0] ?? "")")) }
            let outStr = row[safe: 1] ?? ""; let inStr = row[safe: 2] ?? ""
            let content = row[safe: 7]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let partner = row[safe: 8]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            var t: TransactionType = .expense; var a = 0

            if let v = AmountParser.parse(outStr), v > 0 {
                t = .expense; a = v
            } else if let v = AmountParser.parse(inStr), v > 0 {
                t = .income; a = v
            } else {
                return .failure(.parseError("PayPay: 金額が見つかりません (行: \(row))"))
            }
            if content == "チャージ" { t = .transfer }

            date = d; type = t; amount = a
            // メモ構築
            if !partner.isEmpty {
                memo = partner
                if !content.isEmpty { memo += " (\(content))" }
            } else {
                memo = content
            }
            if memo.isEmpty { memo = "PayPay取引" }
            catName = defaultCategoryName(for: t)
        }
        
        let tx = Transaction(date: date, type: type, amount: amount, categoryId: nil, originalCategoryName: catName, memo: memo)
        
        // 分類ルールを使ってカテゴリIDを推測
        // カテゴリマスタを渡して、ルールに無い場合もキーワードから推測できるようにする
        if let suggestedId = ClassificationRulesStore.shared.suggestCategoryId(from: [memo, catName], type: type, categories: categories(for: type)) {
            var updatedTx = tx
            updatedTx.categoryId = suggestedId
            // 予測できた場合は originalCategoryName はそのままにしておくか、nilにするか
            // 入力画面の挙動に合わせるならそのままの方が「予測された」ことが分かりやすいかもしれないが、
            // ID解決済みとして扱うならnilの方が重複判定などで有利
            return .success(updatedTx)
        }
        
        return .success(tx)
    }

    private func defaultCategoryName(for type: TransactionType) -> String {
        "その他"
    }

    private func parseAppTypeAmount(typeStr: String, amountStr: String) -> (TransactionType, Int)? {
        guard let raw = AmountParser.parse(amountStr) else { return nil }
        let t = typeStr.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.contains("収入") || t.lowercased().contains("income") { return (.income, abs(raw)) }
        if t.contains("支出") || t.lowercased().contains("expense") { return (.expense, abs(raw)) }
        return (raw < 0 ? .expense : .income, abs(raw))
    }
}

fileprivate extension Array where Element == String {
    subscript(safe index: Int) -> String? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}

// MARK: - SwiftData Operations
extension DataStore {

    // MARK: - Load All from SwiftData

    private func loadAllFromSwiftData() {
        guard let context = modelContext else {
            Diagnostics.shared.log("ModelContext not available, falling back to JSON", category: .error)
            loadAllFromJSON()
            return
        }

        loadTransactionsFromSwiftData(context: context)
        loadCategoriesFromSwiftData(context: context)
        loadFixedCostsFromSwiftData(context: context)
        loadBudgetsFromSwiftData(context: context)

        // Initialize Balance Cache
        AccountStore.shared.refreshBalances(transactions: transactions)

        Diagnostics.shared.log("Loaded from SwiftData: \(transactions.count) transactions, \(categoryItems.count) categories", category: .swiftData)
    }

    private func loadTransactionsFromSwiftData(context: ModelContext) {
        let descriptor = FetchDescriptor<TransactionModel>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        if let models = try? context.fetch(descriptor) {
            transactions = models.map { $0.toTransaction() }
        }
    }

    private func loadCategoriesFromSwiftData(context: ModelContext) {
        let groupDescriptor = FetchDescriptor<CategoryGroupModel>(sortBy: [SortDescriptor(\.order)])
        if let models = try? context.fetch(groupDescriptor) {
            categoryGroups = models.map { $0.toCategoryGroup() }
        }

        let itemDescriptor = FetchDescriptor<CategoryItemModel>(sortBy: [SortDescriptor(\.order)])
        if let models = try? context.fetch(itemDescriptor) {
            categoryItems = models.map { $0.toCategoryItem() }
        }
    }

    private func loadFixedCostsFromSwiftData(context: ModelContext) {
        let descriptor = FetchDescriptor<FixedCostTemplateModel>()
        if let models = try? context.fetch(descriptor) {
            fixedCostTemplates = models.map { $0.toFixedCostTemplate() }
        }
    }

    private func loadBudgetsFromSwiftData(context: ModelContext) {
        let descriptor = FetchDescriptor<BudgetModel>()
        if let models = try? context.fetch(descriptor) {
            budgets = models.map { $0.toBudget() }
        }
    }

    // MARK: - Transaction CRUD (SwiftData)

    private func insertTransactionToSwiftData(_ tx: Transaction) {
        guard let context = modelContext else { return }
        let model = TransactionModel(from: tx)
        context.insert(model)
        do {
            try context.save()
            AccountStore.shared.applyTransactionIncremental(tx)
        } catch {
            Diagnostics.shared.log("Failed to insert transaction: \(error)", category: .error)
        }
    }

    private func updateTransactionInSwiftData(_ tx: Transaction, oldTx: Transaction? = nil) {
        guard let context = modelContext else { return }
        // #Predicate除去
        let descriptor = FetchDescriptor<TransactionModel>()

        if let models = try? context.fetch(descriptor), let model = models.first(where: { $0.id == tx.id }) {
            // Update all fields
            model.date = tx.date
            model.typeRaw = tx.type.rawValue
            model.amount = tx.amount
            model.categoryId = tx.categoryId
            model.originalCategoryName = tx.originalCategoryName
            model.memo = tx.memo
            model.isRecurring = tx.isRecurring
            model.templateId = tx.templateId
            model.source = tx.source
            model.sourceId = tx.sourceId
            model.accountId = tx.accountId
            model.toAccountId = tx.toAccountId
            model.parentId = tx.parentId
            model.isSplit = tx.isSplit
            model.isDeleted = tx.isDeleted
            model.transferId = tx.transferId
            // 分類情報フィールド
            model.classificationSource = tx.classificationSource
            model.classificationRuleId = tx.classificationRuleId
            model.classificationConfidence = tx.classificationConfidence
            model.classificationReason = tx.classificationReason
            model.suggestedCategoryId = tx.suggestedCategoryId
            do {
                try context.save()
                if let old = oldTx {
                    AccountStore.shared.removeTransactionIncremental(old)
                }
                AccountStore.shared.applyTransactionIncremental(tx)
            } catch {
                Diagnostics.shared.log("Failed to update transaction: \(error)", category: .error)
            }
        } else {
            // Not found, insert new
            insertTransactionToSwiftData(tx)
        }
    }

    private func deleteTransactionFromSwiftData(_ id: UUID, originalTx: Transaction? = nil) {
        guard let context = modelContext else { return }
        // #Predicate除去
        let descriptor = FetchDescriptor<TransactionModel>()

        if let models = try? context.fetch(descriptor), let model = models.first(where: { $0.id == id }) {
            context.delete(model)
            do {
                try context.save()
                if let tx = originalTx {
                    AccountStore.shared.removeTransactionIncremental(tx)
                }
            } catch {
                Diagnostics.shared.log("Failed to delete transaction: \(error)", category: .error)
            }
        }
    }

    private func deleteTransactionsFromSwiftData(ids: [UUID], originalTransactions: [Transaction] = []) {
        guard let context = modelContext else { return }
        let idSet = Set(ids)
        let descriptor = FetchDescriptor<TransactionModel>()

        if let models = try? context.fetch(descriptor) {
            for model in models where idSet.contains(model.id) {
                context.delete(model)
            }
            do {
                try context.save()
                for tx in originalTransactions {
                    AccountStore.shared.removeTransactionIncremental(tx)
                }
            } catch {
                Diagnostics.shared.log("Failed to delete transactions batch: \(error)", category: .error)
            }
        }
    }

    func saveAllTransactionsToSwiftData() {
        guard let context = modelContext else { return }

        // Get existing IDs
        let descriptor = FetchDescriptor<TransactionModel>()
        let existingModels = (try? context.fetch(descriptor)) ?? []
        let existingIds = Set(existingModels.map { $0.id })

        for tx in transactions {
            if existingIds.contains(tx.id) {
                updateTransactionInSwiftData(tx)
            } else {
                insertTransactionToSwiftData(tx)
            }
        }
    }

    // MARK: - Category CRUD (SwiftData)

    private func saveCategoryGroupToSwiftData(_ group: CategoryGroup) {
        guard let context = modelContext else { return }
        // #Predicate除去
        let descriptor = FetchDescriptor<CategoryGroupModel>()

        if let models = try? context.fetch(descriptor), let model = models.first(where: { $0.id == group.id }) {
            model.name = group.name
            model.typeRaw = group.type.rawValue
            model.order = group.order
            model.colorHex = group.colorHex
        } else {
            let model = CategoryGroupModel(from: group)
            context.insert(model)
        }
        try? context.save()
    }

    private func saveCategoryItemToSwiftData(_ item: CategoryItem) {
        guard let context = modelContext else { return }
        // #Predicate除去
        let descriptor = FetchDescriptor<CategoryItemModel>()

        if let models = try? context.fetch(descriptor), let model = models.first(where: { $0.id == item.id }) {
            model.name = item.name
            model.groupId = item.groupId
            model.typeRaw = item.type.rawValue
            model.order = item.order
            model.colorHex = item.colorHex
        } else {
            let model = CategoryItemModel(from: item)
            context.insert(model)
        }
        try? context.save()
    }

    private func deleteCategoryItemFromSwiftData(_ id: UUID) {
        guard let context = modelContext else { return }
        // #Predicate除去
        let descriptor = FetchDescriptor<CategoryItemModel>()

        if let models = try? context.fetch(descriptor), let model = models.first(where: { $0.id == id }) {
            context.delete(model)
            try? context.save()
        }
    }

    func saveAllCategoriesToSwiftData() {
        guard let context = modelContext else { return }

        for group in categoryGroups {
            saveCategoryGroupToSwiftData(group)
        }
        for item in categoryItems {
            saveCategoryItemToSwiftData(item)
        }
    }

    // MARK: - FixedCost CRUD (SwiftData)

    private func saveFixedCostToSwiftData(_ template: FixedCostTemplate) {
        guard let context = modelContext else { return }
        // #Predicate除去
        let descriptor = FetchDescriptor<FixedCostTemplateModel>()

        if let models = try? context.fetch(descriptor), let model = models.first(where: { $0.id == template.id }) {
            model.name = template.name
            model.typeRaw = template.type.rawValue
            model.amount = template.amount
            model.categoryId = template.categoryId
            model.originalCategoryName = template.originalCategoryName
            model.dayOfMonth = template.dayOfMonth
            model.memo = template.memo
            model.isEnabled = template.isEnabled
            model.lastProcessedMonth = template.lastProcessedMonth
        } else {
            let model = FixedCostTemplateModel(from: template)
            context.insert(model)
        }
        try? context.save()
    }

    private func deleteFixedCostFromSwiftData(_ id: UUID) {
        guard let context = modelContext else { return }
        // #Predicate除去
        let descriptor = FetchDescriptor<FixedCostTemplateModel>()

        if let models = try? context.fetch(descriptor), let model = models.first(where: { $0.id == id }) {
            context.delete(model)
            try? context.save()
        }
    }

    func saveAllFixedCostsToSwiftData() {
        guard let context = modelContext else { return }
        for template in fixedCostTemplates {
            saveFixedCostToSwiftData(template)
        }
    }

    // MARK: - Budget CRUD (SwiftData)

    private func saveBudgetToSwiftData(_ budget: Budget) {
        guard let context = modelContext else { return }
        // #Predicate除去
        let descriptor = FetchDescriptor<BudgetModel>()

        if let models = try? context.fetch(descriptor), let model = models.first(where: { $0.id == budget.id }) {
            model.categoryId = budget.categoryId
            model.originalCategoryName = budget.originalCategoryName
            model.amount = budget.amount
            model.month = budget.month
            model.year = budget.year
        } else {
            let model = BudgetModel(from: budget)
            context.insert(model)
        }
        try? context.save()
    }

    private func deleteBudgetFromSwiftData(_ id: UUID) {
        guard let context = modelContext else { return }
        // #Predicate除去
        let descriptor = FetchDescriptor<BudgetModel>()

        if let models = try? context.fetch(descriptor), let model = models.first(where: { $0.id == id }) {
            context.delete(model)
            try? context.save()
        }
    }

    func saveAllBudgetsToSwiftData() {
        guard let context = modelContext else { return }
        for budget in budgets {
            saveBudgetToSwiftData(budget)
        }
    }

    // MARK: - Bulk Operations (SwiftData)

    /// 全データをSwiftDataに保存
    func saveAllToSwiftData() {
        saveAllTransactionsToSwiftData()
        saveAllCategoriesToSwiftData()
        saveAllFixedCostsToSwiftData()
        saveAllBudgetsToSwiftData()
    }

    /// SwiftDataから全データを削除（リセット用）
    private func deleteAllFromSwiftData() {
        guard let context = modelContext else { return }

        // Transactions
        let txDescriptor = FetchDescriptor<TransactionModel>()
        if let models = try? context.fetch(txDescriptor) {
            for model in models { context.delete(model) }
        }

        // Category Groups
        let groupDescriptor = FetchDescriptor<CategoryGroupModel>()
        if let models = try? context.fetch(groupDescriptor) {
            for model in models { context.delete(model) }
        }

        // Category Items
        let itemDescriptor = FetchDescriptor<CategoryItemModel>()
        if let models = try? context.fetch(itemDescriptor) {
            for model in models { context.delete(model) }
        }

        // Fixed Costs
        let fixedDescriptor = FetchDescriptor<FixedCostTemplateModel>()
        if let models = try? context.fetch(fixedDescriptor) {
            for model in models { context.delete(model) }
        }

        // Budgets
        let budgetDescriptor = FetchDescriptor<BudgetModel>()
        if let models = try? context.fetch(budgetDescriptor) {
            for model in models { context.delete(model) }
        }

        try? context.save()
        Diagnostics.shared.log("All data deleted from SwiftData", category: .swiftData)
    }

    // MARK: - Fallback JSON Loading (for migration)

    private func loadAllFromJSON() {
        loadTransactionsFromJSON()
        loadCategoriesFromJSON()
        loadFixedCostsFromJSON()
        loadBudgetsFromJSON()
    }

    private func loadTransactionsFromJSON() {
        if let data = try? Data(contentsOf: transactionsFileURL),
           let arr = try? JSONDecoder().decode([Transaction].self, from: data) {
            transactions = arr
        }
    }

    private func loadCategoriesFromJSON() {
        if let data = try? Data(contentsOf: categoryGroupsFileURL),
           let arr = try? JSONDecoder().decode([CategoryGroup].self, from: data) {
            categoryGroups = arr
        }
        if let data = try? Data(contentsOf: categoryItemsFileURL),
           let arr = try? JSONDecoder().decode([CategoryItem].self, from: data) {
            categoryItems = arr
        }
    }

    private func loadFixedCostsFromJSON() {
        if let data = try? Data(contentsOf: fixedCostsFileURL),
           let arr = try? JSONDecoder().decode([FixedCostTemplate].self, from: data) {
            fixedCostTemplates = arr
        }
    }

    private func loadBudgetsFromJSON() {
        if let data = try? Data(contentsOf: budgetsFileURL),
           let arr = try? JSONDecoder().decode([Budget].self, from: data) {
            budgets = arr
        }
    }

    // MARK: - Import History Operations

    /// インポート履歴を保存
    func saveImportHistory(_ history: ImportHistory) {
        guard let context = modelContext else { return }

        let model = ImportHistoryModel(
            id: history.id,
            importId: history.importId,
            importDate: history.importDate,
            filename: history.filename,
            fileHash: history.fileHash,
            totalRowCount: history.totalRowCount,
            addedCount: history.addedCount,
            duplicateCount: history.duplicateCount,
            skippedCount: history.skippedCount,
            source: history.source,
            notes: history.notes
        )
        context.insert(model)
        try? context.save()
        Diagnostics.shared.log("Saved import history: \(history.filename)", category: .swiftData)
    }

    /// インポート履歴を取得（新しい順）
    func fetchImportHistory() -> [ImportHistory] {
        guard let context = modelContext else { return [] }

        var descriptor = FetchDescriptor<ImportHistoryModel>(
            sortBy: [SortDescriptor(\.importDate, order: .reverse)]
        )
        descriptor.fetchLimit = 100

        if let models = try? context.fetch(descriptor) {
            return models.map { $0.toImportHistory() }
        }
        return []
    }

    /// 同一ファイルハッシュの履歴を検索
    func findImportHistoryByHash(_ hash: String) -> ImportHistory? {
        guard let context = modelContext else { return nil }

        // #Predicate除去
        let descriptor = FetchDescriptor<ImportHistoryModel>()

        if let models = try? context.fetch(descriptor), let model = models.first(where: { $0.fileHash == hash }) {
            return model.toImportHistory()
        }
        return nil
    }

    /// インポート履歴を削除
    func deleteImportHistory(_ history: ImportHistory) {
        guard let context = modelContext else { return }

        // #Predicate除去
        let descriptor = FetchDescriptor<ImportHistoryModel>()

        if let models = try? context.fetch(descriptor), let model = models.first(where: { $0.id == history.id }) {
            context.delete(model)
            try? context.save()
        }
    }

    /// インポート履歴に紐づく取引を削除し、履歴も削除
    /// - Parameter history: 削除対象のインポート履歴
    /// - Returns: 削除した取引の件数
    @discardableResult
    func deleteTransactionsByImportHistory(_ history: ImportHistory) -> Int {
        guard let context = modelContext else { return 0 }

        let targetImportId = history.importId
        let targetFileHash = history.fileHash
        print("[DeleteImport] 開始: importId=\(targetImportId), filename=\(history.filename)")

        // SwiftDataから該当取引を検索して削除
        let descriptor = FetchDescriptor<TransactionModel>()
        var deletedCount = 0

        do {
            let models = try context.fetch(descriptor)
            let toDelete = models.filter { model in
                // 1. 新方式: importIdが一致
                if let importId = model.importId, !importId.isEmpty, importId == targetImportId {
                    return true
                }
                // 2. 互換方式: sourceIdがfileHashと一致
                if let sourceId = model.sourceId, !sourceId.isEmpty, sourceId == targetFileHash {
                    return true
                }
                return false
            }

            for model in toDelete {
                context.delete(model)
                deletedCount += 1
            }
            
            // 変更内容を永続化
            try context.save()
            print("[DeleteImport] SwiftDataから \(deletedCount) 件削除しました")
        } catch {
            print("[DeleteImport] 削除中にエラーが発生しました: \(error.localizedDescription)")
            Diagnostics.shared.log("Failed to delete transactions for import \(targetImportId): \(error.localizedDescription)", category: .swiftData)
        }

        // メモリ上の配列を同期
        let initialCount = transactions.count
        transactions.removeAll { tx in
            // 1. 新方式: importIdが一致
            if let importId = tx.importId, !importId.isEmpty, importId == targetImportId {
                return true
            }
            // 2. 互換方式: sourceIdがfileHashと一致
            if let sourceId = tx.sourceId, !sourceId.isEmpty, sourceId == targetFileHash {
                return true
            }
            return false
        }
        let removedFromMemory = initialCount - transactions.count
        print("[DeleteImport] メモリから \(removedFromMemory) 件削除しました")

        // 削除した件数が0の場合のフォールバック表示用
        if deletedCount == 0 && removedFromMemory > 0 {
            deletedCount = removedFromMemory
        }

        // 履歴自体も削除
        deleteImportHistory(history)

        updateWidget()
        return deletedCount
    }

    /// 全てのインポート済み取引を削除（手動入力は保持）
    /// 自動分類ルール・カテゴリ・予算・固定費は保持される
    func deleteAllImportedTransactions() {
        guard let context = modelContext else { return }

        // sourceが設定されている取引のみ削除（CSVインポートされたもの）
        let descriptor = FetchDescriptor<TransactionModel>()

        if let models = try? context.fetch(descriptor) {
            let imported = models.filter { $0.source != nil && !$0.source!.isEmpty }
            for model in imported {
                context.delete(model)
            }
        }

        // メモリ上のtransactionsからも削除
        transactions.removeAll { $0.source != nil && !$0.source!.isEmpty }

        // インポート履歴も全削除
        let historyDescriptor = FetchDescriptor<ImportHistoryModel>()
        if let histories = try? context.fetch(historyDescriptor) {
            for h in histories {
                context.delete(h)
            }
        }

        try? context.save()
        
        // 残高を再計算
        AccountStore.shared.refreshBalances(transactions: transactions)
    }

    /// 特定のインポートソースに紐づく取引件数を取得
    func countTransactionsForImportHistory(_ history: ImportHistory) -> Int {
        let fileHash = history.fileHash

        // メモリ上のtransactionsから数える
        let count = transactions.filter { tx in
            if let sourceId = tx.sourceId, sourceId == fileHash {
                return true
            }
            return false
        }.count

        // 見つからない場合はaddedCountを返す（推定値）
        return count > 0 ? count : history.addedCount
    }

    /// CSVコンテンツのハッシュを計算（正規化付き）
    func calculateCSVHash(_ csvText: String) -> String {
        // 正規化: 改行統一、BOM除去、空白トリム
        var normalized = csvText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.hasPrefix("\u{FEFF}") {
            normalized.removeFirst()
        }
        // 各行をトリムして空行を除去
        let lines = normalized.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let cleanContent = lines.joined(separator: "\n")

        // SHA256ハッシュ
        return cleanContent.sha256Hash
    }
}

// MARK: - Import Wizard Commit (Phase 2)
extension DataStore {
    /// ドラフト行を確定保存する（ウィザード用）
    /// - Parameters:
    ///   - rows: ImportDraftRow配列（メモリ上のドラフト）
    ///   - accountId: 紐付ける口座ID（任意）
    ///   - fileName: CSVファイル名
    ///   - fileHash: CSVコンテンツのハッシュ
    ///   - format: CSVフォーマット
    /// - Returns: ImportCommitResult
    func commitDraftRows(
        _ rows: [ImportDraftRow],
        accountId: UUID?,
        fileName: String,
        fileHash: String,
        format: CSVImportFormat
    ) -> ImportCommitResult {
        // 1. importIdを1回だけ生成
        let importId = UUID().uuidString
        print("[CommitDraft] 開始: importId=\(importId), rows=\(rows.count)")

        // 2. 解決済みの行のみ対象（duplicate, invalid, unresolvedは除外）
        let validRows = rows.filter { $0.status == .resolved }
        print("[CommitDraft] 有効行数: \(validRows.count)")

        // 3. Transaction生成・保存
        var addedIds: [UUID] = []
        var toAppend: [Transaction] = []

        for draftRow in validRows {
            // finalCategoryIdを使用（なければsuggestedを使用）
            let categoryId = draftRow.finalCategoryId ?? draftRow.suggestedCategoryId

            let tx = Transaction(
                date: draftRow.date,
                type: draftRow.type,
                amount: draftRow.amount,
                categoryId: categoryId,
                originalCategoryName: nil, // ID解決済み
                memo: draftRow.description.isEmpty ? draftRow.memo : draftRow.description,
                isRecurring: false,
                templateId: nil,
                createdAt: Date(),
                source: format.rawValue,
                sourceId: nil,
                accountId: accountId,
                toAccountId: nil,
                parentId: nil,
                isSplit: false,
                isDeleted: false,
                importId: importId,
                sourceHash: nil
            )

            toAppend.append(tx)
            addedIds.append(tx.id)
        }

        // 4. 一括保存
        if !toAppend.isEmpty {
            transactions.append(contentsOf: toAppend)
            for tx in toAppend {
                insertTransactionToSwiftData(tx)
            }
            updateWidget()
        }

        // 5. ImportHistory作成・保存
        let duplicateCount = rows.filter { $0.status == .duplicate }.count
        let invalidCount = rows.filter { $0.status == .invalid }.count
        let skippedCount = duplicateCount + invalidCount

        let history = ImportHistory(
            id: UUID(),
            importId: importId,
            importDate: Date(),
            filename: fileName,
            fileHash: fileHash,
            totalRowCount: rows.count,
            addedCount: addedIds.count,
            duplicateCount: duplicateCount,
            skippedCount: skippedCount,
            source: format.rawValue,
            notes: nil
        )
        saveImportHistory(history)

        print("[CommitDraft] 完了: added=\(addedIds.count), skipped=\(skippedCount), importId=\(importId)")

        // 6. 結果を返す
        return ImportCommitResult(
            importId: importId,
            totalRows: rows.count,
            addedCount: addedIds.count,
            skippedCount: skippedCount,
            duplicateCount: duplicateCount,
            addedTransactionIds: addedIds
        )
    }

    // MARK: - Phase 3-3: 振替対応のコミット関数

    /// ドラフト行を確定保存する（振替対応版）
    /// 振替確定された行は2本のTransaction（出金/入金ペア）として保存
    /// - Parameters:
    ///   - rows: ImportDraftRow配列（メモリ上のドラフト）
    ///   - primaryAccountId: CSVの口座ID（振替の主口座）
    ///   - fileName: CSVファイル名
    ///   - fileHash: CSVコンテンツのハッシュ
    ///   - format: CSVフォーマット
    /// - Returns: ImportCommitResult
    func commitDraftRowsWithTransfer(
        _ rows: [ImportDraftRow],
        primaryAccountId: UUID?,
        fileName: String,
        fileHash: String,
        format: CSVImportFormat
    ) -> ImportCommitResult {
        // 1. importIdを1回だけ生成
        let importId = UUID().uuidString
        print("[CommitDraftWithTransfer] 開始: importId=\(importId), rows=\(rows.count)")

        // 2. 行を分類
        let resolvedRows = rows.filter { $0.status == .resolved }
        let transferConfirmedRows = rows.filter { $0.status == .transferConfirmed }
        let duplicateCount = rows.filter { $0.status == .duplicate }.count
        let invalidCount = rows.filter { $0.status == .invalid }.count
        let skippedCount = duplicateCount + invalidCount

        print("[CommitDraftWithTransfer] resolved=\(resolvedRows.count), transferConfirmed=\(transferConfirmedRows.count), skipped=\(skippedCount)")

        // 3. Transaction生成
        var addedIds: [UUID] = []
        var toAppend: [Transaction] = []
        var transferPairCount = 0

        // 3a. 通常の解決済み行をTransaction化
        for draftRow in resolvedRows {
            let categoryId = draftRow.finalCategoryId ?? draftRow.suggestedCategoryId

            // 分類ソースを決定
            let classificationSource: ClassificationSource
            let classificationReason: String?
            if let aiReason = draftRow.aiReason, !aiReason.isEmpty {
                // AI分類
                classificationSource = .ai
                classificationReason = aiReason
            } else if draftRow.finalCategoryId != nil && draftRow.finalCategoryId != draftRow.suggestedCategoryId {
                // ユーザーが手動で変更した
                classificationSource = .manual
                classificationReason = nil
            } else if draftRow.suggestedCategoryId != nil {
                // ルールベースの自動分類
                classificationSource = .rule
                classificationReason = nil
            } else {
                // インポートのデフォルト
                classificationSource = .imported
                classificationReason = nil
            }

            var tx = Transaction(
                date: draftRow.date,
                type: draftRow.type,
                amount: draftRow.amount,
                categoryId: categoryId,
                originalCategoryName: nil,
                memo: draftRow.description.isEmpty ? draftRow.memo : draftRow.description,
                isRecurring: false,
                templateId: nil,
                createdAt: Date(),
                source: format.rawValue,
                sourceId: nil,
                accountId: primaryAccountId,
                toAccountId: nil,
                parentId: nil,
                isSplit: false,
                isDeleted: false,
                importId: importId,
                sourceHash: nil,
                transferId: nil
            )

            // 分類情報を設定
            tx.classificationSource = classificationSource
            tx.classificationReason = classificationReason
            tx.suggestedCategoryId = draftRow.suggestedCategoryId

            toAppend.append(tx)
            addedIds.append(tx.id)
        }

        // 3b. 振替確定行を2本のTransaction（ペア）として生成
        for draftRow in transferConfirmedRows {
            guard let counterAccountId = draftRow.counterAccountId else {
                print("[CommitDraftWithTransfer] WARNING: transferConfirmedだがcounterAccountIdがnil: \(draftRow.id)")
                continue
            }

            // 振替ペア用のtransferIdを生成
            let transferId = UUID().uuidString

            // 金額の符号で方向を判定
            // amountSign == .minus → primaryから出金（expense）、counterへ入金（income）
            // amountSign == .plus → primaryへ入金（income）、counterから出金（expense）
            let isOutgoing = draftRow.amountSign == .minus
            let absAmount = abs(draftRow.amount)

            // 振替カテゴリを取得（「振替」カテゴリがあれば使用、なければnil）
            let transferCategoryId = findTransferCategoryId()

            if isOutgoing {
                // 主口座から出金（振替）
                let outgoingTx = Transaction(
                    date: draftRow.date,
                    type: .transfer,  // 振替として保存（収支計算から除外するため）
                    amount: absAmount,
                    categoryId: transferCategoryId,
                    originalCategoryName: nil,
                    memo: "振替: \(draftRow.description)",
                    isRecurring: false,
                    templateId: nil,
                    createdAt: Date(),
                    source: format.rawValue,
                    sourceId: nil,
                    accountId: primaryAccountId,
                    toAccountId: counterAccountId,
                    parentId: nil,
                    isSplit: false,
                    isDeleted: false,
                    importId: importId,
                    sourceHash: nil,
                    transferId: transferId
                )

                // 相手口座へ入金（振替）
                let incomingTx = Transaction(
                    date: draftRow.date,
                    type: .transfer,  // 振替として保存（収支計算から除外するため）
                    amount: absAmount,
                    categoryId: transferCategoryId,
                    originalCategoryName: nil,
                    memo: "振替: \(draftRow.description)",
                    isRecurring: false,
                    templateId: nil,
                    createdAt: Date(),
                    source: format.rawValue,
                    sourceId: nil,
                    accountId: counterAccountId,
                    toAccountId: primaryAccountId,
                    parentId: nil,
                    isSplit: false,
                    isDeleted: false,
                    importId: importId,
                    sourceHash: nil,
                    transferId: transferId
                )

                toAppend.append(outgoingTx)
                toAppend.append(incomingTx)
                addedIds.append(outgoingTx.id)
                addedIds.append(incomingTx.id)

                print("[CommitDraftWithTransfer] 振替ペア生成(出金): transferId=\(transferId), amount=\(absAmount)")
            } else {
                // 主口座へ入金（振替）
                let incomingTx = Transaction(
                    date: draftRow.date,
                    type: .transfer,  // 振替として保存（収支計算から除外するため）
                    amount: absAmount,
                    categoryId: transferCategoryId,
                    originalCategoryName: nil,
                    memo: "振替: \(draftRow.description)",
                    isRecurring: false,
                    templateId: nil,
                    createdAt: Date(),
                    source: format.rawValue,
                    sourceId: nil,
                    accountId: primaryAccountId,
                    toAccountId: counterAccountId,
                    parentId: nil,
                    isSplit: false,
                    isDeleted: false,
                    importId: importId,
                    sourceHash: nil,
                    transferId: transferId
                )

                // 相手口座から出金（振替）
                let outgoingTx = Transaction(
                    date: draftRow.date,
                    type: .transfer,  // 振替として保存（収支計算から除外するため）
                    amount: absAmount,
                    categoryId: transferCategoryId,
                    originalCategoryName: nil,
                    memo: "振替: \(draftRow.description)",
                    isRecurring: false,
                    templateId: nil,
                    createdAt: Date(),
                    source: format.rawValue,
                    sourceId: nil,
                    accountId: counterAccountId,
                    toAccountId: primaryAccountId,
                    parentId: nil,
                    isSplit: false,
                    isDeleted: false,
                    importId: importId,
                    sourceHash: nil,
                    transferId: transferId
                )

                toAppend.append(incomingTx)
                toAppend.append(outgoingTx)
                addedIds.append(incomingTx.id)
                addedIds.append(outgoingTx.id)

                print("[CommitDraftWithTransfer] 振替ペア生成(入金): transferId=\(transferId), amount=\(absAmount)")
            }

            transferPairCount += 1
        }

        // 4. 一括保存
        if !toAppend.isEmpty {
            transactions.append(contentsOf: toAppend)
            for tx in toAppend {
                insertTransactionToSwiftData(tx)
            }
            updateWidget()
        }

        // 5. ImportHistory作成・保存
        let history = ImportHistory(
            id: UUID(),
            importId: importId,
            importDate: Date(),
            filename: fileName,
            fileHash: fileHash,
            totalRowCount: rows.count,
            addedCount: addedIds.count,
            duplicateCount: duplicateCount,
            skippedCount: skippedCount,
            source: format.rawValue,
            notes: transferPairCount > 0 ? "振替ペア: \(transferPairCount)件" : nil
        )
        saveImportHistory(history)

        print("[CommitDraftWithTransfer] 完了: added=\(addedIds.count), transferPairs=\(transferPairCount), skipped=\(skippedCount), importId=\(importId)")

        // 6. 結果を返す
        return ImportCommitResult(
            importId: importId,
            totalRows: rows.count,
            addedCount: addedIds.count,
            skippedCount: skippedCount,
            duplicateCount: duplicateCount,
            addedTransactionIds: addedIds,
            transferPairCount: transferPairCount
        )
    }

    /// 振替用カテゴリIDを検索（「振替」「現金入出金」などの名前で検索）
    private func findTransferCategoryId() -> UUID? {
        // 支出カテゴリから「振替」「現金入出金」を検索
        let transferNames = ["振替", "現金入出金", "チャージ"]
        for name in transferNames {
            if let cat = expenseCategories.first(where: { $0.name == name }) {
                return cat.id
            }
        }
        // 収入カテゴリからも検索
        for name in transferNames {
            if let cat = incomeCategories.first(where: { $0.name == name }) {
                return cat.id
            }
        }
        return nil
    }
}

// MARK: - String SHA256 Extension

import CryptoKit

extension String {
    var sha256Hash: String {
        let data = Data(self.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}
