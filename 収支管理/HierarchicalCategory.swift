import Foundation
import SwiftUI

// MARK: - CategoryGroup（大分類）

/// カテゴリの大分類（生活、移動、娯楽 等）
struct CategoryGroup: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var type: TransactionType
    var order: Int
    var colorHex: String?
    
    init(
        id: UUID = UUID(),
        name: String,
        type: TransactionType,
        order: Int = 0,
        colorHex: String? = nil
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.order = order
        self.colorHex = colorHex
    }
    
    var color: Color {
        if let hex = colorHex {
            return Color(hex: hex)
        }
        return Color.gray
    }
}

// MARK: - CategoryItem（中分類）

/// カテゴリの中分類（食費、日用品 等）
/// 既存のCategoryと互換性を維持しつつ、groupIdで大分類に紐づく
struct CategoryItem: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var groupId: UUID
    var type: TransactionType
    var order: Int
    var colorHex: String
    
    init(
        id: UUID = UUID(),
        name: String,
        groupId: UUID,
        type: TransactionType,
        order: Int = 0,
        colorHex: String = "#607D8B"
    ) {
        self.id = id
        self.name = name
        self.groupId = groupId
        self.type = type
        self.order = order
        self.colorHex = colorHex
    }
    
    var color: Color {
        Color(hex: colorHex)
    }
    
    /// 既存Categoryとの互換変換
    func toCategory() -> Category {
        Category(id: id, name: name, colorHex: colorHex, type: type, order: order)
    }
    
    /// 既存Categoryからの変換
    static func from(_ category: Category, groupId: UUID) -> CategoryItem {
        CategoryItem(
            id: category.id,
            name: category.name,
            groupId: groupId,
            type: category.type,
            order: category.order,
            colorHex: category.colorHex
        )
    }
}

// MARK: - Default Hierarchical Categories

/// デフォルトの階層カテゴリ定義
struct DefaultHierarchicalCategories {
    
    // MARK: - 支出グループ
    
    static let expenseGroups: [(name: String, items: [(name: String, color: String)])] = [
        ("生活", [
            ("食費", "#4CAF50"),
            ("外食", "#43A047"),
            ("コンビニ", "#81C784"),
            ("スーパー", "#66BB6A"),
            ("デリバリー", "#A5D6A7"),
            ("カフェ", "#8D6E63"),
            ("おやつ・パン", "#A1887F"),
            ("日用品", "#2196F3"),
            ("ドラッグストア", "#64B5F6"),
            ("雑貨", "#90CAF9"),
            ("家賃", "#795548"),
            ("水道光熱費", "#00BCD4"),
            ("通信費", "#9C27B0"),
            ("保険", "#009688"),
            ("医療費", "#F44336"),
        ]),
        ("買い物", [
            ("Amazon", "#FF9900"),
            ("通販", "#FFB74D"),
            ("百貨店", "#FB8C00"),
            ("衣服", "#673AB7"),
            ("美容・理容", "#EC407A"),
            ("家具・インテリア", "#EF6C00"),
            ("中古・買取", "#F57C00"),
        ]),
        ("移動", [
            ("交通費", "#FF9800"),
            ("電車・駅", "#FF6F00"),
            ("タクシー", "#FFB74D"),
            ("ガソリン", "#FF5722"),
            ("駐車場", "#BF360C"),
            ("高速道路", "#E65100"),
        ]),
        ("娯楽", [
            ("娯楽", "#E91E63"),
            ("サブスク・デジタル", "#BA68C8"),
            ("イベント", "#F06292"),
            ("書籍・教育", "#3F51B5"),
        ]),
        ("お金関連", [
            ("手数料", "#455A64"),
            ("税金", "#607D8B"),
            ("奨学金返済", "#1A237E"),
            ("返済・ローン", "#263238"),
            ("カード引落", "#546E7A"),
            ("個人送金", "#F06292"),
            ("チャージ", "#90A4AE"),
            ("現金入出金", "#78909C"),
        ]),
        ("未分類", [
            ("その他", "#9E9E9E"),
        ]),
    ]
    
    // MARK: - 収入グループ
    
    static let incomeGroups: [(name: String, items: [(name: String, color: String)])] = [
        ("給与収入", [
            ("給与", "#4CAF50"),
            ("賞与", "#8BC34A"),
            ("失業保険", "#DCE775"),
        ]),
        ("その他収入", [
            ("副業", "#CDDC39"),
            ("投資", "#FFC107"),
            ("利息", "#81C784"),
            ("ポイント還元", "#FFCA28"),
            ("還付金", "#AED581"),
            ("受け取り", "#B3E5FC"),
            ("チャージ", "#CFD8DC"),
        ]),
        ("未分類", [
            ("その他", "#607D8B"),
        ]),
    ]
    
    /// デフォルトの大分類と中分類を生成
    static func createDefaults(for type: TransactionType) -> (groups: [CategoryGroup], items: [CategoryItem]) {
        let groupDefs = type == .expense ? expenseGroups : incomeGroups
        
        var groups: [CategoryGroup] = []
        var items: [CategoryItem] = []
        
        for (groupIndex, groupDef) in groupDefs.enumerated() {
            let group = CategoryGroup(
                name: groupDef.name,
                type: type,
                order: groupIndex
            )
            groups.append(group)
            
            for (itemIndex, itemDef) in groupDef.items.enumerated() {
                let item = CategoryItem(
                    name: itemDef.name,
                    groupId: group.id,
                    type: type,
                    order: itemIndex,
                    colorHex: itemDef.color
                )
                items.append(item)
            }
        }
        
        return (groups, items)
    }
    
    /// 中分類名から所属すべき大分類名を検索
    static func findGroupName(for itemName: String, type: TransactionType) -> String? {
        let groupDefs = type == .expense ? expenseGroups : incomeGroups
        
        for groupDef in groupDefs {
            if groupDef.items.contains(where: { $0.name == itemName }) {
                return groupDef.name
            }
        }
        return nil
    }
}
