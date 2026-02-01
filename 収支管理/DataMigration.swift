import Foundation
import SwiftData

// MARK: - Data Migration (JSON Files → SwiftData)

@MainActor
final class DataMigration {

    // MARK: - Migration Entry Point

    /// JSONからSwiftDataへのマイグレーションを実行
    /// MigrationStatusを使用して一度だけの実行を保証
    static func migrateIfNeeded(context: ModelContext) {
        let status = MigrationStatus.shared

        // 既に完了している場合はスキップ
        guard status.needsMigration else {
            Diagnostics.shared.log("SwiftData migration already completed", category: .migration)
            return
        }

        Diagnostics.shared.log("Starting JSON → SwiftData migration...", category: .migration)

        var transactionCount = 0
        var categoryCount = 0
        var accountCount = 0

        do {
            // 1. Transactions
            transactionCount = migrateTransactionsFromJSON(context: context)

            // 2. Category Groups & Items
            categoryCount = migrateCategoriesFromJSON(context: context)

            // 3. Accounts
            accountCount = migrateAccountsFromJSON(context: context)

            // 4. Fixed Cost Templates
            migrateFixedCostsFromJSON(context: context)

            // 5. Budgets
            migrateBudgetsFromJSON(context: context)

            // 保存
            try context.save()

            // 完了マーク
            status.markJsonToSwiftDataMigrationCompleted(
                transactionCount: transactionCount,
                categoryCount: categoryCount,
                accountCount: accountCount
            )

            Diagnostics.shared.log("Migration completed successfully", category: .migration)

        } catch {
            Diagnostics.shared.log("Migration failed: \(error.localizedDescription)", category: .error)
        }
    }

    // MARK: - JSON File Paths

    private static var applicationSupportDirectory: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return dir
    }

    private static var transactionsFileURL: URL {
        applicationSupportDirectory.appendingPathComponent("transactions.json")
    }

    private static var categoryGroupsFileURL: URL {
        applicationSupportDirectory.appendingPathComponent("category_groups.json")
    }

    private static var categoryItemsFileURL: URL {
        applicationSupportDirectory.appendingPathComponent("category_items.json")
    }

    private static var fixedCostsFileURL: URL {
        applicationSupportDirectory.appendingPathComponent("fixed_costs.json")
    }

    private static var budgetsFileURL: URL {
        applicationSupportDirectory.appendingPathComponent("budgets.json")
    }

    // MARK: - Migration Methods

    private static func migrateTransactionsFromJSON(context: ModelContext) -> Int {
        // JSONファイルから読み込み
        guard let data = try? Data(contentsOf: transactionsFileURL),
              let transactions = try? JSONDecoder().decode([Transaction].self, from: data) else {
            Diagnostics.shared.log("No transactions.json found or empty", category: .migration)
            return 0
        }

        // 既存のSwiftData取引を取得（重複チェック用）
        let existingIds = fetchExistingTransactionIds(context: context)

        var insertedCount = 0
        for tx in transactions {
            // 重複チェック
            if existingIds.contains(tx.id) {
                continue
            }

            let model = TransactionModel(from: tx)
            context.insert(model)
            insertedCount += 1
        }

        Diagnostics.shared.log("Migrated \(insertedCount) transactions (skipped \(transactions.count - insertedCount) duplicates)", category: .migration)
        return insertedCount
    }

    private static func migrateCategoriesFromJSON(context: ModelContext) -> Int {
        var totalCount = 0

        // Category Groups
        if let data = try? Data(contentsOf: categoryGroupsFileURL),
           let groups = try? JSONDecoder().decode([CategoryGroup].self, from: data) {

            let existingGroupIds = fetchExistingCategoryGroupIds(context: context)

            for group in groups {
                if existingGroupIds.contains(group.id) { continue }

                let model = CategoryGroupModel(from: group)
                context.insert(model)
                totalCount += 1
            }

            Diagnostics.shared.log("Migrated \(groups.count) category groups", category: .migration)
        } else {
            // JSONファイルがない場合はデフォルトを作成
            Diagnostics.shared.log("No category_groups.json found, creating defaults", category: .migration)
            createDefaultCategories(context: context)
            return countCategoryItems(context: context)
        }

        // Category Items
        if let data = try? Data(contentsOf: categoryItemsFileURL),
           let items = try? JSONDecoder().decode([CategoryItem].self, from: data) {

            let existingItemIds = fetchExistingCategoryItemIds(context: context)

            for item in items {
                if existingItemIds.contains(item.id) { continue }

                let model = CategoryItemModel(from: item)
                context.insert(model)
                totalCount += 1
            }

            Diagnostics.shared.log("Migrated \(items.count) category items", category: .migration)
        }

        return totalCount
    }

    private static func migrateAccountsFromJSON(context: ModelContext) -> Int {
        // AccountStoreはUserDefaultsを使用しているので、そこから読み込む
        let storageKey = "accounts_v1"
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let accounts = try? JSONDecoder().decode([Account].self, from: data) else {
            Diagnostics.shared.log("No accounts found in UserDefaults, creating defaults", category: .migration)
            createDefaultAccounts(context: context)
            return 3 // デフォルト口座数
        }

        let existingIds = fetchExistingAccountIds(context: context)

        var insertedCount = 0
        for account in accounts {
            if existingIds.contains(account.id) { continue }

            let model = AccountModel(from: account)
            context.insert(model)
            insertedCount += 1
        }

        Diagnostics.shared.log("Migrated \(insertedCount) accounts", category: .migration)
        return insertedCount
    }

    private static func migrateFixedCostsFromJSON(context: ModelContext) {
        guard let data = try? Data(contentsOf: fixedCostsFileURL),
              let templates = try? JSONDecoder().decode([FixedCostTemplate].self, from: data) else {
            Diagnostics.shared.log("No fixed_costs.json found", category: .migration)
            return
        }

        let existingIds = fetchExistingFixedCostIds(context: context)

        var insertedCount = 0
        for template in templates {
            if existingIds.contains(template.id) { continue }

            let model = FixedCostTemplateModel(from: template)
            context.insert(model)
            insertedCount += 1
        }

        Diagnostics.shared.log("Migrated \(insertedCount) fixed cost templates", category: .migration)
    }

    private static func migrateBudgetsFromJSON(context: ModelContext) {
        guard let data = try? Data(contentsOf: budgetsFileURL),
              let budgets = try? JSONDecoder().decode([Budget].self, from: data) else {
            Diagnostics.shared.log("No budgets.json found", category: .migration)
            return
        }

        let existingIds = fetchExistingBudgetIds(context: context)

        var insertedCount = 0
        for budget in budgets {
            if existingIds.contains(budget.id) { continue }

            let model = BudgetModel(from: budget)
            context.insert(model)
            insertedCount += 1
        }

        Diagnostics.shared.log("Migrated \(insertedCount) budgets", category: .migration)
    }

    // MARK: - Fetch Existing IDs (for idempotent migration)

    private static func fetchExistingTransactionIds(context: ModelContext) -> Set<UUID> {
        let descriptor = FetchDescriptor<TransactionModel>()
        guard let models = try? context.fetch(descriptor) else { return [] }
        return Set(models.map { $0.id })
    }

    private static func fetchExistingCategoryGroupIds(context: ModelContext) -> Set<UUID> {
        let descriptor = FetchDescriptor<CategoryGroupModel>()
        guard let models = try? context.fetch(descriptor) else { return [] }
        return Set(models.map { $0.id })
    }

    private static func fetchExistingCategoryItemIds(context: ModelContext) -> Set<UUID> {
        let descriptor = FetchDescriptor<CategoryItemModel>()
        guard let models = try? context.fetch(descriptor) else { return [] }
        return Set(models.map { $0.id })
    }

    private static func fetchExistingAccountIds(context: ModelContext) -> Set<UUID> {
        let descriptor = FetchDescriptor<AccountModel>()
        guard let models = try? context.fetch(descriptor) else { return [] }
        return Set(models.map { $0.id })
    }

    private static func fetchExistingFixedCostIds(context: ModelContext) -> Set<UUID> {
        let descriptor = FetchDescriptor<FixedCostTemplateModel>()
        guard let models = try? context.fetch(descriptor) else { return [] }
        return Set(models.map { $0.id })
    }

    private static func fetchExistingBudgetIds(context: ModelContext) -> Set<UUID> {
        let descriptor = FetchDescriptor<BudgetModel>()
        guard let models = try? context.fetch(descriptor) else { return [] }
        return Set(models.map { $0.id })
    }

    // MARK: - Default Data Creation

    private static func createDefaultCategories(context: ModelContext) {
        let (expenseGroups, expenseItems) = DefaultHierarchicalCategories.createDefaults(for: .expense)
        let (incomeGroups, incomeItems) = DefaultHierarchicalCategories.createDefaults(for: .income)

        for group in expenseGroups + incomeGroups {
            let model = CategoryGroupModel(from: group)
            context.insert(model)
        }

        for item in expenseItems + incomeItems {
            let model = CategoryItemModel(from: item)
            context.insert(model)
        }

        Diagnostics.shared.log("Created default categories: \(expenseGroups.count + incomeGroups.count) groups, \(expenseItems.count + incomeItems.count) items", category: .migration)
    }

    private static func createDefaultAccounts(context: ModelContext) {
        let defaultAccounts = [
            Account(name: "現金", type: .cash, colorHex: "#4CAF50", order: 0),
            Account(name: "銀行口座", type: .bank, colorHex: "#2196F3", order: 1),
            Account(name: "クレジットカード", type: .creditCard, colorHex: "#FF9800", order: 2),
        ]

        for account in defaultAccounts {
            let model = AccountModel(from: account)
            context.insert(model)
        }

        Diagnostics.shared.log("Created default accounts: \(defaultAccounts.count)", category: .migration)
    }

    private static func countCategoryItems(context: ModelContext) -> Int {
        let descriptor = FetchDescriptor<CategoryItemModel>()
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    // MARK: - Debug Utilities

    /// マイグレーションフラグをリセット（デバッグ用）
    static func resetMigrationFlag() {
        MigrationStatus.shared.resetMigrationStatus()
    }
}
