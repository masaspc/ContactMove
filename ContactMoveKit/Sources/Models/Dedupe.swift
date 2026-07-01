import Foundation

// MARK: - 重複判定モデル(仕様書 §9.3 / §6)

/// 重複グループのメンバー参照。既存連絡先(CNContact.identifier)か
/// 取り込み中データ(TransferContact.id)のどちらかを指す。
public enum ContactRef: Hashable, Sendable {
    case existing(identifier: String, contact: TransferContact)
    case incoming(TransferContact)

    public var contact: TransferContact {
        switch self {
        case .existing(_, let contact): return contact
        case .incoming(let contact): return contact
        }
    }

    public var isExisting: Bool {
        if case .existing = self { return true }
        return false
    }
}

/// 重複と判定された(または候補の)連絡先グループ
public struct DuplicateGroup: Identifiable, Sendable {
    public let id: UUID
    public var members: [ContactRef]
    /// .high(L1電話/L2メール一致) / .medium(L3) / .candidate(L4: 自動統合しない)
    public var confidence: Confidence

    public enum Confidence: Comparable, Sendable {
        case candidate, medium, high
    }

    public init(id: UUID = UUID(), members: [ContactRef], confidence: Confidence) {
        self.id = id
        self.members = members
        self.confidence = confidence
    }
}

/// 統合戦略(仕様書 §6.3)
public enum MergeStrategy: String, CaseIterable, Codable, Sendable {
    /// 既存を変更せず、重複した取り込み行を捨てる(既定)
    case skip
    /// 既存レコードに「新規側にしかない値」を追加(推奨)
    case merge
    /// 新規側の値でフィールドを置換(新規側が空のフィールドは既存維持)
    case overwrite
    /// 無条件で新規作成
    case keepBoth
}
