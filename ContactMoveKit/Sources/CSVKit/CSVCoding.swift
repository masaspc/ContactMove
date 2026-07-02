import Foundation
import Models

/// パース済みの CSV 表現。1行目をヘッダーとし、`rows` にはデータ行のみを保持する。
public struct CSVTable: Sendable, Equatable {
    public var headers: [String]
    /// headers を除いたデータ行
    public var rows: [[String]]

    public init(headers: [String], rows: [[String]]) {
        self.headers = headers
        self.rows = rows
    }
}

/// RFC 4180 準拠の CSV パーサ/ライタと文字コード判定(仕様書 §5)。
public enum CSVCoding {

    // MARK: - パース

    /// RFC 4180 準拠パース(クォート内カンマ/改行/`""` エスケープ対応)。1行目をヘッダーとする。
    ///
    /// - CRLF / LF / CR の行区切りをすべて受理(混在可)。
    /// - 空行は「空フィールド1つの行」として保持する(元ファイルの行番号を
    ///   `CSVSchema.contacts(from:mapping:)` のスキップレポートで再現するため)。
    /// - 末尾の改行は余分な空行とみなさない。
    public static func parse(text: String) throws -> CSVTable {
        var input = text
        // テキスト先頭に BOM(U+FEFF)が残っている場合は取り除く
        if input.hasPrefix("\u{FEFF}") {
            input.removeFirst()
        }

        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        /// 現在のレコードに何らかの入力(文字・カンマ・クォート)があったか。
        /// EOF 時に「末尾改行の後の空レコード」を出力しないための判定に使う。
        var recordHasContent = false

        var index = input.startIndex
        let end = input.endIndex
        while index < end {
            let ch = input[index]
            if inQuotes {
                if ch == "\"" {
                    let next = input.index(after: index)
                    if next < end, input[next] == "\"" {
                        // "" エスケープ
                        field.append("\"")
                        index = input.index(after: next)
                        continue
                    }
                    inQuotes = false
                } else {
                    // クォート内のカンマ・改行はフィールドの一部
                    field.append(ch)
                }
            } else {
                switch ch {
                case "\"":
                    if field.isEmpty {
                        inQuotes = true
                    } else {
                        // RFC 4180 違反(フィールド途中のクォート)は寛容にそのまま取り込む
                        field.append(ch)
                    }
                    recordHasContent = true
                case ",":
                    row.append(field)
                    field = ""
                    recordHasContent = true
                case "\n", "\r", "\r\n":
                    row.append(field)
                    rows.append(row)
                    field = ""
                    row = []
                    recordHasContent = false
                default:
                    field.append(ch)
                    recordHasContent = true
                }
            }
            index = input.index(after: index)
        }

        if inQuotes {
            throw AppError.csvParseFailed(reason: "クォート(\")が閉じられていません。")
        }
        if recordHasContent || !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        guard let headers = rows.first else {
            throw AppError.csvParseFailed(reason: "内容が空です。")
        }
        return CSVTable(headers: headers, rows: Array(rows.dropFirst()))
    }

    /// BOM 検出 → UTF-8 → Shift_JIS → EUC-JP の順に試行。全滅なら `AppError.unreadableEncoding`。
    ///
    /// Shift_JIS(実体は CP932)のデコーダは EUC-JP のバイト列でも半角カナ等として
    /// 「成功」してしまうことがあるため、デコード前にバイト構造の妥当性を検査して
    /// 誤判定を防ぐ(試行順は仕様書 §5.2 のとおり)。
    public static func parse(data: Data) throws -> (table: CSVTable, encoding: String.Encoding) {
        // UTF-8 BOM
        if data.starts(with: utf8BOM) {
            guard let text = String(data: Data(data.dropFirst(utf8BOM.count)), encoding: .utf8) else {
                throw AppError.unreadableEncoding
            }
            return (try parse(text: text), .utf8)
        }
        // UTF-16 BOM(Excel の「Unicode テキスト」保存対策)
        if data.starts(with: [0xFE, 0xFF]) || data.starts(with: [0xFF, 0xFE]),
           let text = String(data: data, encoding: .utf16) {
            return (try parse(text: text), .utf16)
        }
        // UTF-8(BOM なし)
        if let text = String(data: data, encoding: .utf8) {
            return (try parse(text: text), .utf8)
        }
        // Shift_JIS
        if isValidShiftJIS(data), let text = String(data: data, encoding: .shiftJIS) {
            return (try parse(text: text), .shiftJIS)
        }
        // EUC-JP
        if isValidEUCJP(data), let text = String(data: data, encoding: .japaneseEUC) {
            return (try parse(text: text), .japaneseEUC)
        }
        throw AppError.unreadableEncoding
    }

    // MARK: - 書き出し

    /// CRLF 改行・必要時のみクォート(カンマ/改行/`"` を含むフィールドのみ)。末尾に CRLF を付ける。
    public static func write(table: CSVTable) -> String {
        var lines: [String] = []
        lines.reserveCapacity(table.rows.count + 1)
        lines.append(encodeRow(table.headers))
        for row in table.rows {
            lines.append(encodeRow(row))
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    /// UTF-8 BOM(EF BB BF)を先頭に付与した Data。
    public static func encodeUTF8BOM(_ text: String) -> Data {
        var data = Data(utf8BOM)
        data.append(Data(text.utf8))
        return data
    }

    // MARK: - 内部実装

    private static let utf8BOM: [UInt8] = [0xEF, 0xBB, 0xBF]

    private static func encodeRow(_ fields: [String]) -> String {
        fields.map(encodeField).joined(separator: ",")
    }

    private static func encodeField(_ field: String) -> String {
        // "\r\n" が1つの Character(書記素)になるため、Unicode スカラ単位で判定する
        let needsQuoting = field.unicodeScalars.contains { scalar in
            scalar == "," || scalar == "\"" || scalar == "\n" || scalar == "\r"
        }
        guard needsQuoting else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// Shift_JIS(CP932)としてバイト構造が妥当か。
    /// 1バイト: 0x00–0x7F, 0xA1–0xDF(半角カナ)
    /// 2バイト: 先行 0x81–0x9F / 0xE0–0xFC + 後続 0x40–0xFC(0x7F を除く)
    private static func isValidShiftJIS(_ data: Data) -> Bool {
        let bytes = [UInt8](data)
        var i = 0
        while i < bytes.count {
            let b = bytes[i]
            if b <= 0x7F || (0xA1...0xDF).contains(b) {
                i += 1
            } else if (0x81...0x9F).contains(b) || (0xE0...0xFC).contains(b) {
                guard i + 1 < bytes.count else { return false }
                let trail = bytes[i + 1]
                guard (0x40...0xFC).contains(trail), trail != 0x7F else { return false }
                i += 2
            } else {
                return false
            }
        }
        return true
    }

    /// EUC-JP としてバイト構造が妥当か。
    /// 1バイト: 0x00–0x7F
    /// 半角カナ: 0x8E + 0xA1–0xDF
    /// 補助漢字: 0x8F + (0xA1–0xFE) × 2
    /// 2バイト: (0xA1–0xFE) × 2
    private static func isValidEUCJP(_ data: Data) -> Bool {
        let bytes = [UInt8](data)
        var i = 0
        while i < bytes.count {
            let b = bytes[i]
            if b <= 0x7F {
                i += 1
            } else if b == 0x8E {
                guard i + 1 < bytes.count, (0xA1...0xDF).contains(bytes[i + 1]) else { return false }
                i += 2
            } else if b == 0x8F {
                guard i + 2 < bytes.count,
                      (0xA1...0xFE).contains(bytes[i + 1]),
                      (0xA1...0xFE).contains(bytes[i + 2]) else { return false }
                i += 3
            } else if (0xA1...0xFE).contains(b) {
                guard i + 1 < bytes.count, (0xA1...0xFE).contains(bytes[i + 1]) else { return false }
                i += 2
            } else {
                return false
            }
        }
        return true
    }
}
