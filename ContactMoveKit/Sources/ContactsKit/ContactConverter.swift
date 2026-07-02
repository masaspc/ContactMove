import Foundation
import Models

#if canImport(Contacts)
import Contacts
#if canImport(UIKit)
import UIKit
#endif

/// CNContact ⇄ TransferContact の変換(仕様書 §9.1)。
/// note フィールドは Entitlement 承認が必要なため一切扱わない。
enum ContactConverter {

    // MARK: - ラベル変換

    static func label(fromCN cnLabel: String?) -> TransferContact.ContactLabel {
        guard let cnLabel else { return .other }
        switch cnLabel {
        case CNLabelHome: return .home
        case CNLabelWork: return .work
        case CNLabelPhoneNumberMobile: return .mobile
        case CNLabelPhoneNumberiPhone: return .iPhone
        case CNLabelPhoneNumberMain: return .main
        default: return .other
        }
    }

    static func cnLabel(from label: TransferContact.ContactLabel) -> String {
        switch label {
        case .home: return CNLabelHome
        case .work: return CNLabelWork
        case .mobile: return CNLabelPhoneNumberMobile
        case .iPhone: return CNLabelPhoneNumberiPhone
        case .main: return CNLabelPhoneNumberMain
        case .other: return CNLabelOther
        }
    }

    // MARK: - 読み取りに必要なキー

    static func keysToFetch(imageOption: ImageOption) -> [CNKeyDescriptor] {
        var keys: [String] = [
            CNContactIdentifierKey,
            CNContactGivenNameKey, CNContactFamilyNameKey, CNContactMiddleNameKey,
            CNContactNamePrefixKey, CNContactNameSuffixKey,
            CNContactPhoneticGivenNameKey, CNContactPhoneticFamilyNameKey,
            CNContactOrganizationNameKey, CNContactDepartmentNameKey, CNContactJobTitleKey,
            CNContactPhoneNumbersKey, CNContactEmailAddressesKey,
            CNContactPostalAddressesKey, CNContactUrlAddressesKey,
            CNContactBirthdayKey,
        ]
        if imageOption != .excluded {
            keys.append(CNContactImageDataKey)
            keys.append(CNContactImageDataAvailableKey)
        }
        return keys as [CNKeyDescriptor]
    }

    // MARK: - CNContact → TransferContact

    static func transferContact(from contact: CNContact,
                                imageOption: ImageOption,
                                groups: [String] = []) -> TransferContact {
        var result = TransferContact(
            sourceIdentifier: contact.identifier,
            givenName: contact.givenName,
            familyName: contact.familyName,
            middleName: contact.middleName.isEmpty ? nil : contact.middleName,
            phoneticGivenName: contact.phoneticGivenName.isEmpty ? nil : contact.phoneticGivenName,
            phoneticFamilyName: contact.phoneticFamilyName.isEmpty ? nil : contact.phoneticFamilyName,
            namePrefix: contact.namePrefix.isEmpty ? nil : contact.namePrefix,
            nameSuffix: contact.nameSuffix.isEmpty ? nil : contact.nameSuffix,
            organizationName: contact.organizationName.isEmpty ? nil : contact.organizationName,
            departmentName: contact.departmentName.isEmpty ? nil : contact.departmentName,
            jobTitle: contact.jobTitle.isEmpty ? nil : contact.jobTitle,
            groups: groups
        )

        result.phones = contact.phoneNumbers.map {
            .init(label: label(fromCN: $0.label), value: $0.value.stringValue)
        }
        result.emails = contact.emailAddresses.map {
            .init(label: label(fromCN: $0.label), value: $0.value as String)
        }
        result.postalAddresses = contact.postalAddresses.map { labeled in
            let address = labeled.value
            return TransferContact.PostalAddress(
                label: label(fromCN: labeled.label),
                postalCode: address.postalCode.isEmpty ? nil : address.postalCode,
                state: address.state.isEmpty ? nil : address.state,
                city: address.city.isEmpty ? nil : address.city,
                street: address.street.isEmpty ? nil : address.street,
                subLocality: address.subLocality.isEmpty ? nil : address.subLocality,
                country: address.country.isEmpty ? nil : address.country)
        }
        result.urls = contact.urlAddresses.map {
            .init(label: label(fromCN: $0.label), value: $0.value as String)
        }
        result.birthday = contact.birthday

        if imageOption != .excluded,
           contact.isKeyAvailable(CNContactImageDataKey),
           let imageData = contact.imageData {
            switch imageOption {
            case .scaled:
                result.imageData = scaledJPEG(imageData) ?? imageData
            case .original:
                result.imageData = imageData
            case .excluded:
                break
            }
        }
        return result
    }

    // MARK: - TransferContact → CNMutableContact

    static func makeCNMutableContact(from contact: TransferContact) -> CNMutableContact {
        let cn = CNMutableContact()
        apply(contact, to: cn)
        return cn
    }

    /// TransferContact の内容を CNMutableContact へ全フィールド反映する
    /// (更新時は merged の完成形をそのまま書く)。
    static func apply(_ contact: TransferContact, to cn: CNMutableContact) {
        cn.givenName = contact.givenName
        cn.familyName = contact.familyName
        cn.middleName = contact.middleName ?? ""
        cn.namePrefix = contact.namePrefix ?? ""
        cn.nameSuffix = contact.nameSuffix ?? ""
        cn.phoneticGivenName = contact.phoneticGivenName ?? ""
        cn.phoneticFamilyName = contact.phoneticFamilyName ?? ""
        cn.organizationName = contact.organizationName ?? ""
        cn.departmentName = contact.departmentName ?? ""
        cn.jobTitle = contact.jobTitle ?? ""

        cn.phoneNumbers = contact.phones
            .filter { !$0.value.isEmpty }
            .map { CNLabeledValue(label: cnLabel(from: $0.label),
                                  value: CNPhoneNumber(stringValue: $0.value)) }
        cn.emailAddresses = contact.emails
            .filter { !$0.value.isEmpty }
            .map { CNLabeledValue(label: cnLabel(from: $0.label),
                                  value: $0.value as NSString) }
        cn.postalAddresses = contact.postalAddresses.map { address in
            let postal = CNMutablePostalAddress()
            postal.postalCode = address.postalCode ?? ""
            postal.state = address.state ?? ""
            postal.city = address.city ?? ""
            postal.street = address.street ?? ""
            postal.subLocality = address.subLocality ?? ""
            postal.country = address.country ?? ""
            return CNLabeledValue(label: cnLabel(from: address.label),
                                  value: postal.copy() as! CNPostalAddress)
        }
        cn.urlAddresses = contact.urls
            .filter { !$0.value.isEmpty }
            .map { CNLabeledValue(label: cnLabel(from: $0.label),
                                  value: $0.value as NSString) }
        cn.birthday = contact.birthday
        cn.imageData = contact.imageData
    }

    // MARK: - 画像縮小(長辺512px・JPEG品質0.7、仕様書 §2.2)

    static func scaledJPEG(_ data: Data,
                           maxDimension: CGFloat = 512,
                           quality: CGFloat = 0.7) -> Data? {
        #if canImport(UIKit)
        guard let image = UIImage(data: data) else { return nil }
        let longest = max(image.size.width, image.size.height)
        guard longest > 0 else { return nil }
        if longest <= maxDimension {
            return image.jpegData(compressionQuality: quality)
        }
        let scale = maxDimension / longest
        let newSize = CGSize(width: floor(image.size.width * scale),
                             height: floor(image.size.height * scale))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        return resized.jpegData(compressionQuality: quality)
        #else
        // UIKit が無い環境(macOS の swift test 等)では縮小せずそのまま返す
        return data
        #endif
    }
}

#endif
