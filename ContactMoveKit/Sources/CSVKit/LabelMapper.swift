import Foundation
import Models

/// ラベル変換表(仕様書 §5.1)。
/// CSV上の日本語ラベル(自宅/勤務先/携帯/iPhone/メイン/その他)と
/// `TransferContact.ContactLabel` を相互変換する。
/// インポート時は Google/Outlook 形式の英語ラベルも受理する。
public enum LabelMapper {

    public static func japaneseText(for label: TransferContact.ContactLabel) -> String {
        switch label {
        case .home: return "自宅"
        case .work: return "勤務先"
        case .mobile: return "携帯"
        case .iPhone: return "iPhone"
        case .main: return "メイン"
        case .other: return "その他"
        }
    }

    public static func label(fromCSVText text: String) -> TransferContact.ContactLabel {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch trimmed {
        case "自宅": return .home
        case "勤務先", "会社": return .work
        case "携帯", "携帯電話": return .mobile
        case "iPhone": return .iPhone
        case "メイン", "主": return .main
        case "その他", "": return .other
        default: break
        }
        // Google / Outlook 形式の英語ラベル(大文字小文字を無視)
        switch trimmed.lowercased() {
        case "home", "home phone": return .home
        case "work", "business", "business phone", "company": return .work
        case "mobile", "cell", "mobile phone", "cellular": return .mobile
        case "iphone": return .iPhone
        case "main": return .main
        default: return .other
        }
    }
}
