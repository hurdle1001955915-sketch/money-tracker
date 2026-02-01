import SwiftUI
import Foundation
import Combine

#if canImport(SwiftData)
import SwiftData
#endif

// MARK: - AccountStore

@MainActor
final class AccountStore: ObservableObject {
    static let shared = AccountStore()

    private let storageKey = "accounts_v1"

    // SwiftData ModelContext - will be injected from App
    private var modelContext: ModelContext?

    @Published private(set) var accounts: [Account] = []

    private init() {
        // 初期化時にはまだModelContextがないので、ロードはsetModelContext後に行う
    }

    // MARK: - ModelContext Injection

    /// ModelContextを注入してSwiftDataからデータをロード
    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
        loadAccountsFromSwiftData()
        ensureDefaultAccountsIfNeeded()
    }

    // MARK: - CRUD

    var activeAccounts: [Account] {
        accounts.filter { $0.isActive }.sorted { $0.order < $1.order }
    }

    func account(for id: UUID?) -> Account? {
        guard let id = id else { return nil }
        return accounts.first { $0.id == id }
    }

    /// 現金口座を取得（ATM取引の振替先として使用）
    func cashAccount() -> Account? {
        return accounts.first { $0.type == .cash && $0.isActive }
    }

    func addAccount(_ account: Account) {
        var newAccount = account
        newAccount.order = accounts.count
        accounts.append(newAccount)
        saveAccountToSwiftData(newAccount)
    }

    func updateAccount(_ account: Account) {
        if let idx = accounts.firstIndex(where: { $0.id == account.id }) {
            accounts[idx] = account
            saveAccountToSwiftData(account)
        }
    }

    func deleteAccount(_ account: Account) {
        // 論理削除（関連取引があるため）
        if let idx = accounts.firstIndex(where: { $0.id == account.id }) {
            accounts[idx].isActive = false
            saveAccountToSwiftData(accounts[idx])
        }
    }

    func reorderAccounts(from: IndexSet, to: Int) {
        var active = activeAccounts
        active.move(fromOffsets: from, toOffset: to)

        for (i, account) in active.enumerated() {
            if let idx = accounts.firstIndex(where: { $0.id == account.id }) {
                accounts[idx].order = i
                saveAccountToSwiftData(accounts[idx])
            }
        }
    }

    // MARK: - Balance Calculation

    private var balanceCache: [UUID: Int] = [:]
    
    /// 全口座の残高を再計算してキャッシュを更新
    /// - Parameter transactions: 全取引データ
    func refreshBalances(transactions: [Transaction]) {
        var newCache: [UUID: Int] = [:]
        
        // 初期残高をセット
        for account in accounts {
            newCache[account.id] = account.initialBalance
        }
        
        // 取引を集計
        for tx in transactions where !tx.isDeleted {
            applyTransactionToCache(tx, cache: &newCache)
        }
        
        self.balanceCache = newCache
    }

    /// 特定の取引をキャッシュに反映（インクリメンタル更新用）
    func applyTransactionIncremental(_ tx: Transaction) {
        applyTransactionToCache(tx, cache: &balanceCache)
        objectWillChange.send()
    }

    /// 特定の取引をキャッシュから除外（インクリメンタル更新用）
    func removeTransactionIncremental(_ tx: Transaction) {
        removeTransactionFromCache(tx, cache: &balanceCache)
        objectWillChange.send()
    }

    private func applyTransactionToCache(_ tx: Transaction, cache: inout [UUID: Int]) {
        if tx.isDeleted { return }

        // 出金側
        if let accountId = tx.accountId, let current = cache[accountId] {
            switch tx.type {
            case .expense, .transfer:
                cache[accountId] = current - tx.amount
            case .income:
                cache[accountId] = current + tx.amount
            }
        }
        
        // 入金側 (振替)
        if tx.type == .transfer, let toId = tx.toAccountId, let current = cache[toId] {
            cache[toId] = current + tx.amount
        }
    }

    private func removeTransactionFromCache(_ tx: Transaction, cache: inout [UUID: Int]) {
        // 反映されていた内容を逆転させる
        
        // 出金側の逆転
        if let accountId = tx.accountId, let current = cache[accountId] {
            switch tx.type {
            case .expense, .transfer:
                cache[accountId] = current + tx.amount
            case .income:
                cache[accountId] = current - tx.amount
            }
        }
        
        // 入金側 (振替) の逆転
        if tx.type == .transfer, let toId = tx.toAccountId, let current = cache[toId] {
            cache[toId] = current - tx.amount
        }
    }
    
    /// 指定口座の現在残高（キャッシュ使用）
    func currentBalance(for accountId: UUID) -> Int {
        return balanceCache[accountId] ?? 0
    }

    /// 指定口座の任意時点の残高を計算（過去分は計算が必要）
    func balance(for accountId: UUID, transactions: [Transaction], asOf date: Date = Date()) -> Int {
        // 現在日付(今日以降)ならキャッシュを返す
        if date >= Date().startOfDay {
             return currentBalance(for: accountId)
        }

        guard let account = account(for: accountId) else { return 0 }

        var balance = account.initialBalance

        for tx in transactions where tx.date <= date && !tx.isDeleted {
            // この口座からの出金
            if tx.accountId == accountId {
                switch tx.type {
                case .expense:
                    balance -= tx.amount
                case .income:
                    balance += tx.amount
                case .transfer:
                    // 振替元として出金
                    balance -= tx.amount
                }
            }

            // この口座への入金（振替先）
            if tx.toAccountId == accountId && tx.type == .transfer {
                balance += tx.amount
            }
        }

        return balance
    }

    /// 全口座の合計残高（キャッシュ使用）
    func totalBalance() -> Int {
        activeAccounts.reduce(0) { sum, account in
            sum + currentBalance(for: account.id)
        }
    }
    
    /// 全口座の合計残高（過去指定用）
    func totalBalance(transactions: [Transaction], asOf date: Date) -> Int {
        activeAccounts.reduce(0) { sum, account in
            sum + balance(for: account.id, transactions: transactions, asOf: date)
        }
    }

    // MARK: - SwiftData Operations

    private func loadAccountsFromSwiftData() {
        guard let context = modelContext else {
            // Fallback to UserDefaults for migration
            loadAccountsFromUserDefaults()
            return
        }

        let descriptor = FetchDescriptor<AccountModel>(sortBy: [SortDescriptor(\.order)])
        if let models = try? context.fetch(descriptor) {
            accounts = models.map { $0.toAccount() }
            Diagnostics.shared.log("Loaded \(accounts.count) accounts from SwiftData", category: .swiftData)
        }
    }

    private func saveAccountToSwiftData(_ account: Account) {
        guard let context = modelContext else { return }

        // #Predicate除去: 全件取得してIDで検索
        let descriptor = FetchDescriptor<AccountModel>()
        
        do {
            let models = try context.fetch(descriptor)
            
            if let model = models.first(where: { $0.id == account.id }) {
                // Update existing
                model.name = account.name
                model.typeRaw = account.type.rawValue
                model.colorHex = account.colorHex
                model.order = account.order
                model.isActive = account.isActive
                model.initialBalance = account.initialBalance
            } else {
                // Insert new
                let model = AccountModel(from: account)
                context.insert(model)
            }
            try context.save()
        } catch {
            print("Failed to save account to SwiftData: \(error)")
        }
    }

    private func saveAllAccountsToSwiftData() {
        for account in accounts {
            saveAccountToSwiftData(account)
        }
    }

    // MARK: - Legacy Persistence (for migration)

    private func loadAccountsFromUserDefaults() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([Account].self, from: data) else {
            return
        }
        accounts = decoded
        Diagnostics.shared.log("Loaded \(accounts.count) accounts from UserDefaults (fallback)", category: .json)
    }

    private func ensureDefaultAccountsIfNeeded() {
        // 1. 口座が全くない場合は完全に新規
        if accounts.isEmpty {
            let defaultAccounts = [
                Account(name: "現金", type: .cash, colorHex: "#4CAF50", order: 0),
                Account(name: "銀行口座", type: .bank, colorHex: "#2196F3", order: 1),
                Account(name: "クレジットカード", type: .creditCard, colorHex: "#FF9800", order: 2),
                Account(name: "PayPay", type: .payPay, colorHex: "#FF0033", order: 3),
                Account(name: "Suica（iPhone）", type: .suica, colorHex: "#009E44", order: 4),
                Account(name: "Suica（Apple Watch）", type: .suica, colorHex: "#009E44", order: 5),
            ]
            accounts = defaultAccounts
            saveAllAccountsToSwiftData()
            return
        }

        // 2. 既存ユーザーの場合、PayPayやSuicaが不足していれば追加（利便性のため）
        let existingNames = Set(accounts.map { $0.name })
        var toAdd: [Account] = []
        
        let commonAccounts = [
            (name: "PayPay", type: AccountType.payPay, color: "#FF0033"),
            (name: "Suica（iPhone）", type: AccountType.suica, color: "#009E44"),
            (name: "Suica（Apple Watch）", type: AccountType.suica, color: "#009E44")
        ]
        
        for common in commonAccounts {
            if !existingNames.contains(common.name) {
                toAdd.append(Account(name: common.name, type: common.type, colorHex: common.color, order: accounts.count + toAdd.count))
            }
        }
        
        if !toAdd.isEmpty {
            accounts.append(contentsOf: toAdd)
            for acc in toAdd {
                saveAccountToSwiftData(acc)
            }
            Diagnostics.shared.log("Added \(toAdd.count) missing common accounts", category: .swiftData)
        }
    }

    /// デフォルト口座にリセット
    func resetToDefaults() {
        deleteAllAccountsFromSwiftData()
        accounts = []
        ensureDefaultAccountsIfNeeded()
    }
    
    /// バックアップからの復元
    func restoreAccounts(_ newAccounts: [Account]) {
        deleteAllAccountsFromSwiftData()
        accounts = newAccounts
        saveAllAccountsToSwiftData()
        Diagnostics.shared.log("Restored \(accounts.count) accounts from backup", category: .swiftData)
    }
    
    private func deleteAllAccountsFromSwiftData() {
        guard let context = modelContext else { return }
        let descriptor = FetchDescriptor<AccountModel>()
        if let models = try? context.fetch(descriptor) {
            for model in models {
                context.delete(model)
            }
            try? context.save()
        }
    }
}

// MARK: - Account Color Extension

extension Account {
    var color: Color {
        Color(hex: colorHex)
    }
}
