import Foundation
import Models

// MARK: - マージ計画(仕様書 §6.3 / §6.4)

/// 適用計画。ContactsKit の `ContactsApplier.apply(_:)` がこの計画を実行する。
public struct MergePlan: Sendable {
    /// 新規作成する連絡先
    public var creates: [TransferContact]
    /// 既存連絡先の更新(existing.sourceIdentifier 必須)
    public var updates: [MergeUpdate]
    /// 端末内整理でグループ統合後に削除する側
    public var deletes: [TransferContact]
    /// スキップ件数
    public var skippedCount: Int
    /// 変更内容の要約(例:「10件を新規作成、3件をマージ」)
    public var summary: String

    public struct MergeUpdate: Sendable {
        public var existing: TransferContact
        /// 適用後の完成形(id / sourceIdentifier は existing 側を維持)
        public var merged: TransferContact

        public init(existing: TransferContact, merged: TransferContact) {
            self.existing = existing
            self.merged = merged
        }
    }

    public init(
        creates: [TransferContact] = [],
        updates: [MergeUpdate] = [],
        deletes: [TransferContact] = [],
        skippedCount: Int = 0,
        summary: String = ""
    ) {
        self.creates = creates
        self.updates = updates
        self.deletes = deletes
        self.skippedCount = skippedCount
        self.summary = summary
    }
}

public enum MergePlanner {

    // MARK: - 取り込み時の計画生成

    /// analyze 結果を戦略に従って計画へ変換する。
    /// - duplicates(L1〜L3): merge/overwrite → updates、skip → skippedCount、
    ///   keepBoth → creates。
    /// - candidates(L4): `acceptedCandidates`(ユーザーが「統合する」を選んだ
    ///   DedupeMatch.id)に含まれるものはフィールドマージ(updates)、
    ///   含まれないものは新規作成(creates)。
    public static func plan(
        analysis: DedupeAnalysis,
        strategy: MergeStrategy,
        acceptedCandidates: Set<UUID>
    ) -> MergePlan {
        var creates = analysis.newContacts
        var updates: [MergePlan.MergeUpdate] = []
        var skipped = 0

        for match in analysis.duplicates {
            switch strategy {
            case .skip:
                skipped += 1
            case .merge, .overwrite:
                let merged = merge(existing: match.existing, incoming: match.incoming, strategy: strategy)
                updates.append(.init(existing: match.existing, merged: merged))
            case .keepBoth:
                creates.append(match.incoming)
            }
        }

        for match in analysis.candidates {
            if acceptedCandidates.contains(match.id) {
                let merged = merge(existing: match.existing, incoming: match.incoming, strategy: .merge)
                updates.append(.init(existing: match.existing, merged: merged))
            } else {
                creates.append(match.incoming)
            }
        }

        return MergePlan(
            creates: creates,
            updates: updates,
            deletes: [],
            skippedCount: skipped,
            summary: summaryText(created: creates.count, merged: updates.count,
                                 skipped: skipped, deleted: 0)
        )
    }

    // MARK: - 端末内整理の計画生成

    /// `acceptedGroupIDs` に含まれる各グループについて、情報量最大
    /// (非空フィールド数+複数値件数)のメンバーをベースに他メンバーを
    /// フィールドマージ → updates に1件、残りメンバーを deletes へ。
    /// 受理されなかったグループは skippedCount に数える。
    public static func plan(groups: [DuplicateGroup], acceptedGroupIDs: Set<UUID>) -> MergePlan {
        var updates: [MergePlan.MergeUpdate] = []
        var deletes: [TransferContact] = []
        var skipped = 0

        for group in groups {
            guard acceptedGroupIDs.contains(group.id), group.members.count >= 2 else {
                skipped += 1
                continue
            }
            let contacts = group.members.map(\.contact)

            var baseIndex = 0
            var bestScore = informationScore(contacts[0])
            for index in 1..<contacts.count {
                let score = informationScore(contacts[index])
                if score > bestScore {
                    bestScore = score
                    baseIndex = index
                }
            }

            let base = contacts[baseIndex]
            var merged = base
            for (index, contact) in contacts.enumerated() where index != baseIndex {
                merged = merge(existing: merged, incoming: contact, strategy: .merge)
                deletes.append(contact)
            }
            updates.append(.init(existing: base, merged: merged))
        }

        return MergePlan(
            creates: [],
            updates: updates,
            deletes: deletes,
            skippedCount: skipped,
            summary: summaryText(created: 0, merged: updates.count,
                                 skipped: skipped, deleted: deletes.count)
        )
    }

    // MARK: - フィールド単位マージ(§6.3 の表)

    /// 1件同士のマージ。結果の id / sourceIdentifier は existing 側を維持する
    /// (skip は existing、keepBoth は incoming をそのまま返す)。
    public static func merge(
        existing: TransferContact,
        incoming: TransferContact,
        strategy: MergeStrategy
    ) -> TransferContact {
        switch strategy {
        case .skip:
            return existing
        case .keepBoth:
            return incoming
        case .merge:
            return fieldMerge(existing: existing, incoming: incoming)
        case .overwrite:
            return overwriteMerge(existing: existing, incoming: incoming)
        }
    }

    /// マージ戦略: 単一値フィールドは既存優先(既存が空なら新規側を採用)。
    /// 複数値フィールドは「同ラベル同値(正規化比較)」の重複追加をせず、
    /// 新規側にしかない値のみ追加。
    private static func fieldMerge(existing: TransferContact, incoming: TransferContact) -> TransferContact {
        var result = existing

        // 単一値フィールド: 既存が空のときのみ補完
        result.givenName = filled(existing.givenName, fallback: incoming.givenName)
        result.familyName = filled(existing.familyName, fallback: incoming.familyName)
        result.middleName = filled(existing.middleName, fallback: incoming.middleName)
        result.phoneticGivenName = filled(existing.phoneticGivenName, fallback: incoming.phoneticGivenName)
        result.phoneticFamilyName = filled(existing.phoneticFamilyName, fallback: incoming.phoneticFamilyName)
        result.namePrefix = filled(existing.namePrefix, fallback: incoming.namePrefix)
        result.nameSuffix = filled(existing.nameSuffix, fallback: incoming.nameSuffix)
        result.organizationName = filled(existing.organizationName, fallback: incoming.organizationName)
        result.departmentName = filled(existing.departmentName, fallback: incoming.departmentName)
        result.jobTitle = filled(existing.jobTitle, fallback: incoming.jobTitle)
        if result.birthday == nil {
            result.birthday = incoming.birthday
        }
        if isEmptyData(result.imageData), !isEmptyData(incoming.imageData) {
            result.imageData = incoming.imageData
        }

        // 電話: 同ラベルで比較キーが交差するものは重複追加しない
        for phone in incoming.phones {
            let value = phone.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }
            let keys = ContactNormalizer.phoneComparisonKeys(phone.value)
            let isDuplicate = result.phones.contains { current in
                current.label == phone.label &&
                    !ContactNormalizer.phoneComparisonKeys(current.value).isDisjoint(with: keys)
            }
            if !isDuplicate { result.phones.append(phone) }
        }

        // メール: 同ラベル同値(小文字化比較)は重複追加しない
        for email in incoming.emails {
            let key = ContactNormalizer.normalizeEmail(email.value)
            guard !key.isEmpty else { continue }
            let isDuplicate = result.emails.contains { current in
                current.label == email.label &&
                    ContactNormalizer.normalizeEmail(current.value) == key
            }
            if !isDuplicate { result.emails.append(email) }
        }

        // 住所: 同ラベル・全構成要素一致(正規化比較)は重複追加しない
        for address in incoming.postalAddresses {
            guard addressHasContent(address) else { continue }
            let key = addressKey(address)
            let isDuplicate = result.postalAddresses.contains { addressKey($0) == key }
            if !isDuplicate { result.postalAddresses.append(address) }
        }

        // URL: 同ラベル同値(trim 比較)は重複追加しない
        for url in incoming.urls {
            let value = url.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }
            let isDuplicate = result.urls.contains { current in
                current.label == url.label &&
                    current.value.trimmingCharacters(in: .whitespacesAndNewlines) == value
            }
            if !isDuplicate { result.urls.append(url) }
        }

        // グループ: 同値(正規化比較)は重複追加しない
        for group in incoming.groups {
            let key = ContactNormalizer.normalizeName(group)
            guard !key.isEmpty else { continue }
            let isDuplicate = result.groups.contains { ContactNormalizer.normalizeName($0) == key }
            if !isDuplicate { result.groups.append(group) }
        }

        return result
    }

    /// 上書き戦略: 新規側が非空のフィールドで置換し、新規側が空のフィールドは
    /// 既存維持。複数値フィールドは新規側で置換(新規側が空配列なら既存維持)。
    private static func overwriteMerge(existing: TransferContact, incoming: TransferContact) -> TransferContact {
        var result = existing

        if !isBlank(incoming.givenName) { result.givenName = incoming.givenName }
        if !isBlank(incoming.familyName) { result.familyName = incoming.familyName }
        if let value = incoming.middleName, !isBlank(value) { result.middleName = value }
        if let value = incoming.phoneticGivenName, !isBlank(value) { result.phoneticGivenName = value }
        if let value = incoming.phoneticFamilyName, !isBlank(value) { result.phoneticFamilyName = value }
        if let value = incoming.namePrefix, !isBlank(value) { result.namePrefix = value }
        if let value = incoming.nameSuffix, !isBlank(value) { result.nameSuffix = value }
        if let value = incoming.organizationName, !isBlank(value) { result.organizationName = value }
        if let value = incoming.departmentName, !isBlank(value) { result.departmentName = value }
        if let value = incoming.jobTitle, !isBlank(value) { result.jobTitle = value }
        if incoming.birthday != nil { result.birthday = incoming.birthday }
        if !isEmptyData(incoming.imageData) { result.imageData = incoming.imageData }

        if !incoming.phones.isEmpty { result.phones = incoming.phones }
        if !incoming.emails.isEmpty { result.emails = incoming.emails }
        if !incoming.postalAddresses.isEmpty { result.postalAddresses = incoming.postalAddresses }
        if !incoming.urls.isEmpty { result.urls = incoming.urls }
        if !incoming.groups.isEmpty { result.groups = incoming.groups }

        return result
    }

    // MARK: - ヘルパー

    private static func summaryText(created: Int, merged: Int, skipped: Int, deleted: Int) -> String {
        var parts: [String] = []
        if created > 0 { parts.append("\(created)件を新規作成") }
        if merged > 0 { parts.append("\(merged)件をマージ") }
        if skipped > 0 { parts.append("\(skipped)件をスキップ") }
        if deleted > 0 { parts.append("\(deleted)件を削除") }
        return parts.isEmpty ? "変更はありません" : parts.joined(separator: "、")
    }

    private static func isBlank(_ value: String) -> Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func isEmptyData(_ data: Data?) -> Bool {
        data?.isEmpty ?? true
    }

    private static func filled(_ existing: String, fallback: String) -> String {
        isBlank(existing) && !isBlank(fallback) ? fallback : existing
    }

    private static func filled(_ existing: String?, fallback: String?) -> String? {
        if let value = existing, !isBlank(value) { return existing }
        if let value = fallback, !isBlank(value) { return fallback }
        return existing
    }

    private static func addressHasContent(_ address: TransferContact.PostalAddress) -> Bool {
        let fields = [address.postalCode, address.state, address.city,
                      address.street, address.subLocality, address.country]
        return fields.contains { !isBlank($0 ?? "") }
    }

    private static func addressKey(_ address: TransferContact.PostalAddress) -> String {
        let fields = [address.label.rawValue, address.postalCode ?? "", address.state ?? "",
                      address.city ?? "", address.street ?? "", address.subLocality ?? "",
                      address.country ?? ""]
        return fields.map(ContactNormalizer.normalizeName).joined(separator: "\u{1F}")
    }

    /// 端末内整理でベースを選ぶための情報量スコア
    /// (非空の単一値フィールド数 + 複数値フィールドの件数合計)。
    static func informationScore(_ contact: TransferContact) -> Int {
        var score = 0
        let singles: [String?] = [
            contact.givenName, contact.familyName, contact.middleName,
            contact.phoneticGivenName, contact.phoneticFamilyName,
            contact.namePrefix, contact.nameSuffix,
            contact.organizationName, contact.departmentName, contact.jobTitle,
        ]
        score += singles.filter { !isBlank($0 ?? "") }.count
        if contact.birthday != nil { score += 1 }
        if !isEmptyData(contact.imageData) { score += 1 }
        score += contact.phones.count + contact.emails.count
            + contact.postalAddresses.count + contact.urls.count + contact.groups.count
        return score
    }
}
