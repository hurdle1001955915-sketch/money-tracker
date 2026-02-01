import Vision
import UIKit
import Combine

// MARK: - Receipt Parsing Models

struct ReceiptParseResult: Equatable {
    var storeName: String?
    var date: Date?
    var totalAmount: Int?
}

@MainActor
final class ReceiptParser: ObservableObject {
    @Published var isProcessing: Bool = false
    @Published var error: String?
    @Published var result: ReceiptParseResult?

    /// Parse receipt info from a selected image using Vision framework.
    func parseReceipt(from image: UIImage) async {
        guard !isProcessing, let cgImage = image.cgImage else { return }

        isProcessing = true
        defer { isProcessing = false }
        error = nil
        result = nil

        do {
            let extractedText = try await recognizeText(from: cgImage)
            let parsedResult = extractInformation(from: extractedText)
            self.result = parsedResult
        } catch {
            self.error = "読み取りに失敗しました: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Vision OCR
    
    private func recognizeText(from image: CGImage) async throws -> [String] {
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: [])
                    return
                }
                // 信頼度の高い候補を採用
                let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                continuation.resume(returning: lines)
            }
            
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["ja-JP", "en-US"]
            request.usesLanguageCorrection = true
            
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    // MARK: - Information Extraction

    private func extractInformation(from lines: [String]) -> ReceiptParseResult {
        var storeName: String?
        var date: Date?
        var totalAmount: Int?

        // 全文検索用
        let fullText = lines.joined(separator: "\n")

        // 1. 店舗名の抽出（既知の店舗パターンを優先）
        storeName = extractKnownStoreName(from: fullText, lines: lines)

        // 2. 金額の抽出
        // パターン: "合計 1,234", "合計 ¥1,234", "合 計 \1,234" 等
        // 合計の文字を見つけて、その後の数字を取得するのが確実
        if let amount = extractAmount(from: fullText) {
            totalAmount = amount
        } else {
            // "合計"が見つからない場合、金額候補から最大値を探す
            totalAmount = extractMaxAmountCandidate(lines)
        }

        // 3. 日付の抽出
        // パターン: 2024年1月1日, 2024/01/01, 2024-01-01
        date = extractDate(from: fullText)

        return ReceiptParseResult(storeName: storeName, date: date, totalAmount: totalAmount)
    }

    // MARK: - Known Store Patterns

    /// 日本の主要チェーン店パターン
    private static let knownStorePatterns: [(pattern: String, name: String)] = [
        // コンビニ
        ("セブン.?イレブン|セブンーイレブン|7-ELEVEN|7-eleven|SEVEN.?ELEVEN", "セブンイレブン"),
        ("ファミリーマート|FamilyMart|FAMILYMART", "ファミリーマート"),
        ("ローソン|LAWSON|Lawson", "ローソン"),
        ("ミニストップ|MINISTOP", "ミニストップ"),
        ("デイリーヤマザキ|Daily.?Yamazaki", "デイリーヤマザキ"),
        ("ニューデイズ|NewDays|NEWDAYS", "ニューデイズ"),

        // スーパー
        ("イオン|AEON|ÆON", "イオン"),
        ("イトーヨーカドー|イトーヨーカ堂|Ito.?Yokado", "イトーヨーカドー"),
        ("西友|SEIYU|Seiyu", "西友"),
        ("ライフ|LIFE", "ライフ"),
        ("マルエツ|maruetsu", "マルエツ"),
        ("サミット|SUMMIT", "サミット"),
        ("オーケー|OK|OKストア", "オーケー"),
        ("業務スーパー|業スー", "業務スーパー"),
        ("コストコ|COSTCO|Costco", "コストコ"),
        ("マックスバリュ|MaxValu", "マックスバリュ"),
        ("ダイエー|Daiei", "ダイエー"),
        ("いなげや|Inageya", "いなげや"),
        ("まいばすけっと|my.?basket", "まいばすけっと"),

        // ドラッグストア
        ("マツモトキヨシ|matsukiyo|マツキヨ", "マツモトキヨシ"),
        ("ウエルシア|welcia|WELCIA", "ウエルシア"),
        ("サンドラッグ|SUN.?DRUG|SUNDRUG", "サンドラッグ"),
        ("ツルハドラッグ|TSURUHA|ツルハ", "ツルハドラッグ"),
        ("スギ薬局|スギドラッグ|SUGI", "スギ薬局"),
        ("ココカラファイン|cocokara|COCOKARA", "ココカラファイン"),
        ("クリエイト|CREATE.?SD", "クリエイト"),

        // 家電量販店
        ("ヨドバシカメラ|Yodobashi|YODOBASHI", "ヨドバシカメラ"),
        ("ビックカメラ|BIC.?CAMERA|BICCAMERA", "ビックカメラ"),
        ("ヤマダ電機|ヤマダデンキ|YAMADA", "ヤマダ電機"),
        ("ケーズデンキ|K'?s.?denki|KSDENKI", "ケーズデンキ"),
        ("エディオン|EDION", "エディオン"),
        ("ノジマ|nojima|NOJIMA", "ノジマ"),

        // 100円ショップ
        ("ダイソー|DAISO|Daiso", "ダイソー"),
        ("セリア|Seria|SERIA", "セリア"),
        ("キャンドゥ|Can.?Do|CANDO", "キャンドゥ"),

        // ホームセンター
        ("カインズ|CAINZ|Cainz", "カインズ"),
        ("コーナン|KOHNAN", "コーナン"),
        ("ニトリ|NITORI", "ニトリ"),
        ("ドン・キホーテ|ドンキホーテ|DON.?QUIJOTE|ドンキ", "ドン・キホーテ"),

        // 飲食店
        ("スターバックス|STARBUCKS|Starbucks", "スターバックス"),
        ("ドトールコーヒー|DOUTOR|ドトール", "ドトール"),
        ("マクドナルド|McDonald|MCDONALD", "マクドナルド"),
        ("モスバーガー|MOS.?BURGER|MOSBURGER", "モスバーガー"),
        ("吉野家|YOSHINOYA", "吉野家"),
        ("すき家|SUKIYA|すきや", "すき家"),
        ("松屋|MATSUYA", "松屋"),
        ("サイゼリヤ|SAIZERIYA|Saizeriya", "サイゼリヤ"),
        ("ガスト|GUSTO|Gusto", "ガスト"),
        ("デニーズ|Denny'?s|DENNYS", "デニーズ"),
        ("ジョナサン|Jonathan|JONATHAN", "ジョナサン"),
        ("バーミヤン|Bamiyan|BAMIYAN", "バーミヤン"),
        ("ケンタッキー|KFC|Kentucky", "ケンタッキー"),
        ("丸亀製麺|MARUGAME", "丸亀製麺"),
        ("CoCo壱番屋|ココイチ|COCOICHI", "CoCo壱番屋"),

        // アパレル・雑貨
        ("ユニクロ|UNIQLO|Uniqlo", "ユニクロ"),
        ("GU|ジーユー", "GU"),
        ("無印良品|MUJI|Muji", "無印良品"),
        ("しまむら|SHIMAMURA", "しまむら"),

        // 書店
        ("紀伊國屋書店|KINOKUNIYA", "紀伊國屋書店"),
        ("TSUTAYA|ツタヤ|蔦屋", "TSUTAYA"),
        ("ブックオフ|BOOK.?OFF|BOOKOFF", "ブックオフ"),
    ]

    /// 既知の店舗パターンから店舗名を抽出
    private func extractKnownStoreName(from fullText: String, lines: [String]) -> String? {
        // 1. 既知パターンでマッチを試みる
        for (pattern, name) in Self.knownStorePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
               regex.firstMatch(in: fullText, options: [], range: NSRange(location: 0, length: (fullText as NSString).length)) != nil {
                return name
            }
        }

        // 2. 既知パターンにマッチしない場合、1〜3行目から推定
        for i in 0..<min(lines.count, 5) {
            let line = lines[i].trimmingCharacters(in: .whitespaces)
            // 除外条件: 電話番号っぽい、住所っぽい、短すぎる、日付っぽい
            if isPhoneNumber(line) || isAddress(line) || line.count < 2 { continue }
            if isDateLine(line) || isSystemLine(line) { continue }
            // 店名らしき行を返す
            return line
        }

        return nil
    }

    private func isDateLine(_ text: String) -> Bool {
        let pattern = "\\d{4}[/年-]\\d{1,2}[/月-]\\d{1,2}"
        return text.range(of: pattern, options: .regularExpression) != nil
    }

    private func isSystemLine(_ text: String) -> Bool {
        let systemWords = ["再発行", "領収書", "レシート", "明細", "登録", "No.", "伝票"]
        return systemWords.contains(where: { text.contains($0) })
    }
    
    // MARK: - Regex Helpers
    
    private func isPhoneNumber(_ text: String) -> Bool {
        // 簡易チェック: 数字とハイフンだけで構成されている、または "TEL" を含む
        let digitCount = text.filter { $0.isNumber }.count
        if digitCount > 8 && (text.contains("-") || text.uppercased().contains("TEL")) {
            return true
        }
        return false
    }
    
    private func isAddress(_ text: String) -> Bool {
        // "県","市","区","町","村"などが含まれ、かつ数字が含まれる
        let indicators = ["県", "市", "区", "町", "村", "丁目"]
        if indicators.contains(where: { text.contains($0) }) && text.rangeOfCharacter(from: .decimalDigits) != nil {
            return true
        }
        return false
    }
    
    private func extractAmount(from text: String) -> Int? {
        // 優先度の高いパターン順に試行
        // 1. 税込合計（最優先）
        if let amount = extractWithPattern(text, pattern: "(税込.{0,3}合計|税込).{0,5}[¥￥]?\\s*([0-9,]+)") {
            return amount
        }

        // 2. 総合計・お支払い合計
        if let amount = extractWithPattern(text, pattern: "(総合計|お支払い?.?合計|お買上げ.?合計).{0,10}[¥￥]?\\s*([0-9,]+)") {
            return amount
        }

        // 3. 一般的な合計パターン（より広範囲）
        let generalPatterns = [
            "(合計|合\\s+計|小計|お支払|支払計|請求金額|ご請求|売上金額|現計).{0,10}[¥￥]?\\s*([0-9,]+)",
            "[¥￥]\\s*([0-9,]+)\\s*(円|合計|計)",
            "([0-9,]+)\\s*円\\s*(税込|込)",
        ]

        for pattern in generalPatterns {
            if let amount = extractWithPattern(text, pattern: pattern) {
                return amount
            }
        }

        return nil
    }

    /// 正規表現パターンで金額を抽出（最後のマッチを優先）
    private func extractWithPattern(_ text: String, pattern: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let nsString = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))

        // 後ろの方にあるマッチ（最終的な合計）を優先
        if let match = matches.last {
            // 金額部分を探す（グループ2を優先、なければグループ1）
            for groupIdx in (1..<match.numberOfRanges).reversed() {
                let range = match.range(at: groupIdx)
                if range.location != NSNotFound {
                    let candidate = nsString.substring(with: range)
                    let normalized = candidate.replacingOccurrences(of: ",", with: "")
                    if let amount = Int(normalized), amount > 0 {
                        return amount
                    }
                }
            }
        }
        return nil
    }

    /// 金額候補から最大値を抽出（フォールバック）
    private func extractMaxAmountCandidate(_ lines: [String]) -> Int? {
        var candidates: [Int] = []

        // 金額っぽいパターンを探す（¥記号付き、または「円」付き）
        let amountPattern = "[¥￥]\\s*([0-9,]+)|([0-9,]+)\\s*円"
        guard let regex = try? NSRegularExpression(pattern: amountPattern, options: []) else { return nil }

        for line in lines {
            // 除外: ポイント、番号、バーコード関連
            let lowerLine = line.lowercased()
            if lowerLine.contains("ポイント") || lowerLine.contains("point") ||
               lowerLine.contains("no.") || lowerLine.contains("番号") ||
               lowerLine.contains("レジ") || lowerLine.contains("担当") {
                continue
            }

            let nsLine = line as NSString
            let matches = regex.matches(in: line, options: [], range: NSRange(location: 0, length: nsLine.length))

            for match in matches {
                for groupIdx in 1..<match.numberOfRanges {
                    let range = match.range(at: groupIdx)
                    if range.location != NSNotFound {
                        let candidate = nsLine.substring(with: range)
                        let normalized = candidate.replacingOccurrences(of: ",", with: "")
                        if let amount = Int(normalized), amount >= 100, amount <= 1_000_000 {
                            candidates.append(amount)
                        }
                    }
                }
            }
        }

        // 最大値を返す（複数の個別金額より合計が大きいはず）
        return candidates.max()
    }
    
    private func extractDate(from text: String) -> Date? {
        // YYYY/MM/DD, YYYY年MM月DD日, YYYY-MM-DD
        let pattern = "(\\d{4})[/年-](\\d{1,2})[/月-](\\d{1,2})"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        
        let nsString = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))
        
        // 日付も複数ある場合があるが、最初の方（購入日時）を優先するか、当日であれば採用
        for match in matches {
            if match.numberOfRanges >= 4 {
                let yStr = nsString.substring(with: match.range(at: 1))
                let mStr = nsString.substring(with: match.range(at: 2))
                let dStr = nsString.substring(with: match.range(at: 3))
                
                if let y = Int(yStr), let m = Int(mStr), let d = Int(dStr) {
                    var comps = DateComponents()
                    comps.year = y
                    comps.month = m
                    comps.day = d
                    if let date = Calendar.current.date(from: comps) {
                        return date
                    }
                }
            }
        }
        return nil
    }
}
