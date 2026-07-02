import Foundation
import Models

/// 重複判定用の正規化(仕様書 §6.1)。
/// - 電話: 記号除去 → 日本番号(0始まり)は E.164 化。比較は「E.164一致 or 下10桁一致」
/// - メール: 小文字化 + trim
/// - 氏名: NFKC 正規化 + trim + 連続空白の統合
/// - ふりがな: ひらがな→カタカナ統一
public enum ContactNormalizer {

    /// 記号除去 → 日本番号は E.164 化(`090…` → `+8190…`)。
    /// - 全角数字/全角記号は NFKC で半角化してから処理する。
    /// - `+` 始まり(既に国際形式)はそのまま `+` + 数字列を返す。
    /// - `0` 始まりで10桁以上(日本の固定/携帯番号)は先頭 0 を除去し `+81` を付与。
    /// - それ以外(桁不足・国番号不明等)は数字列のまま返す。
    public static func normalizePhone(_ raw: String) -> String {
        let nfkc = raw.precomposedStringWithCompatibilityMapping
        var digits = ""
        var hasLeadingPlus = false
        var seenSignificant = false
        for scalar in nfkc.unicodeScalars {
            if scalar.value >= 0x30 && scalar.value <= 0x39 {
                digits.unicodeScalars.append(scalar)
                seenSignificant = true
            } else if scalar.value == 0x2B { // "+"
                if !seenSignificant { hasLeadingPlus = true }
                seenSignificant = true
            }
        }
        guard !digits.isEmpty else { return "" }
        if hasLeadingPlus {
            return "+" + digits
        }
        if digits.hasPrefix("0") && digits.count >= 10 {
            return "+81" + digits.dropFirst()
        }
        return digits
    }

    /// 比較キー集合(E.164 表現と、10桁以上ある場合の「下10桁」)。
    /// どれか1つでも交差すれば L1(電話一致)と判定する。
    /// 例: `090-1234-5678` → {"+819012345678", "9012345678"}
    ///     `+819012345678` → {"+819012345678", "9012345678"}
    public static func phoneComparisonKeys(_ raw: String) -> Set<String> {
        let normalized = normalizePhone(raw)
        guard !normalized.isEmpty else { return [] }
        var keys: Set<String> = [normalized]
        let digits = normalized.hasPrefix("+") ? String(normalized.dropFirst()) : normalized
        if digits.count >= 10 {
            keys.insert(String(digits.suffix(10)))
        }
        return keys
    }

    /// 小文字化・前後空白除去
    public static func normalizeEmail(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// NFKC 正規化(全角英数→半角、半角カナ→全角カナ等)+ trim + 連続空白を1つに統合
    public static func normalizeName(_ raw: String) -> String {
        let nfkc = raw.precomposedStringWithCompatibilityMapping
        let parts = nfkc
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        return parts.joined(separator: " ")
    }

    /// normalizeName 後、ひらがな(U+3041〜U+3096)をカタカナへ統一。
    /// StringTransform は Linux Foundation で利用できない可能性があるため
    /// スカラー変換(+0x60)で実装する。
    public static func normalizeKana(_ raw: String) -> String {
        let base = normalizeName(raw)
        var result = ""
        result.unicodeScalars.reserveCapacity(base.unicodeScalars.count)
        for scalar in base.unicodeScalars {
            if (0x3041...0x3096).contains(scalar.value),
               let katakana = Unicode.Scalar(scalar.value + 0x60) {
                result.unicodeScalars.append(katakana)
            } else {
                result.unicodeScalars.append(scalar)
            }
        }
        return result
    }
}
