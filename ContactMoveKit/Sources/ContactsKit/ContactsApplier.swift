import Foundation
import Models
import DedupeKit

#if canImport(Contacts)
import Contacts

/// MergePlan を CNSaveRequest で適用する(仕様書 §6.4)。
/// 100件単位でバッチ実行し、バッチ成功ごとに進捗を通知する。
/// バッチ全体が失敗した場合は1件ずつ実行し直して失敗個体を特定する。
/// Task キャンセル時は完了バッチまで確定し `AppError.cancelled` を投げる。
public struct ContactsApplier: Sendable {

    public struct ApplyProgress: Sendable {
        public let processed: Int
        public let total: Int

        public init(processed: Int, total: Int) {
            self.processed = processed
            self.total = total
        }
    }

    static let batchSize = 100

    public init() {}

    public func apply(_ plan: MergePlan,
                      onProgress: (@Sendable (ApplyProgress) -> Void)? = nil) async throws -> TransferResult {
        try await Task.detached(priority: .userInitiated) {
            let store = CNContactStore()

            // 作業項目の組み立て
            var items: [WorkItem] = []
            items.append(contentsOf: plan.creates.map { .create($0) })
            items.append(contentsOf: plan.updates.map {
                .update(existingID: $0.existing.sourceIdentifier, merged: $0.merged)
            })
            items.append(contentsOf: plan.deletes.map {
                .delete(identifier: $0.sourceIdentifier, displayName: $0.displayName)
            })
            let total = items.count

            // 必要なグループを解決(無ければ作成)。新規作成分のみに適用する。
            let groupNames = Set(plan.creates.flatMap(\.groups))
            let groupsByName = Self.resolveGroups(named: groupNames, store: store)

            var created = 0
            var merged = 0
            var failed: [TransferResult.FailedItem] = []
            var processed = 0

            var batchStart = 0
            while batchStart < items.count {
                if Task.isCancelled {
                    throw AppError.cancelled(completedCount: processed)
                }
                let batch = Array(items[batchStart..<min(batchStart + Self.batchSize, items.count)])
                let errors = Self.execute(batch: batch, store: store, groupsByName: groupsByName)

                for (item, error) in zip(batch, errors) {
                    processed += 1
                    if let error {
                        failed.append(.init(displayName: item.displayName,
                                            reason: error.localizedDescription))
                    } else {
                        switch item {
                        case .create: created += 1
                        case .update: merged += 1
                        case .delete: break
                        }
                    }
                }
                onProgress?(ApplyProgress(processed: processed, total: total))
                batchStart += Self.batchSize
            }

            return TransferResult(
                received: total + plan.skippedCount,
                created: created,
                merged: merged,
                skipped: plan.skippedCount,
                failed: failed)
        }.value
    }

    // MARK: - 内部実装

    private enum WorkItem: Sendable {
        case create(TransferContact)
        case update(existingID: String?, merged: TransferContact)
        case delete(identifier: String?, displayName: String)

        var displayName: String {
            switch self {
            case .create(let contact): return contact.displayName
            case .update(_, let merged): return merged.displayName
            case .delete(_, let name): return name
            }
        }
    }

    /// グループ名 → CNGroup。存在しないグループは作成する(失敗したものは除外)。
    private static func resolveGroups(named names: Set<String>,
                                      store: CNContactStore) -> [String: CNGroup] {
        var result: [String: CNGroup] = [:]
        guard !names.isEmpty else { return result }
        for group in (try? store.groups(matching: nil)) ?? [] {
            result[group.name] = group
        }
        for name in names where result[name] == nil && !name.isEmpty {
            let newGroup = CNMutableGroup()
            newGroup.name = name
            let request = CNSaveRequest()
            request.add(newGroup, toContainerWithIdentifier: nil)
            if (try? store.execute(request)) != nil {
                result[name] = newGroup
            }
        }
        return result
    }

    /// バッチを1つの CNSaveRequest で実行。失敗したら1件ずつ再実行して
    /// 失敗個体を特定する。戻り値は各項目に対応するエラー(成功は nil)。
    private static func execute(batch: [WorkItem], store: CNContactStore,
                                groupsByName: [String: CNGroup]) -> [Error?] {
        if performSave(batch, store: store, groupsByName: groupsByName) == nil {
            return Array(repeating: nil, count: batch.count)
        }
        return batch.map { performSave([$0], store: store, groupsByName: groupsByName) }
    }

    private static func performSave(_ items: [WorkItem], store: CNContactStore,
                                    groupsByName: [String: CNGroup]) -> Error? {
        let request = CNSaveRequest()
        do {
            for item in items {
                switch item {
                case .create(let contact):
                    let cn = ContactConverter.makeCNMutableContact(from: contact)
                    request.add(cn, toContainerWithIdentifier: nil)
                    for groupName in contact.groups {
                        if let group = groupsByName[groupName] {
                            request.addMember(cn, to: group)
                        }
                    }

                case .update(let existingID, let merged):
                    guard let existingID else {
                        throw AppError.saveFailed(underlying: "更新対象の連絡先IDがありません")
                    }
                    let existing = try store.unifiedContact(
                        withIdentifier: existingID,
                        keysToFetch: ContactConverter.keysToFetch(imageOption: .original))
                    guard let mutable = existing.mutableCopy() as? CNMutableContact else {
                        throw AppError.saveFailed(underlying: "連絡先を編集用に複製できませんでした")
                    }
                    // merged は適用後の完成形なので全フィールドを反映する。
                    // グループ所属の変更は更新では扱わない(既存の所属を維持)。
                    ContactConverter.apply(merged, to: mutable)
                    request.update(mutable)

                case .delete(let identifier, _):
                    guard let identifier else {
                        throw AppError.saveFailed(underlying: "削除対象の連絡先IDがありません")
                    }
                    let existing = try store.unifiedContact(
                        withIdentifier: identifier,
                        keysToFetch: [CNContactIdentifierKey as CNKeyDescriptor])
                    guard let mutable = existing.mutableCopy() as? CNMutableContact else {
                        throw AppError.saveFailed(underlying: "連絡先を編集用に複製できませんでした")
                    }
                    request.delete(mutable)
                }
            }
            try store.execute(request)
            return nil
        } catch {
            return error
        }
    }
}

#else

/// Contacts framework が使えない環境(Linux 等)向けのスタブ。
public struct ContactsApplier: Sendable {
    public struct ApplyProgress: Sendable {
        public let processed: Int
        public let total: Int
        public init(processed: Int, total: Int) {
            self.processed = processed
            self.total = total
        }
    }

    public init() {}

    public func apply(_ plan: MergePlan,
                      onProgress: (@Sendable (ApplyProgress) -> Void)? = nil) async throws -> TransferResult {
        throw AppError.contactsAccessDenied
    }
}

#endif
