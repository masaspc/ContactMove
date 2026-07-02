import XCTest
import Models
@testable import CSVKit

final class CSVCodingTests: XCTestCase {

    // MARK: - UT-CSV-01: RFC 4180 パース

    func testSimpleParse() throws {
        let table = try CSVCoding.parse(text: "a,b,c\r\n1,2,3\r\n")
        XCTAssertEqual(table.headers, ["a", "b", "c"])
        XCTAssertEqual(table.rows, [["1", "2", "3"]])
    }

    func testQuotedComma() throws {
        let table = try CSVCoding.parse(text: "name,memo\r\n\"山田, 太郎\",hello\r\n")
        XCTAssertEqual(table.rows[0][0], "山田, 太郎")
    }

    func testQuotedNewline() throws {
        let table = try CSVCoding.parse(text: "name,addr\r\n太郎,\"東京都\r\n千代田区\"\r\n")
        XCTAssertEqual(table.rows[0][1], "東京都\r\n千代田区")
        XCTAssertEqual(table.rows.count, 1)
    }

    func testEscapedQuote() throws {
        let table = try CSVCoding.parse(text: "a\r\n\"say \"\"hi\"\"\"\r\n")
        XCTAssertEqual(table.rows[0][0], "say \"hi\"")
    }

    func testEmptyFieldsAndTrailingComma() throws {
        let table = try CSVCoding.parse(text: "a,b,c\r\n1,,\r\n")
        XCTAssertEqual(table.rows[0], ["1", "", ""])
    }

    func testMixedLineEndings() throws {
        let table = try CSVCoding.parse(text: "a,b\n1,2\r\n3,4\n")
        XCTAssertEqual(table.rows, [["1", "2"], ["3", "4"]])
    }

    func testBlankLineIsKeptAsEmptyRow() throws {
        let table = try CSVCoding.parse(text: "a,b\r\n1,2\r\n\r\n3,4\r\n")
        XCTAssertEqual(table.rows.count, 3)
        XCTAssertEqual(table.rows[1], [""])
    }

    func testNoTrailingNewline() throws {
        let table = try CSVCoding.parse(text: "a,b\r\n1,2")
        XCTAssertEqual(table.rows, [["1", "2"]])
    }

    func testUnclosedQuoteThrows() {
        XCTAssertThrowsError(try CSVCoding.parse(text: "a\r\n\"open\r\n"))
    }

    func testEmptyTextThrows() {
        XCTAssertThrowsError(try CSVCoding.parse(text: ""))
    }

    // MARK: - UT-CSV-02: 文字コード判定

    func testUTF8WithBOM() throws {
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(Data("姓,名\r\n山田,太郎\r\n".utf8))
        let (table, encoding) = try CSVCoding.parse(data: data)
        XCTAssertEqual(encoding, .utf8)
        XCTAssertEqual(table.headers, ["姓", "名"])
        XCTAssertEqual(table.rows[0], ["山田", "太郎"])
    }

    func testUTF8WithoutBOM() throws {
        let data = Data("姓,名\r\n山田,太郎\r\n".utf8)
        let (table, encoding) = try CSVCoding.parse(data: data)
        XCTAssertEqual(encoding, .utf8)
        XCTAssertEqual(table.rows[0][0], "山田")
    }

    func testShiftJISDetection() throws {
        guard let data = "姓,名\r\n山田,太郎\r\n".data(using: .shiftJIS) else {
            throw XCTSkip("この環境では Shift_JIS エンコードを生成できません")
        }
        let (table, encoding) = try CSVCoding.parse(data: data)
        XCTAssertEqual(encoding, .shiftJIS)
        XCTAssertEqual(table.rows[0], ["山田", "太郎"])
    }

    func testEUCJPDetection() throws {
        guard let data = "姓,名\r\n山田,太郎\r\n".data(using: .japaneseEUC) else {
            throw XCTSkip("この環境では EUC-JP エンコードを生成できません")
        }
        let (table, encoding) = try CSVCoding.parse(data: data)
        // EUC-JP のバイト列が Shift_JIS 構造としても妥当な場合があるため、
        // どちらかで正しくデコードできていることを確認する
        XCTAssertTrue(encoding == .japaneseEUC || encoding == .shiftJIS)
        XCTAssertEqual(table.rows[0], ["山田", "太郎"])
    }

    func testUnreadableEncodingThrows() {
        // 不正な UTF-8 かつ SJIS/EUC としても不正なバイト列
        let data = Data([0xFF, 0xFF, 0xFF, 0x80])
        XCTAssertThrowsError(try CSVCoding.parse(data: data)) { error in
            guard case AppError.unreadableEncoding = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }
    }

    // MARK: - UT-CSV-03: ライタとラウンドトリップ

    func testWriteQuotesOnlyWhenNeeded() {
        let table = CSVTable(headers: ["a", "b"], rows: [["plain", "with,comma"]])
        let text = CSVCoding.write(table: table)
        XCTAssertEqual(text, "a,b\r\nplain,\"with,comma\"\r\n")
    }

    func testWriteEscapesQuotes() {
        let table = CSVTable(headers: ["a"], rows: [["say \"hi\""]])
        XCTAssertTrue(CSVCoding.write(table: table).contains("\"say \"\"hi\"\"\""))
    }

    func testRoundTripWithSpecialCharacters() throws {
        let original = CSVTable(
            headers: ["名前", "メモ", "住所"],
            rows: [
                ["山田, 太郎", "改行\r\n入り", "引用\"符\""],
                ["", "カンマ,と\"引用\"", "普通の値"],
            ]
        )
        let text = CSVCoding.write(table: original)
        let parsed = try CSVCoding.parse(text: text)
        XCTAssertEqual(parsed, original)
    }

    func testBOMEncodingRoundTrip() throws {
        let table = CSVTable(headers: ["姓"], rows: [["山田"]])
        let data = CSVCoding.encodeUTF8BOM(CSVCoding.write(table: table))
        XCTAssertEqual([UInt8](data.prefix(3)), [0xEF, 0xBB, 0xBF])
        let (parsed, _) = try CSVCoding.parse(data: data)
        XCTAssertEqual(parsed, table)
    }
}
