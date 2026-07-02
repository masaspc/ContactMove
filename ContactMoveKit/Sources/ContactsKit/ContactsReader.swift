import Foundation
import Models

#if canImport(Contacts)
import Contacts

/// CNContactStore からの読み取り(仕様書 §2.2: 5,000件を10秒以内目標)。
public struct ContactsReader: Sendable {

    public init() {}

    /// アクセス可能な連絡先の総数(limited 時は許可された範囲のみ)。
    public func authorizedCount() throws -> Int {
        let store = CNContactStore()
        let request = CNContactFetchRequest(keysToFetch: [CNContactIdentifierKey as CNKeyDescriptor])
        var count = 0
        try store.enumerateContacts(with: request) { _, _ in count += 1 }
        return count
    }

    /// 全連絡先をストリーム読取して TransferContact へ変換する。
    /// sourceIdentifier には CNContact.identifier が入る。
    /// - Parameter onProgress: 変換済み件数(50件ごと+最後に呼ばれる)
    public func fetchAll(imageOption: ImageOption,
                         onProgress: (@Sendable (Int) -> Void)? = nil) async throws -> [TransferContact] {
        let option = imageOption
        return try await Task.detached(priority: .userInitiated) {
            let store = CNContactStore()

            // グループ名マップ(identifier → [グループ名])を先に構築
            var groupNames: [String: [String]] = [:]
            if let groups = try? store.groups(matching: nil) {
                for group in groups {
                    let predicate = CNContact.predicateForContactsInGroup(withIdentifier: group.identifier)
                    if let members = try? store.unifiedContacts(
                        matching: predicate,
                        keysToFetch: [CNContactIdentifierKey as CNKeyDescriptor]) {
                        for member in members {
                            groupNames[member.identifier, default: []].append(group.name)
                        }
                    }
                }
            }

            let request = CNContactFetchRequest(keysToFetch: ContactConverter.keysToFetch(imageOption: option))
            request.sortOrder = .userDefault

            var results: [TransferContact] = []
            var cancelled = false
            do {
                try store.enumerateContacts(with: request) { contact, stop in
                    if Task.isCancelled {
                        cancelled = true
                        stop.pointee = true
                        return
                    }
                    results.append(ContactConverter.transferContact(
                        from: contact,
                        imageOption: option,
                        groups: groupNames[contact.identifier] ?? []))
                    if results.count % 50 == 0 {
                        onProgress?(results.count)
                    }
                }
            } catch {
                throw Self.mapAccessError(error)
            }
            if cancelled { throw CancellationError() }
            onProgress?(results.count)
            return results
        }.value
    }

    static func mapAccessError(_ error: Error) -> Error {
        let nsError = error as NSError
        if nsError.domain == CNErrorDomain,
           nsError.code == CNError.Code.authorizationDenied.rawValue {
            return AppError.contactsAccessDenied
        }
        return error
    }
}

#else

/// Contacts framework が使えない環境(Linux 等)向けのスタブ。
public struct ContactsReader: Sendable {
    public init() {}
    public func authorizedCount() throws -> Int { throw AppError.contactsAccessDenied }
    public func fetchAll(imageOption: ImageOption,
                         onProgress: (@Sendable (Int) -> Void)? = nil) async throws -> [TransferContact] {
        throw AppError.contactsAccessDenied
    }
}

#endif
