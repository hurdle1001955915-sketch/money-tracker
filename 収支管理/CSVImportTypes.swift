import Foundation
import Combine

// MARK: - CSV Import Types (single source of truth)

enum CSVImportFormat: String, CaseIterable, Identifiable {
    case appExport = "appExport"
    case resonaBank = "resonaBank"     // りそな銀行
    case amazonCard = "amazonCard"     // 三井住友カード（Amazonカード等）
    case payPay = "payPay"             // PayPay
    case bankGeneric = "bankGeneric"
    case cardGeneric = "cardGeneric"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .appExport: return "このアプリのCSV"
        case .resonaBank: return "りそな銀行CSV"
        case .amazonCard: return "三井住友カード（Amazon等）"
        case .payPay: return "PayPay CSV"
        case .bankGeneric: return "銀行CSV（汎用）"
        case .cardGeneric: return "クレカCSV（汎用）"
        }
    }
    
    var description: String {
        switch self {
        case .appExport: return "このアプリでエクスポートしたCSV（ヘッダー: 日付,種類,金額,カテゴリ,メモ）"
        case .resonaBank: return "りそな銀行の入出金明細CSV"
        case .amazonCard: return "三井住友カード（Vpass）からダウンロードしたCSV"
        case .payPay: return "PayPayアプリからダウンロードしたCSV"
        case .bankGeneric: return "一般的な銀行の入出金明細CSV（日付, 入金, 出金など）"
        case .cardGeneric: return "一般的なクレジットカードの利用明細CSV"
        }
    }
}

struct CSVImportResult {
    /// 正常に追加できた件数
    var added: Int
    /// 何らかの理由でスキップされた件数（重複 + 不正行など）
    var skipped: Int
    /// 読み取り失敗などのエラー詳細（表示用）
    var errors: [String]

    /// 今回のインポートで追加された取引ID（取り消し用）
    var addedTransactionIds: [UUID]
    /// 重複と判断してスキップされた件数
    var duplicateSkipped: Int
    /// 解析できずにスキップされた件数
    var invalidSkipped: Int
    /// 未分類（カテゴリが「その他」）のサンプル（表示用）
    var unclassifiedSamples: [String]
    
    /// Phase1: このインポートの一意識別子（ロールバック用）
    var importId: String

    init(
        added: Int,
        skipped: Int,
        errors: [String],
        addedTransactionIds: [UUID] = [],
        duplicateSkipped: Int = 0,
        invalidSkipped: Int = 0,
        unclassifiedSamples: [String] = [],
        importId: String = ""
    ) {
        self.added = added
        self.skipped = skipped
        self.errors = errors
        self.addedTransactionIds = addedTransactionIds
        self.duplicateSkipped = duplicateSkipped
        self.invalidSkipped = invalidSkipped
        self.unclassifiedSamples = unclassifiedSamples
        self.importId = importId
    }

    struct Summary {
        var totalProcessed: Int
        var successRate: Double
    }

    /// 画面表示用の集計
    var summary: Summary {
        let total = added + duplicateSkipped + invalidSkipped
        let rate = total > 0 ? (Double(added) / Double(total) * 100.0) : 0
        return Summary(totalProcessed: total, successRate: rate)
    }
}

/// ユーザーが列番号を指定するためのマッピング
struct CSVManualMapping: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var name: String?
    var formatHint: String?
    
    var dateIndex: Int?
    var amountIndex: Int?
    var debitIndex: Int?
    var creditIndex: Int?
    var typeIndex: Int?
    var memoIndex: Int?
    var categoryIndex: Int?
    
    // テンプレート作成用
    static func template(for format: CSVImportFormat) -> CSVManualMapping {
        var m = CSVManualMapping()
        m.formatHint = format.rawValue
        
        let map = ColumnMap.build(fromHeader: [], format: format)
        m.dateIndex = map.dateIndex
        m.amountIndex = map.amountIndex
        m.debitIndex = map.debitIndex
        m.creditIndex = map.creditIndex
        m.typeIndex = map.typeIndex
        m.memoIndex = map.memoIndex
        m.categoryIndex = map.categoryIndex
        
        return m
    }
}

// MARK: - Text Normalizer

// TextNormalizer moved to Extensions.swift

// MARK: - CSV Parser

/// ダブルクォート対応の簡易CSVパーサ
enum CSVParser {
    static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false

        let chars = Array(text)

        func endField() {
            row.append(field.trimmingCharacters(in: .whitespacesAndNewlines))
            field = ""
        }
        func endRow() {
            rows.append(row)
            row = []
        }

        var i = 0
        while i < chars.count {
            let c = chars[i]

            if c == "\"" {
                if inQuotes {
                    if i + 1 < chars.count && chars[i + 1] == "\"" {
                        field.append("\"")
                        i += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    inQuotes = true
                }
            } else if c == "," && !inQuotes {
                endField()
            } else if c == "\n" && !inQuotes {
                endField()
                endRow()
            } else {
                field.append(c)
            }
            i += 1
        }

        if !field.isEmpty || !row.isEmpty {
            endField()
            endRow()
        }

        // 空行を除外して返す
        return rows.filter { row in !row.allSatisfy { $0.isEmpty } }
    }
}

// MARK: - Date Parser

enum DateParser {
    static func parse(_ s: String) -> Date? {
        // まず全角数字を半角に変換
        let normalized = TextNormalizer.normalizeFullWidthNumbers(s)
        let t = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return nil }

        let fmts = [
            "yyyy/MM/dd HH:mm:ss", // PayPay
            "yyyy/MM/dd",
            "yyyy-MM-dd",
            "yyyy.M.d",
            "yyyy/MM/d",
            "yyyy/M/d",
            "yyyyMMdd",
            "MM/dd/yyyy",
            "M/d/yyyy"
        ]

        for f in fmts {
            let df = DateFormatter()
            df.locale = Locale(identifier: "ja_JP")
            df.calendar = Calendar(identifier: .gregorian)
            df.dateFormat = f
            if let d = df.date(from: t) { return d }
        }
        return nil
    }
}

// MARK: - Amount Parser

enum AmountParser {
    static func isNegative(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.contains("-") || t.contains("－") || (t.hasPrefix("(") && t.hasSuffix(")"))
    }

    static func parse(_ s: String) -> Int? {
        // まず全角数字・記号を半角に変換
        var t = TextNormalizer.normalize(s)
        t = t.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return nil }

        let negative = (t.hasPrefix("(") && t.hasSuffix(")")) || t.contains("-")

        // 不要な文字を除去
        t = t.replacingOccurrences(of: "円", with: "")
        t = t.replacingOccurrences(of: "¥", with: "")
        t = t.replacingOccurrences(of: ",", with: "")
        t = t.replacingOccurrences(of: " ", with: "")
        t = t.replacingOccurrences(of: "\u{00A0}", with: "")
        t = t.replacingOccurrences(of: "\"", with: "")
        t = t.replacingOccurrences(of: "(", with: "")
        t = t.replacingOccurrences(of: ")", with: "")
        t = t.replacingOccurrences(of: "+", with: "")
        t = t.replacingOccurrences(of: "-", with: "")

        guard let n = Int(t) else { return nil }
        return negative ? -n : n
    }
}

// MARK: - Amazon Card CSV Detector

enum AmazonCardDetector {
    /// 三井住友カード（Amazonカード等）のCSVかどうかを判定
    static func detect(rows: [[String]]) -> Bool {
        guard !rows.isEmpty else { return false }
        
        let firstRow = rows[0]
        
        // 1行目が個人情報行の場合
        if firstRow.count >= 3 {
            let normalized = TextNormalizer.normalize(firstRow.joined(separator: ",").lowercased())
            
            // カード番号マスクパターン
            let hasCardMask = normalized.contains("****")
            
            // カード名キーワード
            let cardKeywords = ["amazon", "master", "visa", "三井住友", "smbc"]
            let hasCardKeyword = cardKeywords.contains { normalized.contains($0) }
            
            // 「様」を含む
            let hasHonorific = normalized.contains("様") || normalized.contains("さま")
            
            if hasCardMask || (hasCardKeyword && hasHonorific) {
                return true
            }
        }
        
        // 2行目以降のデータ構造で判定
        if rows.count >= 2 {
            let dataRow = rows[1]
            if dataRow.count >= 6 {
                if DateParser.parse(dataRow[0]) != nil {
                    let amount1 = AmountParser.parse(dataRow[2])
                    let amount2 = AmountParser.parse(dataRow[5])
                    if amount1 != nil && amount1 == amount2 {
                        return true
                    }
                }
            }
        }
        
        return false
    }
    
    /// 個人情報行かどうか
    static func isPersonalInfoRow(_ row: [String]) -> Bool {
        if row.count >= 2 {
            let joined = row.joined(separator: ",")
            return joined.contains("****") || joined.contains("＊＊＊＊") || joined.contains("様")
        }
        return false
    }
    
    /// 合計行かどうか
    static func isTotalRow(_ row: [String]) -> Bool {
        if row.count >= 6 {
            let firstCol = row[0].trimmingCharacters(in: .whitespacesAndNewlines)
            if firstCol.isEmpty {
                if AmountParser.parse(row[5]) != nil {
                    return true
                }
            }
        }
        return false
    }
}

// MARK: - PayPay CSV Detector
enum PayPayDetector {
    static func detect(rows: [[String]]) -> Bool {
        guard let header = rows.first else { return false }
        let h = header.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        return h.contains("取引日") && h.contains("出金金額（円）") && h.contains("取引番号")
    }
}

// MARK: - Resona Bank CSV Detector
enum ResonaDetector {
    static func detect(rows: [[String]]) -> Bool {
        guard let header = rows.first else { return false }
        let h = header.joined(separator: ",").lowercased()
        
        // パターンA: 従来の厳格なキーワード（どれかがあればOKくらいにする）
        if h.contains("取扱日付") && h.contains("摘要") { return true }
        
        // パターンB: 入払区分がある（Resonaの特徴）
        if h.contains("日付") && h.contains("入払区分") { return true }
        
        return false
    }
}

// MARK: - Column Map

struct ColumnMap {
    var dateIndex: Int?
    var amountIndex: Int?
    var debitIndex: Int?
    var creditIndex: Int?
    var typeIndex: Int?
    var memoIndex: Int?
    var categoryIndex: Int?

    static func build(fromHeader header: [String], format: CSVImportFormat) -> ColumnMap {
        // Amazonカードは固定列構造
        if format == .amazonCard {
            var m = ColumnMap()
            m.dateIndex = 0
            m.memoIndex = 1
            m.amountIndex = 2
            return m
        }
        
        func find(_ candidates: [String]) -> Int? {
            for (i, h) in header.enumerated() {
                let x = h.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if candidates.contains(where: { x.contains($0.lowercased()) }) { return i }
            }
            return nil
        }

        var m = ColumnMap()

        m.dateIndex = find(["日付", "取引日", "利用日", "年月日", "取扱日付", "date", "transaction date", "posted date"])
        m.amountIndex = find(["金額", "利用金額", "支払金額", "金額（円）", "amount"])
        // 出金列（「お支払金額」は出金、「お預り金額」は入金なので分離）
        m.debitIndex = find(["出金", "出金額", "支出", "出金金額", "出金金額（円）", "お支払金額", "debit", "withdrawal"])
        // 入金列（「お預り金額」は入金）
        m.creditIndex = find(["入金", "入金額", "収入", "入金金額", "入金金額（円）", "お預り金額", "credit", "deposit"])
        m.typeIndex = find(["入出金", "区分", "種別", "入払区分", "type", "transaction type"])
        m.memoIndex = find(["メモ", "摘要", "内容", "取引内容", "店舗", "加盟店", "取引先", "description", "details", "memo"])
        m.categoryIndex = find(["カテゴリ", "カテゴリー", "category"])

        // ヘッダーがない場合
        if header.isEmpty {
            m.dateIndex = 0
            m.memoIndex = 1
            m.amountIndex = 2
        }

        return m
    }

    mutating func apply(_ m: CSVManualMapping) {
        if let v = m.dateIndex { dateIndex = v }
        if let v = m.amountIndex { amountIndex = v }
        if let v = m.debitIndex { debitIndex = v }
        if let v = m.creditIndex { creditIndex = v }
        if let v = m.typeIndex { typeIndex = v }
        if let v = m.memoIndex { memoIndex = v }
        if let v = m.categoryIndex { categoryIndex = v }
    }

    func pickDate(from row: [String]) -> String? {
        if let i = dateIndex, let v = row[safe: i], !v.isEmpty { return v }
        return row[safe: 0]
    }

    func pickMemo(from row: [String]) -> String? {
        if let i = memoIndex, let v = row[safe: i], !v.isEmpty { return v }
        return row[safe: 1]
    }

    func pickCategory(from row: [String]) -> String? {
        if let i = categoryIndex, let v = row[safe: i], !v.isEmpty { return v }
        return nil
    }

    func pickTypeAmount(from row: [String], format: CSVImportFormat) -> (TransactionType, Int)? {
        // 1) 出金/入金列が分かれてる場合
        if let d = debitIndex, let debitStr = row[safe: d],
           let debit = AmountParser.parse(debitStr), debit > 0 {
            return (.expense, debit)
        }
        if let c = creditIndex, let creditStr = row[safe: c],
           let credit = AmountParser.parse(creditStr), credit > 0 {
            return (.income, credit)
        }

        // 2) 1列金額 + 区分列
        let amountStr = (amountIndex != nil ? row[safe: amountIndex!] : nil) ?? row[safe: 2] ?? ""
        guard var amount = AmountParser.parse(amountStr) else { return nil }

        if let tIdx = typeIndex, let t = row[safe: tIdx] {
            // 半角/全角対応で正規化
            let normalizedT = TextNormalizer.normalize(t)
            // 出金キーワード（正規化済み形式）
            // 注意：「振込」は入金にも出金にも使われるので、ここでは判定しない
            if normalizedT.contains("ｼｭｯｷﾝ") ||    // 出金
               normalizedT.contains("ｼﾊﾗｲ") ||     // 支払
               normalizedT.contains("ﾋｷｵﾄｼ") ||    // 引落
               normalizedT.contains("debit") ||
               normalizedT.contains("withdraw") {
                return (.expense, abs(amount))
            }
            // 入金キーワード（正規化済み形式）
            // 「入金」「預入」「受取」など明確な入金を示すキーワードのみ
            if normalizedT.contains("ﾆｭｳｷﾝ") ||    // 入金
               normalizedT.contains("ｱｽﾞｹｲﾚ") ||   // 預入
               normalizedT.contains("ｳｹﾄﾘ") ||     // 受取
               normalizedT.contains("ﾘｿｸ") ||      // 利息
               normalizedT.contains("credit") ||
               normalizedT.contains("deposit") {
                return (.income, abs(amount))
            }
        }

        // 3) 金額の符号で判断
        if AmountParser.isNegative(amountStr) {
            amount = abs(amount)
            return (.expense, amount)
        }

        // 4) クレカCSVは基本「支出」
        if format == .cardGeneric || format == .amazonCard {
            return (.expense, abs(amount))
        }

        // 5) 銀行CSVはプラスなら収入扱い
        return (.income, abs(amount))
    }
    
    // MARK: - DataStore Helpers
    
    func pickDateValue(from row: [String]) -> Date? {
        guard let s = pickDate(from: row) else { return nil }
        return DateParser.parse(s)
    }
    
    func pickAmountFromDebitCredit(from row: [String]) -> (TransactionType, Int)? {
        if let d = debitIndex, let v = row[safe: d], let amt = AmountParser.parse(v), amt > 0 {
            return (.expense, amt)
        }
        if let c = creditIndex, let v = row[safe: c], let amt = AmountParser.parse(v), amt > 0 {
            return (.income, amt)
        }
        return nil
    }
    
    func pickAmount(from row: [String]) -> Int? {
        guard let i = amountIndex, let v = row[safe: i] else { return nil }
        return AmountParser.parse(v)
    }
    
    func pickType(from row: [String]) -> TransactionType? {
        guard let i = typeIndex, let v = row[safe: i] else { return nil }
        // 半角/全角対応で正規化
        let normalizedType = TextNormalizer.normalize(v)
        // 入金キーワード（正規化済み形式）
        if normalizedType.contains("ﾆｭｳｷﾝ") ||   // 入金
           normalizedType.contains("ｱｽﾞｹｲﾚ") ||   // 預入
           normalizedType.contains("ｳｹﾄﾘ") ||     // 受取
           normalizedType.contains("dep") ||
           normalizedType.contains("credit") {
            return .income
        }
        return .expense
    }
    
    func pickMemoString(from row: [String]) -> String {
        return pickMemo(from: row) ?? ""
    }
}

// Array subscript moved to Extensions.swift

// MARK: - CSV Format Detector

enum CSVFormatDetector {
    enum DetectionConfidence: Int, Comparable {
        case unknown = 0
        case low = 1
        case medium = 2
        case high = 3
        
        static func < (lhs: DetectionConfidence, rhs: DetectionConfidence) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }
    
    struct DetectionResult: Identifiable {
        let id = UUID()
        let format: CSVImportFormat
        let confidence: DetectionConfidence
        let reason: String
    }
    
    static func detectWithConfidence(from text: String) -> [DetectionResult] {
        var results: [DetectionResult] = []
        
        // CSV解析
        var normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        if normalized.hasPrefix("\u{FEFF}") { normalized.removeFirst() }
        let rows = CSVParser.parse(normalized)
        
        guard !rows.isEmpty else { return [] }
        
        // 1. App Export
        if isAppExport(rows) {
            results.append(DetectionResult(format: .appExport, confidence: .high, reason: "ヘッダー構成が完全一致しました"))
        }

        // 2. PayPay (Header check)
        if PayPayDetector.detect(rows: rows) {
            results.append(DetectionResult(format: .payPay, confidence: .high, reason: "PayPayのヘッダー構成と一致しました"))
        }
        
        // 3. Resona (Header check)
        if ResonaDetector.detect(rows: rows) {
            results.append(DetectionResult(format: .resonaBank, confidence: .high, reason: "りそな銀行のヘッダー構成と一致しました"))
        }

        // 4. Amazon Card (Card number mask or keyword)
        if AmazonCardDetector.detect(rows: rows) {
            results.append(DetectionResult(format: .amazonCard, confidence: .high, reason: "三井住友カードの特徴と一致しました"))
        }
        
        // 5. Bank / Card Generic
        let (hasDate, hasAmount) = checkBasicColumns(rows)
        if hasDate && hasAmount {
            // 入出金が分かれている -> 銀行っぽい
            if hasSeparateDebitCredit(rows) {
                results.append(DetectionResult(format: .bankGeneric, confidence: .medium, reason: "日付と入出金列が検出されました"))
            } else {
                results.append(DetectionResult(format: .cardGeneric, confidence: .medium, reason: "日付と金額列が検出されました"))
            }
        }
        
        return results.sorted { $0.confidence > $1.confidence }
    }
    

    
    private static func isAppExport(_ rows: [[String]]) -> Bool {
        guard let header = rows.first else { return false }
        let h = header.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        return h == ["日付", "種類", "金額", "カテゴリ", "メモ"]
    }
    
    private static func checkBasicColumns(_ rows: [[String]]) -> (Bool, Bool) {
        // 単純にヘッダーやデータから推測
        guard rows.count > 0 else { return (false, false) }
        let header = rows[0]
        let dateKeywords = ["日付", "利用日", "date"]
        let amountKeywords = ["金額", "支払い", "amount"]
        
        let hasDate = header.contains { col in dateKeywords.contains { col.contains($0) } }
        let hasAmount = header.contains { col in amountKeywords.contains { col.contains($0) } }
        
        return (hasDate, hasAmount)
    }
    
    private static func hasSeparateDebitCredit(_ rows: [[String]]) -> Bool {
        guard rows.count > 0 else { return false }
        let header = rows[0]
        let debitKeywords = ["出金", "支払"]
        let creditKeywords = ["入金", "預入"]
        
        let hasDebit = header.contains { col in debitKeywords.contains { col.contains($0) } }
        let hasCredit = header.contains { col in creditKeywords.contains { col.contains($0) } }
        
        return hasDebit && hasCredit
    }
}

// MARK: - Saved Mappings Store

@MainActor
class SavedMappingsStore: ObservableObject {
    static let shared = SavedMappingsStore()
    
    @Published private(set) var mappings: [CSVManualMapping] = []
    
    private let key = "saved_csv_mappings"
    
    private init() {
        load()
    }
    
    func save(_ mapping: CSVManualMapping) {
        if let index = mappings.firstIndex(where: { $0.id == mapping.id }) {
            mappings[index] = mapping
        } else {
            mappings.append(mapping)
        }
        persist()
    }
    
    func delete(_ mapping: CSVManualMapping) {
        mappings.removeAll { $0.id == mapping.id }
        persist()
    }
    
    private func load() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([CSVManualMapping].self, from: data) {
            mappings = decoded
        }
    }
    
    private func persist() {
        if let encoded = try? JSONEncoder().encode(mappings) {
            UserDefaults.standard.set(encoded, forKey: key)
        }
    }
}
