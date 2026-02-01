import XCTest
@testable import 収支管理

final class DateParserTests: XCTestCase {
    
    // MARK: - 基本フォーマット
    
    func testParseYYYYSlashMMSlashDD() {
        let result = DateParser.parse("2025/07/04")
        XCTAssertNotNil(result)
        
        let calendar = Calendar.current
        XCTAssertEqual(calendar.component(.year, from: result!), 2025)
        XCTAssertEqual(calendar.component(.month, from: result!), 7)
        XCTAssertEqual(calendar.component(.day, from: result!), 4)
    }
    
    func testParseYYYYHyphenMMHyphenDD() {
        let result = DateParser.parse("2025-07-04")
        XCTAssertNotNil(result)
        
        let calendar = Calendar.current
        XCTAssertEqual(calendar.component(.year, from: result!), 2025)
        XCTAssertEqual(calendar.component(.month, from: result!), 7)
        XCTAssertEqual(calendar.component(.day, from: result!), 4)
    }
    
    func testParseYYYYMMDD() {
        let result = DateParser.parse("20250704")
        XCTAssertNotNil(result)
        
        let calendar = Calendar.current
        XCTAssertEqual(calendar.component(.year, from: result!), 2025)
        XCTAssertEqual(calendar.component(.month, from: result!), 7)
        XCTAssertEqual(calendar.component(.day, from: result!), 4)
    }
    
    func testParseSingleDigitMonth() {
        let result = DateParser.parse("2025/7/4")
        XCTAssertNotNil(result)
        
        let calendar = Calendar.current
        XCTAssertEqual(calendar.component(.year, from: result!), 2025)
        XCTAssertEqual(calendar.component(.month, from: result!), 7)
        XCTAssertEqual(calendar.component(.day, from: result!), 4)
    }
    
    // MARK: - 全角数字対応
    
    func testParseFullWidthNumbers() {
        // 全角数字: ２０２５/０７/０４
        let result = DateParser.parse("２０２５/０７/０４")
        XCTAssertNotNil(result, "全角数字の日付がパースできること")
        
        if let date = result {
            let calendar = Calendar.current
            XCTAssertEqual(calendar.component(.year, from: date), 2025)
            XCTAssertEqual(calendar.component(.month, from: date), 7)
            XCTAssertEqual(calendar.component(.day, from: date), 4)
        }
    }
    
    func testParseMixedWidthNumbers() {
        // 半角と全角が混在: 2025/０７/04
        let result = DateParser.parse("2025/０７/04")
        XCTAssertNotNil(result, "半角/全角混在の日付がパースできること")
    }
    
    // MARK: - エッジケース
    
    func testParseEmptyString() {
        let result = DateParser.parse("")
        XCTAssertNil(result)
    }
    
    func testParseWhitespaceOnly() {
        let result = DateParser.parse("   ")
        XCTAssertNil(result)
    }
    
    func testParseWithLeadingTrailingWhitespace() {
        let result = DateParser.parse("  2025/07/04  ")
        XCTAssertNotNil(result)
    }
    
    func testParseInvalidDate() {
        let result = DateParser.parse("invalid")
        XCTAssertNil(result)
    }
    
    func testParseInvalidFormat() {
        let result = DateParser.parse("04-07-2025")  // DD-MM-YYYY は未対応
        XCTAssertNil(result)
    }
    
    // MARK: - 実際のCSVデータパターン
    
    func testParseAmazonCardDate() {
        // Amazonカード（三井住友）のCSVから抽出した日付
        let result = DateParser.parse("2025/07/04")
        XCTAssertNotNil(result)
    }
    
    func testParsePayPayDate() {
        // PayPayのCSVから抽出した日付
        let result = DateParser.parse("2025-01-15")
        XCTAssertNotNil(result)
    }
    
    func testParseResonaDate() {
        // りそな銀行のCSV形式
        let result = DateParser.parse("2025/01/15")
        XCTAssertNotNil(result)
    }
}
