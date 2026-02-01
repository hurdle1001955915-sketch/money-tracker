import XCTest
@testable import 収支管理

final class CSVImportTests: XCTestCase {
    
    // MARK: - Amazon Card Detection
    
    func testDetectAmazonCardCSV() {
        // Amazonカード（三井住友）CSVの検出
        let csv = """
        井原　翔太郎　様,5334-91**-****-****,Ａｍａｚｏｎマスター
        2025/07/04,大阪第一交通堺営業所,1300,１,１,1300,
        2025/07/04,ＡＶＡＬＯＮ＊ＵＳＥＮ,14630,１,１,14630,
        """
        let rows = CSVParser.parse(csv)
        
        XCTAssertTrue(AmazonCardDetector.detect(rows: rows), "AmazonカードCSVが検出されること")
    }
    
    func testDetectAmazonCardByCardMask() {
        // カード番号マスクによる検出
        let csv = """
        テスト　太郎　様,1234-56**-****-****,VISAカード
        2025/07/04,店舗名,1000,1,1,1000,
        """
        let rows = CSVParser.parse(csv)
        
        XCTAssertTrue(AmazonCardDetector.detect(rows: rows))
    }
    
    func testNotDetectGenericCSV() {
        // 汎用CSVは検出されない
        let csv = """
        日付,種類,金額,カテゴリ,メモ
        2025/01/01,支出,1000,食費,コンビニ
        """
        let rows = CSVParser.parse(csv)
        
        XCTAssertFalse(AmazonCardDetector.detect(rows: rows), "汎用CSVはAmazonカードとして検出されないこと")
    }
    
    func testIsPersonalInfoRow() {
        let personalInfoRow = ["井原　翔太郎　様", "5334-91**-****-****", "Ａｍａｚｏｎマスター"]
        XCTAssertTrue(AmazonCardDetector.isPersonalInfoRow(personalInfoRow))
        
        let dataRow = ["2025/07/04", "AMAZON.CO.JP", "1000"]
        XCTAssertFalse(AmazonCardDetector.isPersonalInfoRow(dataRow))
    }
    
    func testIsTotalRow() {
        let totalRow = ["", "", "", "", "", "33790", ""]
        XCTAssertTrue(AmazonCardDetector.isTotalRow(totalRow))
        
        let dataRow = ["2025/07/04", "AMAZON.CO.JP", "1000", "1", "1", "1000", ""]
        XCTAssertFalse(AmazonCardDetector.isTotalRow(dataRow))
    }
    
    // MARK: - Column Mapping
    
    func testColumnMapBuildForAmazonCard() {
        let map = ColumnMap.build(fromHeader: [], format: .amazonCard)
        
        XCTAssertEqual(map.dateIndex, 0)
        XCTAssertEqual(map.memoIndex, 1)
        XCTAssertEqual(map.amountIndex, 2)
    }
    
    func testColumnMapBuildWithHeader() {
        let header = ["日付", "摘要", "金額"]
        let map = ColumnMap.build(fromHeader: header, format: .bankGeneric)
        
        XCTAssertEqual(map.dateIndex, 0)
        XCTAssertEqual(map.memoIndex, 1)
        XCTAssertEqual(map.amountIndex, 2)
    }
    
    func testColumnMapBuildWithEnglishHeader() {
        let header = ["date", "description", "amount"]
        let map = ColumnMap.build(fromHeader: header, format: .bankGeneric)
        
        XCTAssertEqual(map.dateIndex, 0)
        XCTAssertEqual(map.memoIndex, 1)
        XCTAssertEqual(map.amountIndex, 2)
    }
    
    // MARK: - Type/Amount Parsing
    
    func testPickTypeAmountForCard() {
        var map = ColumnMap()
        map.amountIndex = 2
        
        let row = ["2025/07/04", "AMAZON.CO.JP", "1000", "1", "1", "1000", ""]
        let result = map.pickTypeAmount(from: row, format: .cardGeneric)
        
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.0, "expense")  // クレカは支出
        XCTAssertEqual(result?.1, 1000)
    }
    
    func testPickTypeAmountForBank() {
        var map = ColumnMap()
        map.amountIndex = 2
        
        let row = ["2025/07/04", "給与振込", "200000"]
        let result = map.pickTypeAmount(from: row, format: .bankGeneric)
        
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.0, "income")  // 銀行のプラスは収入
        XCTAssertEqual(result?.1, 200000)
    }
    
    func testPickTypeAmountWithDebitCredit() {
        var map = ColumnMap()
        map.debitIndex = 2
        map.creditIndex = 3
        
        // 出金
        let debitRow = ["2025/07/04", "ATM引出", "30000", ""]
        let debitResult = map.pickTypeAmount(from: debitRow, format: .bankGeneric)
        XCTAssertEqual(debitResult?.0, "expense")
        XCTAssertEqual(debitResult?.1, 30000)
        
        // 入金
        let creditRow = ["2025/07/04", "給与振込", "", "200000"]
        let creditResult = map.pickTypeAmount(from: creditRow, format: .bankGeneric)
        XCTAssertEqual(creditResult?.0, "income")
        XCTAssertEqual(creditResult?.1, 200000)
    }
    
    // MARK: - Full Width Number Support in Import
    
    func testImportAmazonCardWithFullWidthNumbers() {
        // 全角数字を含むAmazonカードCSV
        let csv = """
        テスト　様,****-****-****-****,カード名
        2025/07/04,店舗A,１０００,１,１,１０００,
        2025/07/05,店舗B,２０００,１,１,２０００,
        """
        let rows = CSVParser.parse(csv)
        
        // 2行目（インデックス1）のデータ
        let row = rows[1]
        
        var map = ColumnMap.build(fromHeader: [], format: .amazonCard)
        
        let dateStr = map.pickDate(from: row)
        XCTAssertNotNil(DateParser.parse(dateStr ?? ""))
        
        let result = map.pickTypeAmount(from: row, format: .amazonCard)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.1, 1000, "全角数字の金額が正しくパースされること")
    }
    
    // MARK: - Text Normalizer
    
    func testNormalizeFullWidthNumbers() {
        XCTAssertEqual(TextNormalizer.normalizeFullWidthNumbers("１２３４５"), "12345")
        XCTAssertEqual(TextNormalizer.normalizeFullWidthNumbers("０"), "0")
        XCTAssertEqual(TextNormalizer.normalizeFullWidthNumbers("１０００"), "1000")
    }
    
    func testNormalizeFullWidthAlpha() {
        XCTAssertEqual(TextNormalizer.normalizeFullWidthAlpha("ＡＭＡＺＯＮ"), "AMAZON")
        XCTAssertEqual(TextNormalizer.normalizeFullWidthAlpha("ａｂｃ"), "abc")
    }
    
    func testNormalizeFullWidthSymbols() {
        XCTAssertEqual(TextNormalizer.normalizeFullWidthSymbols("．"), ".")
        XCTAssertEqual(TextNormalizer.normalizeFullWidthSymbols("，"), ",")
        XCTAssertEqual(TextNormalizer.normalizeFullWidthSymbols("－"), "-")
    }
    
    func testNormalizeComplex() {
        let input = "ＡＭＡＺＯＮ．ＣＯ．ＪＰ"
        let expected = "AMAZON.CO.JP"
        XCTAssertEqual(TextNormalizer.normalize(input), expected)
    }
}
