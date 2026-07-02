import Foundation
import Models

#if canImport(Contacts)
import Contacts

/// vCard 3.0 の入出力(仕様書 UC-08 / T15)。
/// `CNContactVCardSerialization` を使用する。
/// 注意: CNContactVCardSerialization.data(with:) は既定で PHOTO を含めないため、
/// エクスポート時は PHOTO 行を手動で埋め込む。
public enum VCardCoder {

    public static func exportData(_ contacts: [TransferContact]) throws -> Data {
        var lines: [String] = []
        for contact in contacts {
            let cn = ContactConverter.makeCNMutableContact(from: contact)
            let single = try CNContactVCardSerialization.data(with: [cn])
            guard var text = String(data: single, encoding: .utf8) else {
                throw AppError.vCardParseFailed
            }
            // PHOTO の手動埋め込み(END:VCARD の直前に挿入)
            if let imageData = contact.imageData, !imageData.isEmpty {
                let base64 = imageData.base64EncodedString()
                let photoLine = "PHOTO;ENCODING=b;TYPE=JPEG:\(base64)\r\n"
                if let range = text.range(of: "END:VCARD") {
                    text.replaceSubrange(range.lowerBound..<range.lowerBound, with: photoLine)
                }
            }
            lines.append(text)
        }
        return Data(lines.joined().utf8)
    }

    public static func contacts(from data: Data) throws -> [TransferContact] {
        let cnContacts: [CNContact]
        do {
            cnContacts = try CNContactVCardSerialization.contacts(with: data)
        } catch {
            throw AppError.vCardParseFailed
        }
        // 1件も解釈できなかった場合もエラー扱い(空の .vcf を弾く)
        guard !cnContacts.isEmpty else { throw AppError.vCardParseFailed }
        return cnContacts.map { contact in
            var result = ContactConverter.transferContact(from: contact, imageOption: .original)
            result.sourceIdentifier = nil  // 取り込みデータは既存連絡先と紐付けない
            return result
        }
    }

    /// `連絡先_YYYYMMDD_HHmm.vcf`
    public static func exportFileName(date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd_HHmm"
        return "連絡先_\(formatter.string(from: date)).vcf"
    }
}

#else

/// Contacts framework が使えない環境(Linux 等)向けのスタブ。
public enum VCardCoder {
    public static func exportData(_ contacts: [TransferContact]) throws -> Data {
        throw AppError.vCardParseFailed
    }
    public static func contacts(from data: Data) throws -> [TransferContact] {
        throw AppError.vCardParseFailed
    }
    public static func exportFileName(date: Date = Date()) -> String {
        "連絡先.vcf"
    }
}

#endif
