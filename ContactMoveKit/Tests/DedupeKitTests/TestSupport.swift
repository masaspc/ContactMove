import Foundation
import Models

/// テスト用の連絡先ビルダー(ラベルは電話= mobile、メール= home 固定)
func makeContact(
    id: UUID = UUID(),
    source: String? = nil,
    family: String = "",
    given: String = "",
    kanaFamily: String? = nil,
    kanaGiven: String? = nil,
    org: String? = nil,
    phones: [String] = [],
    emails: [String] = [],
    birthday: DateComponents? = nil,
    groups: [String] = []
) -> TransferContact {
    TransferContact(
        id: id,
        sourceIdentifier: source,
        givenName: given,
        familyName: family,
        phoneticGivenName: kanaGiven,
        phoneticFamilyName: kanaFamily,
        organizationName: org,
        phones: phones.map { .init(label: .mobile, value: $0) },
        emails: emails.map { .init(label: .home, value: $0) },
        birthday: birthday,
        groups: groups
    )
}
