import Foundation
import SwiftUI
import UIKit

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
    
    static let themeBlue = Color(uiColor: UIColor { trait in
        return trait.userInterfaceStyle == .dark ? UIColor(hex: "#536DFE") : UIColor(hex: "#1a237e")
    })
    
    // Semantic Colors
    static let primaryBackground = Color(uiColor: .systemBackground)
    static let secondaryBackground = Color(uiColor: .secondarySystemBackground)
    
    static let categoryColors: [String] = [
        "#F44336", "#E91E63", "#9C27B0", "#673AB7", "#3F51B5",
        "#2196F3", "#03A9F4", "#00BCD4", "#009688", "#4CAF50",
        "#8BC34A", "#CDDC39", "#FFEB3B", "#FFC107", "#FF9800",
        "#FF5722", "#795548", "#9E9E9E", "#607D8B"
    ]
}

extension UIColor {
    convenience init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            red: CGFloat(r) / 255,
            green: CGFloat(g) / 255,
            blue: CGFloat(b) / 255,
            alpha: CGFloat(a) / 255
        )
    }
}

extension Date {
    var startOfDay: Date {
        Calendar.current.startOfDay(for: self)
    }
    
    var endOfDay: Date {
        var components = DateComponents()
        components.day = 1
        components.second = -1
        return Calendar.current.date(byAdding: components, to: startOfDay) ?? self
    }
    
    var startOfMonth: Date {
        let components = Calendar.current.dateComponents([.year, .month], from: self)
        return Calendar.current.date(from: components) ?? self
    }
    
    var endOfMonth: Date {
        Calendar.current.date(byAdding: DateComponents(month: 1, day: -1), to: startOfMonth) ?? self
    }
    
    func isSameDay(as date: Date) -> Bool {
        Calendar.current.isDate(self, inSameDayAs: date)
    }
    
    func isSameMonth(as date: Date) -> Bool {
        let calendar = Calendar.current
        return calendar.component(.year, from: self) == calendar.component(.year, from: date) &&
               calendar.component(.month, from: self) == calendar.component(.month, from: date)
    }
}

extension Date {
    var month: Int { Calendar.current.component(.month, from: self) }
    var day: Int { Calendar.current.component(.day, from: self) }
    var dayOfWeekString: String {
        let weekday = Calendar.current.component(.weekday, from: self) // 1=Sun ... 7=Sat
        let names = ["日","月","火","水","木","金","土"]
        return names[(weekday - 1 + 7) % 7]
    }
    var yearMonthString: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "yyyy年M月"
        return f.string(from: self)
    }
    var shortDateString: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "yyyy/MM/dd"
        return f.string(from: self)
    }
    var fullDateString: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "yyyy年M月d日(E)"
        return f.string(from: self)
    }
    static func daysInMonth(year: Int, month: Int) -> Int {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        let cal = Calendar.current
        let date = cal.date(from: comps) ?? Date()
        return cal.range(of: .day, in: .month, for: date)?.count ?? 30
    }
    static func createDate(year: Int, month: Int, day: Int) -> Date {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        return Calendar.current.date(from: comps) ?? Date()
    }
}

extension Int {
    var currencyFormatted: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: self)) ?? "\(self)"
    }
    
    var currencyFormattedShort: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: self)) ?? "\(self)"
    }
}

// MARK: - Text Utility

/// アプリ全体で統一されたテキスト正規化処理
enum TextNormalizer {
    /// 検索やマッチング用にテキストを正規化する
    /// - Parameter input: 入力文字列
    /// - Returns: 正規化された文字列
    ///
    /// 処理内容:
    /// - 空白除去（トリミング）
    /// - 小文字化
    /// - 全角英数字/カタカナを半角に統一
    /// - 長音記号を "-" に統一
    /// - 連続する空白を1つに
    /// - 一般的な記号の揺らぎ吸収
    static func normalize(_ input: String) -> String {
        var t = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // Convert fullwidth to halfwidth (e.g., ＡＢＣ -> ABC, カ－ド -> ｶｰﾄﾞ)
        let m = NSMutableString(string: t) as CFMutableString
        CFStringTransform(m, nil, kCFStringTransformFullwidthHalfwidth, false)
        t = m as String

        // Unify long vowel marks and dashes to '-'
        // ー (Katakana-Hiragana Prolonged Sound Mark)
        // ｰ (Halfwidth Katakana-Hiragana Prolonged Sound Mark)
        // － (Fullwidth Hyphen-Minus)
        t = t.replacingOccurrences(of: "ー", with: "-")
             .replacingOccurrences(of: "ｰ", with: "-")
             .replacingOccurrences(of: "－", with: "-")

        // Collapse multiple spaces
        t = t.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

        // Unify common punctuation/variants
        // ／ (Fullwidth Solidus) -> /
        // 　 (Ideographic Space) -> space (though whitespace ref above handles this mostly, explicit check is safe)
        t = t.replacingOccurrences(of: "／", with: "/")
             .replacingOccurrences(of: "　", with: " ")

        return t.trimmingCharacters(in: .whitespaces)
    }

    /// 全角数字を半角に変換（日付パース用）
    static func normalizeFullWidthNumbers(_ input: String) -> String {
        var result = input
        let fullWidthDigits: [Character] = ["０", "１", "２", "３", "４", "５", "６", "７", "８", "９"]
        let halfWidthDigits: [Character] = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"]

        for (full, half) in zip(fullWidthDigits, halfWidthDigits) {
            result = result.replacingOccurrences(of: String(full), with: String(half))
        }
        return result
    }
}

// MARK: - Keyboard Utilities

/// キーボードを閉じる
func hideKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}

/// キーボードツールバー修飾子
extension View {
    func keyboardToolbar() -> some View {
        self.toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完了") {
                    hideKeyboard()
                }
            }
        }
    }
}

// MARK: - Lazy View

/// 遅延読み込みビュー（TabViewのパフォーマンス向上用）
struct LazyView<Content: View>: View {
    let build: () -> Content

    init(_ build: @autoclosure @escaping () -> Content) {
        self.build = build
    }

    var body: Content {
        build()
    }
}

// MARK: - Array Safe Subscript

extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}

// MARK: - ZIP Utilities

extension Data {
    /// CRC32計算（ZIP形式用）
    func crc32() -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF

        for byte in self {
            var lookup = (crc ^ UInt32(byte)) & 0xFF
            for _ in 0..<8 {
                if lookup & 1 == 1 {
                    lookup = (lookup >> 1) ^ 0xEDB88320
                } else {
                    lookup >>= 1
                }
            }
            crc = (crc >> 8) ^ lookup
        }

        return crc ^ 0xFFFFFFFF
    }
}

extension UInt32 {
    /// リトルエンディアンのバイト配列に変換
    var littleEndianBytes: [UInt8] {
        return [
            UInt8(self & 0xFF),
            UInt8((self >> 8) & 0xFF),
            UInt8((self >> 16) & 0xFF),
            UInt8((self >> 24) & 0xFF)
        ]
    }
}

extension UInt16 {
    /// リトルエンディアンのバイト配列に変換
    var littleEndianBytes: [UInt8] {
        return [
            UInt8(self & 0xFF),
            UInt8((self >> 8) & 0xFF)
        ]
    }
}

// MARK: - Week Days Helper

/// 曜日名のヘルパー（設定画面等で使用）
enum WeekDays {
    /// 曜日名の配列（日曜始まり: 1=日, 2=月, ..., 7=土）
    static let names = ["日", "月", "火", "水", "木", "金", "土"]

    /// 指定した曜日から始まる曜日名の配列を返す
    /// - Parameter startDay: 週の開始曜日（1=日曜, 2=月曜, ..., 7=土曜）
    /// - Returns: 並び替えられた曜日名の配列
    static func orderedNames(startingFrom startDay: Int) -> [String] {
        let index = (startDay - 1) % 7
        return Array(names[index...]) + Array(names[..<index])
    }
}
