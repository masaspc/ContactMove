import Foundation
import Models

// MARK: - フィールド定義とマッピング(仕様書 §5)

/// CSV の列に割り当てられる連絡先フィールド。
public enum ContactField: String, Codable, CaseIterable, Sendable {
    case familyName, givenName, phoneticFamilyName, phoneticGivenName, middleName
    case namePrefix, nameSuffix, organizationName, departmentName, jobTitle
    case phone1, phone1Label, phone2, phone2Label, phone3, phone3Label, phoneOther
    case email1, email1Label, email2, email2Label, emailOther
    case postalCode, state, city, street, subLocality, country, addressLabel
    case url, birthday, groups

    /// マッピングUIに表示する日本語名
    public var displayName: String {
        switch self {
        case .familyName: return "姓"
        case .givenName: return "名"
        case .phoneticFamilyName: return "姓ふりがな"
        case .phoneticGivenName: return "名ふりがな"
        case .middleName: return "ミドルネーム"
        case .namePrefix: return "敬称(前)"
        case .nameSuffix: return "敬称(後)"
        case .organizationName: return "会社名"
        case .departmentName: return "部署"
        case .jobTitle: return "役職"
        case .phone1: return "電話1"
        case .phone1Label: return "電話1ラベル"
        case .phone2: return "電話2"
        case .phone2Label: return "電話2ラベル"
        case .phone3: return "電話3"
        case .phone3Label: return "電話3ラベル"
        case .phoneOther: return "電話その他"
        case .email1: return "メール1"
        case .email1Label: return "メール1ラベル"
        case .email2: return "メール2"
        case .email2Label: return "メール2ラベル"
        case .emailOther: return "メールその他"
        case .postalCode: return "郵便番号"
        case .state: return "都道府県"
        case .city: return "市区町村"
        case .street: return "番地"
        case .subLocality: return "建物名"
        case .country: return "国"
        case .addressLabel: return "住所ラベル"
        case .url: return "URL"
        case .birthday: return "誕生日(YYYY-MM-DD)"
        case .groups: return "グループ"
        }
    }
}

/// 既知の CSV 形式プリセット。
public enum CSVPreset: String, CaseIterable, Sendable {
    case standard   // 本アプリ標準(§5.1)
    case google     // Google コンタクト エクスポート形式
    case outlook    // Outlook エクスポート形式
}

/// 列番号 → フィールドの割り当て(ユーザー編集可能・プリセット保存対応)。
public struct ColumnMapping: Codable, Sendable, Equatable {
    /// プリセット名(保存時にユーザーが付ける)
    public var name: String
    /// 列 index(0始まり)→ フィールド
    public var assignments: [Int: ContactField]

    public init(name: String, assignments: [Int: ContactField]) {
        self.name = name
        self.assignments = assignments
    }
}

/// インポート変換の結果。
public struct CSVImportResult: Sendable {
    public var contacts: [TransferContact]
    public var skipped: [SkippedRow]

    public struct SkippedRow: Sendable {
        /// 元ファイル上の行番号(ヘッダー行を1行目とする)
        public let line: Int
        public let reason: String

        public init(line: Int, reason: String) {
            self.line = line
            self.reason = reason
        }
    }

    public init(contacts: [TransferContact] = [], skipped: [SkippedRow] = []) {
        self.contacts = contacts
        self.skipped = skipped
    }
}

// MARK: - スキーマ本体

public enum CSVSchema {

    /// 本アプリ標準カラム(仕様書 §5.1)。
    public static let standardHeaders: [String] = [
        "姓", "名", "姓ふりがな", "名ふりがな", "ミドルネーム", "敬称(前)", "敬称(後)",
        "会社名", "部署", "役職",
        "電話1", "電話1ラベル", "電話2", "電話2ラベル", "電話3", "電話3ラベル", "電話その他",
        "メール1", "メール1ラベル", "メール2", "メール2ラベル", "メールその他",
        "郵便番号", "都道府県", "市区町村", "番地", "建物名", "国", "住所ラベル",
        "URL", "誕生日(YYYY-MM-DD)", "グループ",
    ]

    /// 標準ヘッダー名 → フィールド(standardHeaders と同順)
    private static let standardFields: [ContactField] = [
        .familyName, .givenName, .phoneticFamilyName, .phoneticGivenName, .middleName,
        .namePrefix, .nameSuffix,
        .organizationName, .departmentName, .jobTitle,
        .phone1, .phone1Label, .phone2, .phone2Label, .phone3, .phone3Label, .phoneOther,
        .email1, .email1Label, .email2, .email2Label, .emailOther,
        .postalCode, .state, .city, .street, .subLocality, .country, .addressLabel,
        .url, .birthday, .groups,
    ]

    /// Google コンタクト(旧形式)ヘッダー名 → フィールド
    private static let googleHeaderMap: [String: ContactField] = [
        "Given Name": .givenName,
        "Family Name": .familyName,
        "Additional Name": .middleName,
        "Name Prefix": .namePrefix,
        "Name Suffix": .nameSuffix,
        "Given Name Yomi": .phoneticGivenName,
        "Family Name Yomi": .phoneticFamilyName,
        "Organization 1 - Name": .organizationName,
        "Organization 1 - Department": .departmentName,
        "Organization 1 - Title": .jobTitle,
        "Phone 1 - Value": .phone1,
        "Phone 1 - Type": .phone1Label,
        "Phone 2 - Value": .phone2,
        "Phone 2 - Type": .phone2Label,
        "Phone 3 - Value": .phone3,
        "Phone 3 - Type": .phone3Label,
        "E-mail 1 - Value": .email1,
        "E-mail 1 - Type": .email1Label,
        "E-mail 2 - Value": .email2,
        "E-mail 2 - Type": .email2Label,
        "Address 1 - Postal Code": .postalCode,
        "Address 1 - Region": .state,
        "Address 1 - City": .city,
        "Address 1 - Street": .street,
        "Address 1 - Extended Address": .subLocality,
        "Address 1 - Country": .country,
        "Address 1 - Type": .addressLabel,
        "Website 1 - Value": .url,
        "Birthday": .birthday,
        "Group Membership": .groups,
    ]

    /// Google コンタクト(新形式: First Name / Last Name 系)ヘッダー名 → フィールド
    private static let googleNewHeaderMap: [String: ContactField] = [
        "First Name": .givenName,
        "Middle Name": .middleName,
        "Last Name": .familyName,
        "Phonetic First Name": .phoneticGivenName,
        "Phonetic Last Name": .phoneticFamilyName,
        "Name Prefix": .namePrefix,
        "Name Suffix": .nameSuffix,
        "Organization Name": .organizationName,
        "Organization Title": .jobTitle,
        "Organization Department": .departmentName,
        "Phone 1 - Value": .phone1,
        "Phone 1 - Label": .phone1Label,
        "Phone 2 - Value": .phone2,
        "Phone 2 - Label": .phone2Label,
        "Phone 3 - Value": .phone3,
        "Phone 3 - Label": .phone3Label,
        "E-mail 1 - Value": .email1,
        "E-mail 1 - Label": .email1Label,
        "E-mail 2 - Value": .email2,
        "E-mail 2 - Label": .email2Label,
        "Address 1 - Postal Code": .postalCode,
        "Address 1 - Region": .state,
        "Address 1 - City": .city,
        "Address 1 - Street": .street,
        "Address 1 - Extended Address": .subLocality,
        "Address 1 - Country": .country,
        "Address 1 - Label": .addressLabel,
        "Website 1 - Value": .url,
        "Birthday": .birthday,
        "Labels": .groups,
    ]

    /// Outlook エクスポート形式ヘッダー名 → フィールド
    private static let outlookHeaderMap: [String: ContactField] = [
        "First Name": .givenName,
        "Middle Name": .middleName,
        "Last Name": .familyName,
        "Title": .namePrefix,
        "Suffix": .nameSuffix,
        "Company": .organizationName,
        "Department": .departmentName,
        "Job Title": .jobTitle,
        "Mobile Phone": .phone1,
        "Home Phone": .phone2,
        "Business Phone": .phone3,
        "E-mail Address": .email1,
        "E-mail 2 Address": .email2,
        "Home Postal Code": .postalCode,
        "Home State": .state,
        "Home City": .city,
        "Home Street": .street,
        "Home Country/Region": .country,
        "Web Page": .url,
        "Birthday": .birthday,
        "Categories": .groups,
    ]

    // MARK: - プリセット判定

    /// ヘッダー行から既知プリセットを自動判定する。判定できなければ nil
    /// (呼び出し側でカラムマッピング UI へ誘導する)。
    public static func detectPreset(headers: [String]) -> CSVPreset? {
        let set = Set(headers.map { $0.trimmingCharacters(in: .whitespaces) })
        // 標準形式: 主要カラムが含まれる
        if set.contains("姓") && set.contains("名") && set.contains("電話1") {
            return .standard
        }
        // Google 旧形式: Given Name / Family Name
        if set.contains("Given Name") && set.contains("Family Name") {
            return .google
        }
        // Google 新形式: First/Last Name + Phone 1 - Value 等の複合カラム
        if set.contains("First Name") && set.contains("Last Name"),
           set.contains(where: { $0.hasPrefix("Phone 1 -") || $0.hasPrefix("E-mail 1 -") }) {
            return .google
        }
        // Outlook: First/Last Name + Outlook 固有カラム
        if set.contains("First Name") && set.contains("Last Name"),
           set.contains("E-mail Address") || set.contains("Home Phone")
            || set.contains("Business Phone") || set.contains("Company") {
            return .outlook
        }
        return nil
    }

    /// プリセットに応じた既定マッピングを生成する。
    /// ヘッダー名の照合で割り当てるため、列順が変わっていても機能する。
    public static func defaultMapping(for preset: CSVPreset, headers: [String]) -> ColumnMapping {
        var assignments: [Int: ContactField] = [:]
        let map: [String: ContactField]
        switch preset {
        case .standard:
            map = Dictionary(uniqueKeysWithValues: zip(standardHeaders, standardFields))
        case .google:
            let trimmed = Set(headers.map { $0.trimmingCharacters(in: .whitespaces) })
            map = trimmed.contains("Given Name") ? googleHeaderMap : googleNewHeaderMap
        case .outlook:
            map = outlookHeaderMap
        }
        var used = Set<ContactField>()
        for (index, header) in headers.enumerated() {
            let key = header.trimmingCharacters(in: .whitespaces)
            if let field = map[key], !used.contains(field) {
                assignments[index] = field
                used.insert(field)
            }
        }
        return ColumnMapping(name: preset.rawValue, assignments: assignments)
    }

    // MARK: - インポート変換(仕様書 §5.2 バリデーション)

    /// テーブル+マッピング → TransferContact 列。
    /// - 空行・列数不一致の行はスキップし、行番号(ヘッダーを1行目とする)と理由を記録。
    /// - 電話番号は数字/`+`/`-`/`()`/空白以外を除去。数字が1つもなければ捨てる。
    /// - 誕生日は YYYY-MM-DD / YYYY/MM/DD を受理し、不正値は無視(他フィールドは取り込む)。
    /// - 氏名・組織・電話・メールが全て空の行はスキップ。
    public static func contacts(from table: CSVTable, mapping: ColumnMapping) -> CSVImportResult {
        var result = CSVImportResult()
        let columnCount = table.headers.count

        for (rowIndex, row) in table.rows.enumerated() {
            let line = rowIndex + 2  // ヘッダーが1行目

            if row.count == 1 && row[0].trimmingCharacters(in: .whitespaces).isEmpty {
                result.skipped.append(.init(line: line, reason: "空行"))
                continue
            }
            if row.count != columnCount {
                result.skipped.append(.init(
                    line: line,
                    reason: "列数不一致(期待 \(columnCount) 列、実際 \(row.count) 列)"))
                continue
            }

            var contact = TransferContact()
            var phoneSlots: [(value: String?, label: String?)] = [(nil, nil), (nil, nil), (nil, nil)]
            var emailSlots: [(value: String?, label: String?)] = [(nil, nil), (nil, nil)]
            var address = TransferContact.PostalAddress(label: .home)
            var addressLabelText: String?
            var phoneOther = ""
            var emailOther = ""

            for (column, field) in mapping.assignments {
                guard column < row.count else { continue }
                let value = row[column].trimmingCharacters(in: .whitespacesAndNewlines)
                guard !value.isEmpty else { continue }

                switch field {
                case .familyName: contact.familyName = value
                case .givenName: contact.givenName = value
                case .phoneticFamilyName: contact.phoneticFamilyName = value
                case .phoneticGivenName: contact.phoneticGivenName = value
                case .middleName: contact.middleName = value
                case .namePrefix: contact.namePrefix = value
                case .nameSuffix: contact.nameSuffix = value
                case .organizationName: contact.organizationName = value
                case .departmentName: contact.departmentName = value
                case .jobTitle: contact.jobTitle = value
                case .phone1: phoneSlots[0].value = value
                case .phone1Label: phoneSlots[0].label = value
                case .phone2: phoneSlots[1].value = value
                case .phone2Label: phoneSlots[1].label = value
                case .phone3: phoneSlots[2].value = value
                case .phone3Label: phoneSlots[2].label = value
                case .phoneOther: phoneOther = value
                case .email1: emailSlots[0].value = value
                case .email1Label: emailSlots[0].label = value
                case .email2: emailSlots[1].value = value
                case .email2Label: emailSlots[1].label = value
                case .emailOther: emailOther = value
                case .postalCode: address.postalCode = value
                case .state: address.state = value
                case .city: address.city = value
                case .street: address.street = value
                case .subLocality: address.subLocality = value
                case .country: address.country = value
                case .addressLabel: addressLabelText = value
                case .url:
                    contact.urls.append(.init(label: .other, value: value))
                case .birthday:
                    contact.birthday = parseBirthday(value)
                case .groups:
                    contact.groups = splitMultiValue(value)
                }
            }

            // 電話スロット(ラベル既定: 電話1=携帯、それ以外=その他)
            for (index, slot) in phoneSlots.enumerated() {
                guard let rawValue = slot.value else { continue }
                guard let cleaned = cleanPhoneNumber(rawValue) else { continue }
                let label = slot.label.map(LabelMapper.label(fromCSVText:))
                    ?? (index == 0 ? .mobile : .other)
                contact.phones.append(.init(label: label, value: cleaned))
            }
            for value in splitMultiValue(phoneOther) {
                if let cleaned = cleanPhoneNumber(value) {
                    contact.phones.append(.init(label: .other, value: cleaned))
                }
            }

            // メールスロット(ラベル既定: 自宅)
            for slot in emailSlots {
                guard let value = slot.value else { continue }
                let label = slot.label.map(LabelMapper.label(fromCSVText:)) ?? .home
                contact.emails.append(.init(label: label, value: value))
            }
            for value in splitMultiValue(emailOther) {
                contact.emails.append(.init(label: .other, value: value))
            }

            // 住所(何か1つでも値があれば採用)
            if [address.postalCode, address.state, address.city,
                address.street, address.subLocality, address.country]
                .contains(where: { !($0 ?? "").isEmpty }) {
                address.label = addressLabelText.map(LabelMapper.label(fromCSVText:)) ?? .home
                contact.postalAddresses.append(address)
            }

            guard !contact.isEffectivelyEmpty else {
                result.skipped.append(.init(line: line, reason: "氏名・電話・メールが全て空"))
                continue
            }
            result.contacts.append(contact)
        }
        return result
    }

    // MARK: - エクスポート変換(仕様書 §5.1)

    /// TransferContact 列 → 標準カラムのテーブル。
    /// 電話は最大3件(あふれた分は「電話その他」にセミコロン連結)、メールは最大2件、
    /// 住所は先頭1件のみ。画像は CSV に含めない(vCard を案内)。
    public static func table(from contacts: [TransferContact]) -> CSVTable {
        var rows: [[String]] = []
        rows.reserveCapacity(contacts.count)

        for contact in contacts {
            var values: [ContactField: String] = [:]
            values[.familyName] = contact.familyName
            values[.givenName] = contact.givenName
            values[.phoneticFamilyName] = contact.phoneticFamilyName ?? ""
            values[.phoneticGivenName] = contact.phoneticGivenName ?? ""
            values[.middleName] = contact.middleName ?? ""
            values[.namePrefix] = contact.namePrefix ?? ""
            values[.nameSuffix] = contact.nameSuffix ?? ""
            values[.organizationName] = contact.organizationName ?? ""
            values[.departmentName] = contact.departmentName ?? ""
            values[.jobTitle] = contact.jobTitle ?? ""

            let phoneFields: [(ContactField, ContactField)] = [
                (.phone1, .phone1Label), (.phone2, .phone2Label), (.phone3, .phone3Label),
            ]
            for (index, pair) in phoneFields.enumerated() where index < contact.phones.count {
                values[pair.0] = contact.phones[index].value
                values[pair.1] = LabelMapper.japaneseText(for: contact.phones[index].label)
            }
            if contact.phones.count > 3 {
                values[.phoneOther] = contact.phones.dropFirst(3).map(\.value).joined(separator: ";")
            }

            let emailFields: [(ContactField, ContactField)] = [
                (.email1, .email1Label), (.email2, .email2Label),
            ]
            for (index, pair) in emailFields.enumerated() where index < contact.emails.count {
                values[pair.0] = contact.emails[index].value
                values[pair.1] = LabelMapper.japaneseText(for: contact.emails[index].label)
            }
            if contact.emails.count > 2 {
                values[.emailOther] = contact.emails.dropFirst(2).map(\.value).joined(separator: ";")
            }

            if let address = contact.postalAddresses.first {
                values[.postalCode] = address.postalCode ?? ""
                values[.state] = address.state ?? ""
                values[.city] = address.city ?? ""
                values[.street] = address.street ?? ""
                values[.subLocality] = address.subLocality ?? ""
                values[.country] = address.country ?? ""
                values[.addressLabel] = LabelMapper.japaneseText(for: address.label)
            }

            values[.url] = contact.urls.map(\.value).joined(separator: ";")
            values[.birthday] = formatBirthday(contact.birthday)
            values[.groups] = contact.groups.joined(separator: ";")

            rows.append(standardFields.map { values[$0] ?? "" })
        }
        return CSVTable(headers: standardHeaders, rows: rows)
    }

    /// UTF-8 BOM + CRLF の完成品(エクスポート用)。
    public static func exportData(contacts: [TransferContact]) -> Data {
        CSVCoding.encodeUTF8BOM(CSVCoding.write(table: table(from: contacts)))
    }

    /// `連絡先_YYYYMMDD_HHmm.csv`
    public static func exportFileName(date: Date = Date()) -> String {
        "連絡先_\(timestamp(date)).csv"
    }

    static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd_HHmm"
        return formatter.string(from: date)
    }

    // MARK: - 値のクレンジング

    /// 電話番号: 数字/`+`/`-`/`()`/空白以外の文字を除去。数字が残らなければ nil。
    static func cleanPhoneNumber(_ raw: String) -> String? {
        let allowed = Set("0123456789+-() ")
        // 全角数字等は NFKC で半角化してから許可文字を残す
        let nfkc = raw.precomposedStringWithCompatibilityMapping
        let cleaned = String(nfkc.filter { allowed.contains($0) })
            .trimmingCharacters(in: .whitespaces)
        return cleaned.contains(where: \.isNumber) ? cleaned : nil
    }

    /// 誕生日: `YYYY-MM-DD` / `YYYY/MM/DD` を受理。不正値は nil(無視)。
    static func parseBirthday(_ raw: String) -> DateComponents? {
        let separators = CharacterSet(charactersIn: "-/")
        let parts = raw.trimmingCharacters(in: .whitespaces)
            .components(separatedBy: separators)
        guard parts.count == 3,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (1...12).contains(month), (1...31).contains(day), year >= 1 else {
            return nil
        }
        // 実在日チェック(2/30 等を弾く)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else {
            return nil
        }
        let roundTrip = calendar.dateComponents([.year, .month, .day], from: date)
        guard roundTrip.year == year, roundTrip.month == month, roundTrip.day == day else {
            return nil
        }
        return DateComponents(year: year, month: month, day: day)
    }

    static func formatBirthday(_ birthday: DateComponents?) -> String {
        guard let birthday, let year = birthday.year,
              let month = birthday.month, let day = birthday.day else { return "" }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// セミコロン(全半角)・Google の ` ::: ` 区切りの複数値を分解。
    static func splitMultiValue(_ raw: String) -> [String] {
        guard !raw.isEmpty else { return [] }
        return raw
            .replacingOccurrences(of: ":::", with: ";")
            .replacingOccurrences(of: "\u{FF1B}", with: ";")  // 全角セミコロン
            .components(separatedBy: ";")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
