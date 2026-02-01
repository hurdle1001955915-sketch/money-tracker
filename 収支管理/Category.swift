import Foundation
import SwiftUI

struct Category: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var colorHex: String
    var type: TransactionType
    var order: Int
    
    init(
        id: UUID = UUID(),
        name: String,
        colorHex: String = "#607D8B",
        type: TransactionType,
        order: Int = 0
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.type = type
        self.order = order
    }
    
    var color: Color {
        Color(hex: colorHex)
    }
}

struct DefaultCategories {
    static let expense: [(name: String, color: String)] = [
        ("食費", "#4CAF50"),
        ("スーパー", "#66BB6A"),
        ("コンビニ", "#81C784"),
        ("デリバリー", "#A5D6A7"),
        ("外食", "#43A047"),
        ("カフェ", "#8D6E63"),
        ("おやつ・パン", "#A1887F"),
        ("日用品", "#2196F3"),
        ("ドラッグストア", "#64B5F6"),
        ("雑貨", "#90CAF9"),
        ("Amazon", "#FF9900"),
        ("通販", "#FFB74D"),
        ("百貨店", "#FB8C00"),
        ("家具・インテリア", "#EF6C00"),
        ("中古・買取", "#F57C00"),
        ("交通費", "#FF9800"),
        ("タクシー", "#FFB74D"),
        ("電車・駅", "#FF6F00"),
        ("ガソリン", "#FF5722"),
        ("駐車場", "#BF360C"),
        ("高速道路", "#E65100"),
        ("娯楽", "#E91E63"),
        ("サブスク・デジタル", "#BA68C8"),
        ("イベント", "#F06292"),
        ("通信費", "#9C27B0"),
        ("水道光熱費", "#00BCD4"),
        ("家賃", "#795548"),
        ("医療費", "#F44336"),
        ("衣服", "#673AB7"),
        ("美容・理容", "#EC407A"),
        ("書籍・教育", "#3F51B5"),
        ("保険", "#009688"),
        ("税金", "#607D8B"),
        ("奨学金返済", "#1A237E"),
        ("手数料", "#455A64"),
        ("返済・ローン", "#263238"),
        ("カード引落", "#546E7A"),
        ("個人送金", "#F06292"),
        ("チャージ", "#90A4AE"),
        ("現金入出金", "#78909C"),
        ("その他", "#9E9E9E"),
    ]
    
    static let income: [(name: String, color: String)] = [
        ("給与", "#4CAF50"),
        ("賞与", "#8BC34A"),
        ("失業保険", "#DCE775"),
        ("還付金", "#AED581"),
        ("利息", "#81C784"),
        ("副業", "#CDDC39"),
        ("投資", "#FFC107"),
        ("ポイント還元", "#FFCA28"),
        ("受け取り", "#B3E5FC"),
        ("チャージ", "#CFD8DC"),
        ("その他", "#607D8B"),
    ]
    
    static func findColor(for name: String, type: TransactionType) -> String? {
        let list = type == .expense ? expense : income
        return list.first { $0.name == name }?.color
    }
    
    static func createExpenseCategories() -> [Category] {
        expense.enumerated().map { index, item in
            Category(name: item.name, colorHex: item.color, type: .expense, order: index)
        }
    }
    
    static func createIncomeCategories() -> [Category] {
        income.enumerated().map { index, item in
            Category(name: item.name, colorHex: item.color, type: .income, order: index)
        }
    }
}

