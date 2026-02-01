import Foundation
import WidgetKit

// MARK: - Widget Data Provider

/// ウィジェット用のデータ提供
/// App Groupsを使用してメインアプリとデータを共有
struct WidgetDataProvider {
    
    // App Groups identifier (実際のプロジェクトでは適切なIDに変更)
    static let appGroupID = "group.com.kakeibo.app"
    
    private static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }
    
    // MARK: - Keys
    
    private enum Keys {
        static let todayExpense = "widget_today_expense"
        static let monthExpense = "widget_month_expense"
        static let monthIncome = "widget_month_income"
        static let monthBalance = "widget_month_balance"
        static let lastUpdate = "widget_last_update"
        static let recentTransactions = "widget_recent_transactions"
    }
    
    // MARK: - Data Structures
    
    struct WidgetData: Codable {
        var todayExpense: Int
        var monthExpense: Int
        var monthIncome: Int
        var monthBalance: Int
        var lastUpdate: Date
        var recentTransactions: [SimpleTransaction]
        
        struct SimpleTransaction: Codable, Identifiable {
            var id: String
            var date: Date
            var category: String
            var amount: Int
            var isExpense: Bool
        }
    }
    
    // MARK: - Write (from main app)
    
    static func updateWidgetData(
        todayExpense: Int,
        monthExpense: Int,
        monthIncome: Int,
        recentTransactions: [(id: UUID, date: Date, category: String, amount: Int, isExpense: Bool)]
    ) {
        guard let defaults = sharedDefaults else { return }
        
        defaults.set(todayExpense, forKey: Keys.todayExpense)
        defaults.set(monthExpense, forKey: Keys.monthExpense)
        defaults.set(monthIncome, forKey: Keys.monthIncome)
        defaults.set(monthIncome - monthExpense, forKey: Keys.monthBalance)
        defaults.set(Date(), forKey: Keys.lastUpdate)
        
        // 直近の取引をJSON化して保存
        let simpleTransactions = recentTransactions.map { tx in
            WidgetData.SimpleTransaction(
                id: tx.id.uuidString,
                date: tx.date,
                category: tx.category,
                amount: tx.amount,
                isExpense: tx.isExpense
            )
        }
        
        if let data = try? JSONEncoder().encode(simpleTransactions) {
            defaults.set(data, forKey: Keys.recentTransactions)
        }
        
        // ウィジェットの更新をリクエスト
        WidgetCenter.shared.reloadAllTimelines()
    }
    
    // MARK: - Read (from widget)
    
    static func getWidgetData() -> WidgetData {
        guard let defaults = sharedDefaults else {
            return WidgetData(
                todayExpense: 0,
                monthExpense: 0,
                monthIncome: 0,
                monthBalance: 0,
                lastUpdate: Date(),
                recentTransactions: []
            )
        }
        
        let todayExpense = defaults.integer(forKey: Keys.todayExpense)
        let monthExpense = defaults.integer(forKey: Keys.monthExpense)
        let monthIncome = defaults.integer(forKey: Keys.monthIncome)
        let monthBalance = defaults.integer(forKey: Keys.monthBalance)
        let lastUpdate = defaults.object(forKey: Keys.lastUpdate) as? Date ?? Date()
        
        var recentTransactions: [WidgetData.SimpleTransaction] = []
        if let data = defaults.data(forKey: Keys.recentTransactions),
           let decoded = try? JSONDecoder().decode([WidgetData.SimpleTransaction].self, from: data) {
            recentTransactions = decoded
        }
        
        return WidgetData(
            todayExpense: todayExpense,
            monthExpense: monthExpense,
            monthIncome: monthIncome,
            monthBalance: monthBalance,
            lastUpdate: lastUpdate,
            recentTransactions: recentTransactions
        )
    }
}

// MARK: - Widget Timeline Entry

struct KakeiboWidgetEntry: TimelineEntry {
    let date: Date
    let data: WidgetDataProvider.WidgetData
    
    static var placeholder: KakeiboWidgetEntry {
        KakeiboWidgetEntry(
            date: Date(),
            data: WidgetDataProvider.WidgetData(
                todayExpense: 1500,
                monthExpense: 45000,
                monthIncome: 250000,
                monthBalance: 205000,
                lastUpdate: Date(),
                recentTransactions: []
            )
        )
    }
}
