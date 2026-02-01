import Foundation
import SwiftUI
import Combine
import LocalAuthentication
import Security

class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var monthStartDay: Int {
        didSet { UserDefaults.standard.set(monthStartDay, forKey: "monthStartDay") }
    }

    @Published var weekendHolidayHandling: WeekendHolidayHandling {
        didSet { UserDefaults.standard.set(weekendHolidayHandling.rawValue, forKey: "weekendHolidayHandling") }
    }

    @Published var yearStartMonth: YearStartMonth {
        didSet { UserDefaults.standard.set(yearStartMonth.rawValue, forKey: "yearStartMonth") }
    }

    @Published var weekStartDay: Int {
        didSet { UserDefaults.standard.set(weekStartDay, forKey: "weekStartDay") }
    }

    @Published var sameDaySortOrder: SameDaySortOrder {
        didSet { UserDefaults.standard.set(sameDaySortOrder.rawValue, forKey: "sameDaySortOrder") }
    }

    @Published var showPreviousBalance: Bool {
        didSet { UserDefaults.standard.set(showPreviousBalance, forKey: "showPreviousBalance") }
    }

    @Published var reminderEnabled: Bool {
        didSet { UserDefaults.standard.set(reminderEnabled, forKey: "reminderEnabled") }
    }

    @Published var reminderTime: Date {
        didSet { UserDefaults.standard.set(reminderTime, forKey: "reminderTime") }
    }

    @Published var enabledGraphTypes: Set<GraphType> {
        didSet {
            let rawValues = enabledGraphTypes.map { $0.rawValue }
            UserDefaults.standard.set(rawValues, forKey: "enabledGraphTypes")
        }
    }

    @Published var graphTypeOrder: [GraphType] {
        didSet {
            let rawValues = graphTypeOrder.map { $0.rawValue }
            UserDefaults.standard.set(rawValues, forKey: "graphTypeOrder")
        }
    }
    
    // MARK: - App Lock Settings
    
    @Published var appLockEnabled: Bool {
        didSet { UserDefaults.standard.set(appLockEnabled, forKey: "appLockEnabled") }
    }
    
    @Published var lockOnBackground: Bool {
        didSet { UserDefaults.standard.set(lockOnBackground, forKey: "lockOnBackground") }
    }

    private init() {
        let savedMonthStartDay = UserDefaults.standard.integer(forKey: "monthStartDay")
        self.monthStartDay = savedMonthStartDay == 0 ? 1 : savedMonthStartDay

        let weekendRaw = UserDefaults.standard.string(forKey: "weekendHolidayHandling") ?? "none"
        self.weekendHolidayHandling = WeekendHolidayHandling(rawValue: weekendRaw) ?? .none

        let yearStartRaw = UserDefaults.standard.string(forKey: "yearStartMonth") ?? "january"
        self.yearStartMonth = YearStartMonth(rawValue: yearStartRaw) ?? .january

        let savedWeekStartDay = UserDefaults.standard.integer(forKey: "weekStartDay")
        self.weekStartDay = savedWeekStartDay == 0 ? 1 : savedWeekStartDay

        let sortOrderRaw = UserDefaults.standard.string(forKey: "sameDaySortOrder") ?? "createdDesc"
        self.sameDaySortOrder = SameDaySortOrder(rawValue: sortOrderRaw) ?? .createdDesc

        self.showPreviousBalance = UserDefaults.standard.bool(forKey: "showPreviousBalance")

        self.reminderEnabled = UserDefaults.standard.bool(forKey: "reminderEnabled")
        self.reminderTime = UserDefaults.standard.object(forKey: "reminderTime") as? Date
        ?? Calendar.current.date(from: DateComponents(hour: 21, minute: 0)) ?? Date()

        if let savedGraphTypes = UserDefaults.standard.array(forKey: "enabledGraphTypes") as? [String] {
            self.enabledGraphTypes = Set(savedGraphTypes.compactMap { GraphType(rawValue: $0) })
        } else {
            self.enabledGraphTypes = Set(GraphType.allCases)
        }

        if let savedOrder = UserDefaults.standard.array(forKey: "graphTypeOrder") as? [String] {
            self.graphTypeOrder = savedOrder.compactMap { GraphType(rawValue: $0) }
        } else {
            self.graphTypeOrder = GraphType.allCases
        }
        
        // App Lock
        self.appLockEnabled = UserDefaults.standard.bool(forKey: "appLockEnabled")
        self.lockOnBackground = UserDefaults.standard.bool(forKey: "lockOnBackground")
    }
}

enum WeekendHolidayHandling: String, CaseIterable, Identifiable {
    case none = "none"
    case before = "before"
    case after = "after"

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .none: return "何もしない"
        case .before: return "直前の平日"
        case .after: return "直後の平日"
        }
    }
}

enum YearStartMonth: String, CaseIterable, Identifiable {
    case january = "january"
    case april = "april"

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .january: return "1月1日"
        case .april: return "4月1日"
        }
    }
}

enum SameDaySortOrder: String, CaseIterable, Identifiable {
    case createdDesc = "createdDesc"
    case createdAsc = "createdAsc"
    case amountDesc = "amountDesc"
    case amountAsc = "amountAsc"

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .createdDesc: return "作成日順、新しいものが上"
        case .createdAsc: return "作成日順、新しいものが下"
        case .amountDesc: return "金額順、大きいものが上"
        case .amountAsc: return "金額順、大きいものが下"
        }
    }
    
    var shortDisplayName: String {
        switch self {
        case .createdDesc: return "新しい順"
        case .createdAsc: return "古い順"
        case .amountDesc: return "金額大→小"
        case .amountAsc: return "金額小→大"
        }
    }
}

enum GraphType: String, CaseIterable, Identifiable {
    case expense = "expense"
    case income = "income"
    case savings = "savings"
    case yearlyExpense = "yearlyExpense"
    case yearlyIncome = "yearlyIncome"
    case incomeTrend = "incomeTrend"
    case budget = "budget"

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .expense: return "支出"
        case .income: return "収入"
        case .savings: return "貯金額"
        case .yearlyExpense: return "年間支出"
        case .yearlyIncome: return "年間収入"
        case .incomeTrend: return "収入推移"
        case .budget: return "予算"
        }
    }
}
