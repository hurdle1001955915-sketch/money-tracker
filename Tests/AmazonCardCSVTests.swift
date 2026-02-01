import XCTest
@testable import 収支管理

/// 実際のAmazonカード（三井住友）CSVデータを使ったテスト
final class AmazonCardCSVTests: XCTestCase {
    
    // 実際のCSVデータ（202508.csv の内容）
    let realCSVData = """
    井原　翔太郎　様,5334-91**-****-****,Ａｍａｚｏｎマスター
    2025/07/04,大阪第一交通堺営業所,1300,１,１,1300,
    2025/07/04,ＡＶＡＬＯＮ＊ＵＳＥＮ,14630,１,１,14630,
    2025/07/11,ＡＭＡＺＯＮ．ＣＯ．ＪＰ,816,１,１,816,
    2025/07/12,ＡＭＡＺＯＮ．ＣＯ．ＪＰ,2412,１,１,2412,
    2025/07/13,ＡＭＡＺＯＮ．ＣＯ．ＪＰ,1077,１,１,1077,
    2025/07/14,ＡＭＡＺＯＮ．ＣＯ．ＪＰ,5639,１,１,5639,
    2025/07/22,ＡＭＡＺＯＮ．ＣＯ．ＪＰ,2016,１,１,2016,
    2025/07/30,Ａｍａｚｏｎプライム会費,5900,１,１,5900,
    ,,,,,33790,
    """
    
    // MARK: - フォーマット検出
    
    func testDetectAmazonCardFormat() {
        let rows = CSVParser.parse(realCSVData)
        XCTAssertTrue(AmazonCardDetector.detect(rows: rows), "実際のAmazonカードCSVが検出されること")
    }
    
    // MARK: - 行分類
    
    func testIdentifyPersonalInfoRow() {
        let rows = CSVParser.parse(realCSVData)
        XCTAssertTrue(AmazonCardDetector.isPersonalInfoRow(rows[0]), "1行目が個人情報行として認識されること")
        XCTAssertFalse(AmazonCardDetector.isPersonalInfoRow(rows[1]), "2行目は個人情報行ではないこと")
    }
    
    func testIdentifyTotalRow() {
        let rows = CSVParser.parse(realCSVData)
        let lastRow = rows[rows.count - 1]
        XCTAssertTrue(AmazonCardDetector.isTotalRow(lastRow), "最終行が合計行として認識されること")
        XCTAssertFalse(AmazonCardDetector.isTotalRow(rows[1]), "データ行は合計行ではないこと")
    }
    
    // MARK: - データ行パース
    
    func testParseDataRow() {
        let rows = CSVParser.parse(realCSVData)
        
        // 2行目: 2025/07/04,大阪第一交通堺営業所,1300,１,１,1300,
        let row = rows[1]
        
        // 日付
        let date = DateParser.parse(row[0])
        XCTAssertNotNil(date)
        if let d = date {
            let calendar = Calendar.current
            XCTAssertEqual(calendar.component(.year, from: d), 2025)
            XCTAssertEqual(calendar.component(.month, from: d), 7)
            XCTAssertEqual(calendar.component(.day, from: d), 4)
        }
        
        // 金額
        let amount = AmountParser.parse(row[2])
        XCTAssertEqual(amount, 1300)
        
        // 店舗名（メモ）- 正規化後
        let memo = TextNormalizer.normalize(row[1])
        XCTAssertEqual(memo, "大阪第一交通堺営業所")
    }
    
    func testParseAmazonRow() {
        let rows = CSVParser.parse(realCSVData)
        
        // 4行目: 2025/07/11,ＡＭＡＺＯＮ．ＣＯ．ＪＰ,816,１,１,816,
        let row = rows[3]
        
        // 日付
        let date = DateParser.parse(row[0])
        XCTAssertNotNil(date)
        
        // 金額
        let amount = AmountParser.parse(row[2])
        XCTAssertEqual(amount, 816)
        
        // 店舗名（全角→半角変換）
        let memo = TextNormalizer.normalize(row[1])
        XCTAssertEqual(memo, "AMAZON.CO.JP")
    }
    
    func testParsePrimeRow() {
        let rows = CSVParser.parse(realCSVData)
        
        // 9行目: 2025/07/30,Ａｍａｚｏｎプライム会費,5900,１,１,5900,
        let row = rows[8]
        
        let amount = AmountParser.parse(row[2])
        XCTAssertEqual(amount, 5900)
        
        let memo = TextNormalizer.normalize(row[1])
        XCTAssertEqual(memo, "Amazonプライム会費")
    }
    
    // MARK: - 全角数字対応
    
    func testFullWidthNumbersInPaymentCount() {
        let rows = CSVParser.parse(realCSVData)
        let row = rows[1]
        
        // 列3と列4は支払回数（全角の「１」）
        let count1 = AmountParser.parse(row[3])
        let count2 = AmountParser.parse(row[4])
        
        XCTAssertEqual(count1, 1, "全角の「１」が半角1にパースされること")
        XCTAssertEqual(count2, 1, "全角の「１」が半角1にパースされること")
    }
    
    // MARK: - 合計検証
    
    func testTotalAmount() {
        let rows = CSVParser.parse(realCSVData)
        
        // データ行の金額を合計
        var total = 0
        for i in 1..<(rows.count - 1) {  // 1行目（個人情報）と最終行（合計）を除く
            if let amount = AmountParser.parse(rows[i][2]) {
                total += amount
            }
        }
        
        // 最終行の合計と一致するか
        let lastRow = rows[rows.count - 1]
        let csvTotal = AmountParser.parse(lastRow[5])
        
        XCTAssertEqual(total, 33790, "データ行の合計が33790円であること")
        XCTAssertEqual(csvTotal, 33790, "CSV最終行の合計が33790円であること")
        XCTAssertEqual(total, csvTotal, "計算した合計とCSVの合計が一致すること")
    }
    
    // MARK: - インポート件数
    
    func testExpectedImportCount() {
        let rows = CSVParser.parse(realCSVData)
        
        // 1行目: 個人情報（スキップ）
        // 2-9行目: データ（8件）
        // 10行目: 合計（スキップ）
        
        var dataRowCount = 0
        for i in 1..<rows.count {
            let row = rows[i]
            if !AmazonCardDetector.isTotalRow(row) {
                if DateParser.parse(row[0]) != nil {
                    dataRowCount += 1
                }
            }
        }
        
        XCTAssertEqual(dataRowCount, 8, "インポート対象のデータ行が8件であること")
    }
    
    // MARK: - 期待されるトランザクション
    
    func testExpectedTransactions() {
        // 期待される取引データ
        let expected: [(date: String, memo: String, amount: Int)] = [
            ("2025/07/04", "大阪第一交通堺営業所", 1300),
            ("2025/07/04", "AVALON*USEN", 14630),
            ("2025/07/11", "AMAZON.CO.JP", 816),
            ("2025/07/12", "AMAZON.CO.JP", 2412),
            ("2025/07/13", "AMAZON.CO.JP", 1077),
            ("2025/07/14", "AMAZON.CO.JP", 5639),
            ("2025/07/22", "AMAZON.CO.JP", 2016),
            ("2025/07/30", "Amazonプライム会費", 5900),
        ]
        
        let rows = CSVParser.parse(realCSVData)
        var dataIndex = 0
        
        for i in 1..<rows.count {
            let row = rows[i]
            if AmazonCardDetector.isTotalRow(row) { continue }
            guard DateParser.parse(row[0]) != nil else { continue }
            
            let memo = TextNormalizer.normalize(row[1])
            let amount = AmountParser.parse(row[2])
            
            XCTAssertEqual(memo, expected[dataIndex].memo, "行\(i)のメモが期待値と一致すること")
            XCTAssertEqual(amount, expected[dataIndex].amount, "行\(i)の金額が期待値と一致すること")
            
            dataIndex += 1
        }
        
        XCTAssertEqual(dataIndex, expected.count, "すべての期待データが処理されたこと")
    }
}
