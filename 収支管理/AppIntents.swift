import Foundation
import Intents
import AppIntents

// MARK: - App Intents (iOS 16+)

/// 今日の支出を確認するショートカット
struct GetTodayExpenseIntent: AppIntent {
    static var title: LocalizedStringResource = "今日の支出を確認"
    static var description = IntentDescription("今日使った金額を確認します")
    
    static var openAppWhenRun: Bool = false
    
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let expense = await getTodayExpense()
        
        if expense == 0 {
            return .result(dialog: "今日はまだ支出がありません。")
        } else {
            let formatted = formatCurrency(expense)
            return .result(dialog: "今日の支出は\(formatted)です。")
        }
    }
    
    @MainActor
    private func getTodayExpense() -> Int {
        let transactions = DataStore.shared.transactionsForDate(Date())
        return transactions
            .filter { $0.type == .expense }
            .reduce(0) { $0 + $1.amount }
    }
    
    private func formatCurrency(_ amount: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        let str = formatter.string(from: NSNumber(value: amount)) ?? "0"
        return "\(str)円"
    }
}

/// 今月の収支を確認するショートカット
struct GetMonthSummaryIntent: AppIntent {
    static var title: LocalizedStringResource = "今月の収支を確認"
    static var description = IntentDescription("今月の収入・支出・残高を確認します")
    
    static var openAppWhenRun: Bool = false
    
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let summary = await getMonthSummary()
        
        let incomeStr = formatCurrency(summary.income)
        let expenseStr = formatCurrency(summary.expense)
        let balanceStr = formatCurrency(summary.balance)
        
        let balanceText = summary.balance >= 0 ? "残高は\(balanceStr)" : "\(balanceStr)の赤字"
        
        return .result(dialog: "今月の収入は\(incomeStr)、支出は\(expenseStr)。\(balanceText)です。")
    }
    
    @MainActor
    private func getMonthSummary() -> (income: Int, expense: Int, balance: Int) {
        let income = DataStore.shared.monthlyIncome(for: Date())
        let expense = DataStore.shared.monthlyExpense(for: Date())
        return (income, expense, income - expense)
    }
    
    private func formatCurrency(_ amount: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        let str = formatter.string(from: NSNumber(value: abs(amount))) ?? "0"
        return "\(str)円"
    }
}

/// 支出を記録するショートカット
struct AddExpenseIntent: AppIntent {
    static var title: LocalizedStringResource = "支出を記録"
    static var description = IntentDescription("新しい支出を家計簿に記録します")
    
    @Parameter(title: "金額")
    var amount: Int
    
    @Parameter(title: "カテゴリ", default: "その他")
    var category: String
    
    @Parameter(title: "メモ", default: "")
    var memo: String
    
    static var parameterSummary: some ParameterSummary {
        Summary("￥\(\.$amount) を \(\.$category) として記録") {
            \.$memo
        }
    }
    
    static var openAppWhenRun: Bool = false
    
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard amount > 0 else {
            return .result(dialog: "金額は1円以上で指定してください。")
        }
        
        await addExpense()
        
        let formatted = formatCurrency(amount)
        return .result(dialog: "\(category)として\(formatted)を記録しました。")
    }
    
    @MainActor
    private func addExpense() {
        let catName = category.isEmpty ? "その他" : category
        // カテゴリ名からIDを解決（なければ作成）
        let cat = DataStore.shared.createCategoryIfNeeded(name: catName, type: .expense)
        let tx = Transaction(
            date: Date(),
            type: .expense,
            amount: amount,
            categoryId: cat?.id,
            originalCategoryName: cat == nil ? catName : nil,
            memo: memo
        )
        DataStore.shared.addTransaction(tx)
    }
    
    private func formatCurrency(_ amount: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        let str = formatter.string(from: NSNumber(value: amount)) ?? "0"
        return "\(str)円"
    }
}

/// 収入を記録するショートカット
struct AddIncomeIntent: AppIntent {
    static var title: LocalizedStringResource = "収入を記録"
    static var description = IntentDescription("新しい収入を家計簿に記録します")
    
    @Parameter(title: "金額")
    var amount: Int
    
    @Parameter(title: "カテゴリ", default: "その他")
    var category: String
    
    @Parameter(title: "メモ", default: "")
    var memo: String
    
    static var parameterSummary: some ParameterSummary {
        Summary("￥\(\.$amount) を \(\.$category) として記録") {
            \.$memo
        }
    }
    
    static var openAppWhenRun: Bool = false
    
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard amount > 0 else {
            return .result(dialog: "金額は1円以上で指定してください。")
        }
        
        await addIncome()
        
        let formatted = formatCurrency(amount)
        return .result(dialog: "\(category)として\(formatted)の収入を記録しました。")
    }
    
    @MainActor
    private func addIncome() {
        let catName = category.isEmpty ? "その他" : category
        // カテゴリ名からIDを解決（なければ作成）
        let cat = DataStore.shared.createCategoryIfNeeded(name: catName, type: .income)
        let tx = Transaction(
            date: Date(),
            type: .income,
            amount: amount,
            categoryId: cat?.id,
            originalCategoryName: cat == nil ? catName : nil,
            memo: memo
        )
        DataStore.shared.addTransaction(tx)
    }
    
    private func formatCurrency(_ amount: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        let str = formatter.string(from: NSNumber(value: amount)) ?? "0"
        return "\(str)円"
    }
}

/// 家計簿を開くショートカット
struct OpenKakeiboIntent: AppIntent {
    static var title: LocalizedStringResource = "家計簿を開く"
    static var description = IntentDescription("家計簿アプリを開きます")
    
    static var openAppWhenRun: Bool = true
    
    func perform() async throws -> some IntentResult {
        return .result()
    }
}

// MARK: - App Shortcuts Provider

struct KakeiboShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: GetTodayExpenseIntent(),
            phrases: [
                "今日の支出を\(.applicationName)で確認",
                "\(.applicationName)で今日いくら使った",
                "\(.applicationName)で今日の支出"
            ],
            shortTitle: "今日の支出",
            systemImageName: "yensign.circle"
        )
        
        AppShortcut(
            intent: GetMonthSummaryIntent(),
            phrases: [
                "今月の収支を\(.applicationName)で確認",
                "\(.applicationName)で今月の家計簿",
                "\(.applicationName)で今月の収支"
            ],
            shortTitle: "今月の収支",
            systemImageName: "chart.bar"
        )
        
        AppShortcut(
            intent: AddExpenseIntent(),
            phrases: [
                "\(.applicationName)に支出を記録",
                "\(.applicationName)で支出を記録",
                "\(.applicationName)でお金を使った"
            ],
            shortTitle: "支出を記録",
            systemImageName: "minus.circle"
        )
        
        AppShortcut(
            intent: AddIncomeIntent(),
            phrases: [
                "\(.applicationName)に収入を記録",
                "\(.applicationName)で収入を記録",
                "\(.applicationName)でお金が入った"
            ],
            shortTitle: "収入を記録",
            systemImageName: "plus.circle"
        )
    }
}
