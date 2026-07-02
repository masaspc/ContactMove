import XCTest
import Models
@testable import CSVKit

final class CSVSchemaTests: XCTestCase {

    // MARK: - UT-CSV-04: プリセット自動判定

    func testDetectStandardPreset() {
        XCTAssertEqual(CSVSchema.detectPreset(headers: CSVSchema.standardHeaders), .standard)
    }

    func testDetectGooglePreset() {
        let headers = ["Name", "Given Name", "Additional Name", "Family Name",
                       "Phone 1 - Type", "Phone 1 - Value", "E-mail 1 - Value"]
        XCTAssertEqual(CSVSchema.detectPreset(headers: headers), .google)
    }

    func testDetectOutlookPreset() {
        let headers = ["First Name", "Middle Name", "Last Name", "Company",
                       "Home Phone", "Mobile Phone", "E-mail Address"]
        XCTAssertEqual(CSVSchema.detectPreset(headers: headers), .outlook)
    }

    func testDetectUnknownReturnsNil() {
        XCTAssertNil(CSVSchema.detectPreset(headers: ["col1", "col2", "col3"]))
    }

    // MARK: - UT-CSV-05: バリデーションとスキップ

    private func standardTable(rows: [[String]]) -> CSVTable {
        CSVTable(headers: CSVSchema.standardHeaders, rows: rows)
    }

    private func standardRow(_ overrides: [Int: String]) -> [String] {
        var row = Array(repeating: "", count: CSVSchema.standardHeaders.count)
        for (index, value) in overrides { row[index] = value }
        return row
    }

    private var standardMapping: ColumnMapping {
        CSVSchema.defaultMapping(for: .standard, headers: CSVSchema.standardHeaders)
    }

    func testColumnCountMismatchIsSkippedWithLineNumber() {
        let table = standardTable(rows: [
            standardRow([0: "山田", 1: "太郎"]),
            ["列", "が", "足りない"],
            standardRow([0: "佐藤", 1: "花子"]),
        ])
        let result = CSVSchema.contacts(from: table, mapping: standardMapping)
        XCTAssertEqual(result.contacts.count, 2)
        XCTAssertEqual(result.skipped.count, 1)
        XCTAssertEqual(result.skipped[0].line, 3)  // ヘッダー=1行目、2データ行目=3行目
        XCTAssertTrue(result.skipped[0].reason.contains("列数不一致"))
    }

    func testEmptyRowAndAllEmptyContactAreSkipped() {
        let table = standardTable(rows: [
            [""],                                  // 空行
            standardRow([8: "部署だけ"]),           // 氏名・組織・電話・メール全て空
            standardRow([0: "山田"]),
        ])
        let result = CSVSchema.contacts(from: table, mapping: standardMapping)
        XCTAssertEqual(result.contacts.count, 1)
        XCTAssertEqual(result.skipped.count, 2)
        XCTAssertEqual(result.skipped[0].reason, "空行")
    }

    func testPhoneCleaning() {
        let table = standardTable(rows: [
            standardRow([0: "山田", 10: "090(1234)5678 #依頼あり"]),
        ])
        let result = CSVSchema.contacts(from: table, mapping: standardMapping)
        XCTAssertEqual(result.contacts[0].phones[0].value, "090(1234)5678")
    }

    func testInvalidBirthdayIsIgnoredButRowImported() {
        let table = standardTable(rows: [
            standardRow([0: "山田", 30: "2000-02-30"]),   // 実在しない日
            standardRow([0: "佐藤", 30: "1990/01/02"]),   // スラッシュ区切りは受理
            standardRow([0: "鈴木", 30: "不明"]),
        ])
        let result = CSVSchema.contacts(from: table, mapping: standardMapping)
        XCTAssertEqual(result.contacts.count, 3)
        XCTAssertNil(result.contacts[0].birthday)
        XCTAssertEqual(result.contacts[1].birthday, DateComponents(year: 1990, month: 1, day: 2))
        XCTAssertNil(result.contacts[2].birthday)
    }

    func testLabelsAndMultiValues() {
        let table = standardTable(rows: [
            standardRow([
                0: "山田", 1: "太郎",
                10: "090-1111-2222", 11: "携帯",
                12: "03-1111-2222", 13: "勤務先",
                16: "0120-000-111;0120-000-222",
                17: "taro@example.com", 18: "自宅",
                21: "sub@example.com;sub2@example.com",
                31: "友人;仕事",
            ]),
        ])
        let result = CSVSchema.contacts(from: table, mapping: standardMapping)
        let contact = result.contacts[0]
        XCTAssertEqual(contact.phones.count, 4)
        XCTAssertEqual(contact.phones[0].label, .mobile)
        XCTAssertEqual(contact.phones[1].label, .work)
        XCTAssertEqual(contact.phones[2].label, .other)
        XCTAssertEqual(contact.emails.count, 3)
        XCTAssertEqual(contact.emails[0].label, .home)
        XCTAssertEqual(contact.groups, ["友人", "仕事"])
    }

    // MARK: - エクスポート & ラウンドトリップ

    private func sampleContact() -> TransferContact {
        TransferContact(
            givenName: "太郎",
            familyName: "山田",
            phoneticGivenName: "タロウ",
            phoneticFamilyName: "ヤマダ",
            organizationName: "株式会社サンプル",
            departmentName: "開発部",
            jobTitle: "エンジニア",
            phones: [
                .init(label: .mobile, value: "090-1111-2222"),
                .init(label: .work, value: "03-1111-2222"),
                .init(label: .home, value: "045-111-2222"),
                .init(label: .other, value: "0120-000-111"),
            ],
            emails: [
                .init(label: .home, value: "taro@example.com"),
                .init(label: .work, value: "taro@work.example.com"),
                .init(label: .other, value: "sub@example.com"),
            ],
            postalAddresses: [
                .init(label: .home, postalCode: "100-0001", state: "東京都",
                      city: "千代田区", street: "千代田1-1", subLocality: "ビル3F", country: "日本"),
            ],
            urls: [.init(label: .other, value: "https://example.com")],
            birthday: DateComponents(year: 1990, month: 1, day: 2),
            groups: ["友人", "仕事"]
        )
    }

    func testExportOverflowGoesToOtherColumns() {
        let table = CSVSchema.table(from: [sampleContact()])
        let row = table.rows[0]
        let headers = table.headers
        XCTAssertEqual(row[headers.firstIndex(of: "電話1")!], "090-1111-2222")
        XCTAssertEqual(row[headers.firstIndex(of: "電話1ラベル")!], "携帯")
        XCTAssertEqual(row[headers.firstIndex(of: "電話その他")!], "0120-000-111")
        XCTAssertEqual(row[headers.firstIndex(of: "メールその他")!], "sub@example.com")
        XCTAssertEqual(row[headers.firstIndex(of: "誕生日(YYYY-MM-DD)")!], "1990-01-02")
        XCTAssertEqual(row[headers.firstIndex(of: "グループ")!], "友人;仕事")
    }

    func testExportImportRoundTrip() throws {
        let original = sampleContact()
        let data = CSVSchema.exportData(contacts: [original])
        let (table, encoding) = try CSVCoding.parse(data: data)
        XCTAssertEqual(encoding, .utf8)
        XCTAssertEqual(CSVSchema.detectPreset(headers: table.headers), .standard)

        let mapping = CSVSchema.defaultMapping(for: .standard, headers: table.headers)
        let result = CSVSchema.contacts(from: table, mapping: mapping)
        XCTAssertEqual(result.contacts.count, 1)
        XCTAssertTrue(result.skipped.isEmpty)

        let imported = result.contacts[0]
        XCTAssertEqual(imported.familyName, original.familyName)
        XCTAssertEqual(imported.givenName, original.givenName)
        XCTAssertEqual(imported.phoneticFamilyName, original.phoneticFamilyName)
        XCTAssertEqual(imported.organizationName, original.organizationName)
        XCTAssertEqual(imported.phones.map(\.value), original.phones.map(\.value))
        XCTAssertEqual(imported.phones.map(\.label), original.phones.map(\.label))
        XCTAssertEqual(imported.emails.map(\.value), original.emails.map(\.value))
        XCTAssertEqual(imported.postalAddresses, original.postalAddresses)
        XCTAssertEqual(imported.birthday, original.birthday)
        XCTAssertEqual(imported.groups, original.groups)
        XCTAssertEqual(imported.urls.map(\.value), original.urls.map(\.value))
    }

    // MARK: - Google / Outlook 形式の取り込み

    func testGoogleFormatImport() {
        let headers = ["Name", "Given Name", "Family Name", "Given Name Yomi", "Family Name Yomi",
                       "Organization 1 - Name", "Phone 1 - Type", "Phone 1 - Value",
                       "E-mail 1 - Type", "E-mail 1 - Value", "Group Membership"]
        let rows = [["Taro Yamada", "太郎", "山田", "たろう", "やまだ",
                     "株式会社サンプル", "Mobile", "090-1111-2222",
                     "Home", "taro@example.com", "友人 ::: 仕事"]]
        let mapping = CSVSchema.defaultMapping(for: .google, headers: headers)
        let result = CSVSchema.contacts(from: CSVTable(headers: headers, rows: rows), mapping: mapping)
        let contact = result.contacts[0]
        XCTAssertEqual(contact.familyName, "山田")
        XCTAssertEqual(contact.givenName, "太郎")
        XCTAssertEqual(contact.phones[0].label, .mobile)
        XCTAssertEqual(contact.phones[0].value, "090-1111-2222")
        XCTAssertEqual(contact.emails[0].label, .home)
        XCTAssertEqual(contact.groups, ["友人", "仕事"])
    }

    func testOutlookFormatImport() {
        let headers = ["First Name", "Middle Name", "Last Name", "Company", "Job Title",
                       "Mobile Phone", "Home Phone", "E-mail Address", "Birthday"]
        let rows = [["太郎", "", "山田", "株式会社サンプル", "部長",
                     "090-1111-2222", "045-111-2222", "taro@example.com", "1990-01-02"]]
        let mapping = CSVSchema.defaultMapping(for: .outlook, headers: headers)
        let result = CSVSchema.contacts(from: CSVTable(headers: headers, rows: rows), mapping: mapping)
        let contact = result.contacts[0]
        XCTAssertEqual(contact.familyName, "山田")
        XCTAssertEqual(contact.organizationName, "株式会社サンプル")
        XCTAssertEqual(contact.phones.count, 2)
        XCTAssertEqual(contact.emails[0].value, "taro@example.com")
        XCTAssertEqual(contact.birthday, DateComponents(year: 1990, month: 1, day: 2))
    }

    // MARK: - その他

    func testExportFileName() {
        let date = Date(timeIntervalSince1970: 0)
        let name = CSVSchema.exportFileName(date: date)
        XCTAssertTrue(name.hasPrefix("連絡先_"))
        XCTAssertTrue(name.hasSuffix(".csv"))
        XCTAssertEqual(name.count, "連絡先_19700101_0900.csv".count)
    }

    func testColumnMappingCodableRoundTrip() throws {
        let mapping = ColumnMapping(name: "マイプリセット",
                                    assignments: [0: .familyName, 5: .phone1])
        let data = try JSONEncoder().encode(mapping)
        let decoded = try JSONDecoder().decode(ColumnMapping.self, from: data)
        XCTAssertEqual(decoded, mapping)
    }
}
