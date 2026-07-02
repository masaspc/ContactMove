import XCTest
import Models
@testable import ContactsKit

#if canImport(Contacts)
import Contacts

/// UT-CNT-01: CNContact ⇄ TransferContact の全フィールド往復。
/// 実 CNContactStore へはアクセスしない(権限不要でCIでも実行可能)。
final class ContactConverterTests: XCTestCase {

    private func makeFullTransferContact() -> TransferContact {
        TransferContact(
            givenName: "太郎",
            familyName: "山田",
            middleName: "ミドル",
            phoneticGivenName: "タロウ",
            phoneticFamilyName: "ヤマダ",
            namePrefix: "Dr.",
            nameSuffix: "Jr.",
            organizationName: "株式会社サンプル",
            departmentName: "開発部",
            jobTitle: "エンジニア",
            phones: [
                .init(label: .mobile, value: "090-1111-2222"),
                .init(label: .work, value: "03-1111-2222"),
                .init(label: .iPhone, value: "080-3333-4444"),
                .init(label: .main, value: "045-555-6666"),
            ],
            emails: [
                .init(label: .home, value: "home@example.com"),
                .init(label: .work, value: "work@example.com"),
            ],
            postalAddresses: [
                .init(label: .home, postalCode: "100-0001", state: "東京都",
                      city: "千代田区", street: "千代田1-1", subLocality: "サンプルビル3F",
                      country: "日本"),
            ],
            urls: [.init(label: .other, value: "https://example.com")],
            birthday: DateComponents(year: 1990, month: 1, day: 2),
            imageData: Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]),
            groups: []
        )
    }

    func testTransferToCNToTransferRoundTrip() {
        let original = makeFullTransferContact()
        let cn = ContactConverter.makeCNMutableContact(from: original)
        // 画像は縮小せず(original)、そのまま往復させる
        var restored = ContactConverter.transferContact(from: cn, imageOption: .original)
        restored.sourceIdentifier = nil

        XCTAssertEqual(restored.givenName, original.givenName)
        XCTAssertEqual(restored.familyName, original.familyName)
        XCTAssertEqual(restored.middleName, original.middleName)
        XCTAssertEqual(restored.phoneticGivenName, original.phoneticGivenName)
        XCTAssertEqual(restored.phoneticFamilyName, original.phoneticFamilyName)
        XCTAssertEqual(restored.namePrefix, original.namePrefix)
        XCTAssertEqual(restored.nameSuffix, original.nameSuffix)
        XCTAssertEqual(restored.organizationName, original.organizationName)
        XCTAssertEqual(restored.departmentName, original.departmentName)
        XCTAssertEqual(restored.jobTitle, original.jobTitle)
        XCTAssertEqual(restored.phones.map(\.value), original.phones.map(\.value))
        XCTAssertEqual(restored.phones.map(\.label), original.phones.map(\.label))
        XCTAssertEqual(restored.emails.map(\.value), original.emails.map(\.value))
        XCTAssertEqual(restored.emails.map(\.label), original.emails.map(\.label))
        XCTAssertEqual(restored.postalAddresses, original.postalAddresses)
        XCTAssertEqual(restored.urls.map(\.value), original.urls.map(\.value))
        XCTAssertEqual(restored.birthday?.year, 1990)
        XCTAssertEqual(restored.birthday?.month, 1)
        XCTAssertEqual(restored.birthday?.day, 2)
        XCTAssertEqual(restored.imageData, original.imageData)
    }

    func testEmptyOptionalFieldsBecomeNil() {
        let cn = CNMutableContact()
        cn.givenName = "太郎"
        let restored = ContactConverter.transferContact(from: cn, imageOption: .excluded)
        XCTAssertNil(restored.middleName)
        XCTAssertNil(restored.organizationName)
        XCTAssertNil(restored.birthday)
        XCTAssertNil(restored.imageData)
        XCTAssertTrue(restored.phones.isEmpty)
    }

    func testSourceIdentifierIsSet() {
        let cn = CNMutableContact()
        cn.givenName = "太郎"
        let restored = ContactConverter.transferContact(from: cn, imageOption: .excluded)
        XCTAssertEqual(restored.sourceIdentifier, cn.identifier)
    }

    func testLabelMappingAllCases() {
        for label in TransferContact.ContactLabel.allCases {
            let cnLabel = ContactConverter.cnLabel(from: label)
            XCTAssertEqual(ContactConverter.label(fromCN: cnLabel), label,
                           "label \(label) failed to round-trip")
        }
        XCTAssertEqual(ContactConverter.label(fromCN: nil), .other)
        XCTAssertEqual(ContactConverter.label(fromCN: "独自ラベル"), .other)
    }

    func testExcludedImageOptionDropsImage() {
        let original = makeFullTransferContact()
        let cn = ContactConverter.makeCNMutableContact(from: original)
        let restored = ContactConverter.transferContact(from: cn, imageOption: .excluded)
        XCTAssertNil(restored.imageData)
    }
}

final class VCardCoderTests: XCTestCase {

    func testVCardRoundTrip() throws {
        let original = TransferContact(
            givenName: "太郎",
            familyName: "山田",
            phoneticGivenName: "タロウ",
            phoneticFamilyName: "ヤマダ",
            organizationName: "株式会社サンプル",
            phones: [.init(label: .mobile, value: "090-1111-2222")],
            emails: [.init(label: .home, value: "taro@example.com")],
            postalAddresses: [
                .init(label: .home, postalCode: "100-0001", state: "東京都",
                      city: "千代田区", street: "千代田1-1", country: "日本"),
            ],
            birthday: DateComponents(year: 1990, month: 1, day: 2)
        )
        let data = try VCardCoder.exportData([original])
        let restored = try VCardCoder.contacts(from: data)

        XCTAssertEqual(restored.count, 1)
        let contact = restored[0]
        XCTAssertNil(contact.sourceIdentifier)
        XCTAssertEqual(contact.givenName, "太郎")
        XCTAssertEqual(contact.familyName, "山田")
        XCTAssertEqual(contact.organizationName, "株式会社サンプル")
        XCTAssertEqual(contact.phones.first?.value, "090-1111-2222")
        XCTAssertEqual(contact.phones.first?.label, .mobile)
        XCTAssertEqual(contact.emails.first?.value, "taro@example.com")
        XCTAssertEqual(contact.postalAddresses.first?.state, "東京都")
        XCTAssertEqual(contact.birthday?.year, 1990)
    }

    func testVCardMultipleContacts() throws {
        let contacts = (0..<5).map {
            TransferContact(givenName: "名\($0)", familyName: "姓\($0)")
        }
        let data = try VCardCoder.exportData(contacts)
        let restored = try VCardCoder.contacts(from: data)
        XCTAssertEqual(restored.count, 5)
        XCTAssertEqual(restored.map(\.familyName), contacts.map(\.familyName))
    }

    func testVCardExportIncludesPhoto() throws {
        var contact = TransferContact(givenName: "太郎", familyName: "山田")
        contact.imageData = Data([0xFF, 0xD8, 0xFF, 0xE0])
        let data = try VCardCoder.exportData([contact])
        let text = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(text.contains("PHOTO"))
    }

    func testInvalidVCardThrows() {
        XCTAssertThrowsError(try VCardCoder.contacts(from: Data("これはvCardではない".utf8)))
    }

    func testExportFileName() {
        let name = VCardCoder.exportFileName(date: Date(timeIntervalSince1970: 0))
        XCTAssertTrue(name.hasPrefix("連絡先_"))
        XCTAssertTrue(name.hasSuffix(".vcf"))
    }
}

final class ContactsPermissionsTests: XCTestCase {
    @MainActor
    func testInitialStatusIsValid() {
        let permissions = ContactsPermissions()
        // 環境により値は異なるが、必ずいずれかの状態を取る
        XCTAssertTrue(ContactsAccessStatus.allCases.contains(permissions.status))
    }
}
#endif
