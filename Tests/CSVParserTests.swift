import XCTest
@testable import 収支管理

final class CSVParserTests: XCTestCase {
    
    // MARK: - 基本パース
    
    func testParseSimpleCSV() {
        let csv = "a,b,c\n1,2,3"
        let result = CSVParser.parse(csv)
        
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0], ["a", "b", "c"])
        XCTAssertEqual(result[1], ["1", "2", "3"])
    }
    
    func testParseWithEmptyFields() {
        let csv = "a,,c\n1,2,"
        let result = CSVParser.parse(csv)
        
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0], ["a", "", "c"])
        XCTAssertEqual(result[1], ["1", "2", ""])
    }
    
    // MARK: - ダブルクォート対応
    
    func testParseQuotedFields() {
        let csv = "\"hello, world\",b,c"
        let result = CSVParser.parse(csv)
        
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0][0], "hello, world")
    }
    
    func testParseEscapedQuotes() {
        let csv = "\"hello \"\"world\"\"\",b,c"
        let result = CSVParser.parse(csv)
        
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0][0], "hello \"world\"")
    }
    
    func testParseQuotedFieldWithNewline() {
        let csv = "\"line1\nline2\",b,c"
        let result = CSVParser.parse(csv)
        
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0][0], "line1\nline2")
    }
    
    // MARK: - 空白処理
    
    func testParseTrimWhitespace() {
        let csv = "  a  ,  b  ,  c  "
        let result = CSVParser.parse(csv)
        
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0], ["a", "b", "c"])
    }
    
    // MARK: - エッジケース
    
    func testParseEmptyString() {
        let csv = ""
        let result = CSVParser.parse(csv)
        
        XCTAssertEqual(result.count, 0)
    }
    
    func testParseSingleRow() {
        let csv = "a,b,c"
        let result = CSVParser.parse(csv)
        
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0], ["a", "b", "c"])
    }
    
    func testParseSingleColumn() {
        let csv = "a\nb\nc"
        let result = CSVParser.parse(csv)
        
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result[0], ["a"])
        XCTAssertEqual(result[1], ["b"])
        XCTAssertEqual(result[2], ["c"])
    }
    
    // MARK: - 実際のCSVデータパターン
    
    func testParseAmazonCardCSV() {
        // Amazonカード（三井住友）CSVの実際のデータ構造
        let csv = """
        井原　翔太郎　様,5334-91**-****-****,Ａｍａｚｏｎマスター
        2025/07/04,大阪第一交通堺営業所,1300,１,１,1300,
        2025/07/04,ＡＶＡＬＯＮ＊ＵＳＥＮ,14630,１,１,14630,
        ,,,,,33790,
        """
        let result = CSVParser.parse(csv)
        
        XCTAssertEqual(result.count, 4)
        
        // 1行目: 個人情報
        XCTAssertTrue(result[0][0].contains("様"))
        XCTAssertTrue(result[0][1].contains("****"))
        
        // 2行目: データ行
        XCTAssertEqual(result[1][0], "2025/07/04")
        XCTAssertEqual(result[1][2], "1300")
        
        // 4行目: 合計行（日付が空）
        XCTAssertEqual(result[3][0], "")
        XCTAssertEqual(result[3][5], "33790")
    }
    
    func testParseAppExportCSV() {
        // アプリエクスポートCSV
        let csv = """
        日付,種類,金額,カテゴリ,メモ
        2025/01/01,支出,1000,食費,コンビニ
        2025/01/02,収入,200000,給与,1月分
        """
        let result = CSVParser.parse(csv)
        
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result[0][0], "日付")
        XCTAssertEqual(result[1][3], "食費")
        XCTAssertEqual(result[2][1], "収入")
    }
}
