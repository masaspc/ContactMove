import Foundation

/// 転送・CSV・重複統合で共通利用する中間モデル(仕様書 §9.1)。
/// CNContact とは独立した Codable なデータ構造。note フィールドは
/// Entitlement 承認が必要なため MVP では扱わない。
public struct TransferContact: Codable, Identifiable, Hashable, Sendable {
    /// アプリ内一時ID(CNContact.identifier とは別)
    public var id: UUID
    /// 端末内の既存連絡先を指す CNContact.identifier(取り込み由来の場合は nil)
    public var sourceIdentifier: String?

    public var givenName: String
    public var familyName: String
    public var middleName: String?
    public var phoneticGivenName: String?
    public var phoneticFamilyName: String?
    public var namePrefix: String?
    public var nameSuffix: String?
    public var organizationName: String?
    public var departmentName: String?
    public var jobTitle: String?
    public var phones: [LabeledValue]
    public var emails: [LabeledValue]
    public var postalAddresses: [PostalAddress]
    public var urls: [LabeledValue]
    public var birthday: DateComponents?
    /// 縮小済みJPEG(設定に依存)
    public var imageData: Data?
    public var groups: [String]

    public init(
        id: UUID = UUID(),
        sourceIdentifier: String? = nil,
        givenName: String = "",
        familyName: String = "",
        middleName: String? = nil,
        phoneticGivenName: String? = nil,
        phoneticFamilyName: String? = nil,
        namePrefix: String? = nil,
        nameSuffix: String? = nil,
        organizationName: String? = nil,
        departmentName: String? = nil,
        jobTitle: String? = nil,
        phones: [LabeledValue] = [],
        emails: [LabeledValue] = [],
        postalAddresses: [PostalAddress] = [],
        urls: [LabeledValue] = [],
        birthday: DateComponents? = nil,
        imageData: Data? = nil,
        groups: [String] = []
    ) {
        self.id = id
        self.sourceIdentifier = sourceIdentifier
        self.givenName = givenName
        self.familyName = familyName
        self.middleName = middleName
        self.phoneticGivenName = phoneticGivenName
        self.phoneticFamilyName = phoneticFamilyName
        self.namePrefix = namePrefix
        self.nameSuffix = nameSuffix
        self.organizationName = organizationName
        self.departmentName = departmentName
        self.jobTitle = jobTitle
        self.phones = phones
        self.emails = emails
        self.postalAddresses = postalAddresses
        self.urls = urls
        self.birthday = birthday
        self.imageData = imageData
        self.groups = groups
    }

    public struct LabeledValue: Codable, Hashable, Sendable {
        public var label: ContactLabel
        public var value: String

        public init(label: ContactLabel, value: String) {
            self.label = label
            self.value = value
        }
    }

    public enum ContactLabel: String, Codable, CaseIterable, Sendable {
        case home, work, mobile, iPhone, main, other
    }

    public struct PostalAddress: Codable, Hashable, Sendable {
        public var label: ContactLabel
        public var postalCode: String?
        /// 都道府県
        public var state: String?
        public var city: String?
        public var street: String?
        /// 建物名相当
        public var subLocality: String?
        public var country: String?

        public init(
            label: ContactLabel = .home,
            postalCode: String? = nil,
            state: String? = nil,
            city: String? = nil,
            street: String? = nil,
            subLocality: String? = nil,
            country: String? = nil
        ) {
            self.label = label
            self.postalCode = postalCode
            self.state = state
            self.city = city
            self.street = street
            self.subLocality = subLocality
            self.country = country
        }
    }
}

public extension TransferContact {
    /// 一覧・レポート表示用の表示名(姓 名 → 組織名 → 電話/メールの順でフォールバック)
    var displayName: String {
        let name = [familyName, middleName ?? "", givenName]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if !name.isEmpty { return name }
        if let org = organizationName, !org.isEmpty { return org }
        if let phone = phones.first?.value, !phone.isEmpty { return phone }
        if let email = emails.first?.value, !email.isEmpty { return email }
        return "(名前なし)"
    }

    /// 氏名・電話・メールが全て空(インポート時のスキップ判定に使用)
    var isEffectivelyEmpty: Bool {
        givenName.isEmpty && familyName.isEmpty
            && (organizationName ?? "").isEmpty
            && phones.allSatisfy { $0.value.isEmpty }
            && emails.allSatisfy { $0.value.isEmpty }
    }
}
