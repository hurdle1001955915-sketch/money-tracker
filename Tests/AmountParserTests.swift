import XCTest
@testable import 収支管理

final class AmountParserTests: XCTestCase {
    
    // MARK: - 基本パース
    
    func testParseSimpleInteger() {
        XCTAssertEqual(AmountParser.parse("1000"), 1000)
        XCTAssertEqual(AmountParser.parse("500"), 500)
        XCTAssertEqual(AmountParser.parse("0"), 0)
    }
    
    func testParseWithCommas() {
        XCTAssertEqual(AmountParser.parse("1,000"), 1000)
        XCTAssertEqual(AmountParser.parse("10,000"), 10000)
        XCTAssertEqual(AmountParser.parse("1,234,567"), 1234567)
    }
    
    func testParseWithYenSymbol() {
        XCTAssertEqual(AmountParser.parse("¥1000"), 1000)
        XCTAssertEqual(AmountParser.parse("¥1,000"), 1000)
        XCTAssertEqual(AmountParser.parse("1000円"), 1000)
        XCTAssertEqual(AmountParser.parse("1,000円"), 1000)
    }
    
    // MARK: - 全角数字対応（Amazonカード等）
    
    func testParseFullWidthNumbers() {
        // 全角数字: １０００
        XCTAssertEqual(AmountParser.parse("１０００"), 1000, "全角数字がパースできること")
        XCTAssertEqual(AmountParser.parse("１４６３０"), 14630, "全角5桁がパースできること")
        XCTAssertEqual(AmountParser.parse("８１６"), 816, "全角3桁がパースできること")
    }
    
    func testParseMixedWidthNumbers() {
        // 半角と全角の混在
        XCTAssertEqual(AmountParser.parse("1０００"), 1000)
        XCTAssertEqual(AmountParser.parse("１000"), 1000)
    }
    
    func testParseFullWidthWithComma() {
        // 全角数字とカンマ
        XCTAssertEqual(AmountParser.parse("１，０００"), 1000)
        XCTAssertEqual(AmountParser.parse("１,０００"), 1000)  // 半角カンマ
    }
    
    // MARK: - 負の金額
    
    func testParseNegativeWithMinus() {
        XCTAssertEqual(AmountParser.parse("-1000"), -1000)
        XCTAssertEqual(AmountParser.parse("-1,000"), -1000)
    }
    
    func testParseNegativeWithFullWidthMinus() {
        // 全角マイナス
        XCTAssertEqual(AmountParser.parse("－1000"), -1000)
        XCTAssertEqual(AmountParser.parse("－１０００"), -1000)
    }
    
    func testParseNegativeWithParentheses() {
        // 会計表記: (1000) = -1000
        XCTAssertEqual(AmountParser.parse("(1000)"), -1000)
        XCTAssertEqual(AmountParser.parse("(1,000)"), -1000)
    }
    
    // MARK: - isNegative
    
    func testIsNegativeWithMinus() {
        XCTAssertTrue(AmountParser.isNegative("-1000"))
        XCTAssertTrue(AmountParser.isNegative("－1000"))  // 全角マイナス
    }
    
    func testIsNegativeWithParentheses() {
        XCTAssertTrue(AmountParser.isNegative("(1000)"))
    }
    
    func testIsNegativePositive() {
        XCTAssertFalse(AmountParser.isNegative("1000"))
        XCTAssertFalse(AmountParser.isNegative("+1000"))
    }
    
    // MARK: - エッジケース
    
    func testParseEmptyString() {
        XCTAssertNil(AmountParser.parse(""))
    }
    
    func testParseWhitespaceOnly() {
        XCTAssertNil(AmountParser.parse("   "))
    }
    
    func testParseWithLeadingTrailingWhitespace() {
        XCTAssertEqual(AmountParser.parse("  1000  "), 1000)
    }
    
    func testParseInvalidString() {
        XCTAssertNil(AmountParser.parse("invalid"))
        XCTAssertNil(AmountParser.parse("abc"))
    }
    
    func testParseWithNonBreakingSpace() {
        // Non-breaking space (U+00A0)
        XCTAssertEqual(AmountParser.parse("1\u{00A0}000"), 1000)
    }
    
    // MARK: - 実際のCSVデータパターン
    
    func testParseAmazonCardAmounts() {
        // Amazonカード（三井住友）CSVからの実際の金額
        XCTAssertEqual(AmountParser.parse("1300"), 1300)
        XCTAssertEqual(AmountParser.parse("14630"), 14630)
        XCTAssertEqual(AmountParser.parse("816"), 816)
        XCTAssertEqual(AmountParser.parse("2412"), 2412)
        XCTAssertEqual(AmountParser.parse("5900"), 5900)
        XCTAssertEqual(AmountParser.parse("33790"), 33790)  // 合計行
    }
    
    func testParseBankAmounts() {
        // 銀行CSVで見られる形式
        XCTAssertEqual(AmountParser.parse("50,000"), 50000)
        XCTAssertEqual(AmountParser.parse("-30,000"), -30000)
    }
}
