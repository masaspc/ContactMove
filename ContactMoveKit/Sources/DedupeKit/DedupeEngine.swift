import Foundation
import Models

// MARK: - マッチングレベル(仕様書 §6.2)

/// 段階マッチングの判定レベル。数値が大きいほど確度が高い。
public enum MatchLevel: Int, Sendable, Comparable {
    /// L4: 姓名完全一致のみ(候補。自動統合しない)
    case l4NameOnly = 1
    /// L3: 姓名完全一致 かつ(組織一致 or ふりがな一致 or 誕生日一致)
    case l3NamePlus
    /// L2: 正規化メールが1つでも一致
    case l2Email
    /// L1: 正規化電話番号が1つでも一致
    case l1Phone

    public static func < (lhs: MatchLevel, rhs: MatchLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - 判定結果

/// 既存1件と取り込み1件のマッチ。id は incoming.id と同一
/// (L4 候補確認 UI で acceptedCandidates に使う)。
public struct DedupeMatch: Sendable, Identifiable {
    public let id: UUID
    public var existing: TransferContact
    public var incoming: TransferContact
    public var level: MatchLevel

    public init(existing: TransferContact, incoming: TransferContact, level: MatchLevel) {
        self.id = incoming.id
        self.existing = existing
        self.incoming = incoming
        self.level = level
    }
}

/// analyze の結果。newContacts は新規作成、duplicates(L1〜L3)は戦略に従い
/// 自動処理、candidates(L4)はユーザーが1件ずつ確認する。
public struct DedupeAnalysis: Sendable {
    public var newContacts: [TransferContact]
    public var duplicates: [DedupeMatch]
    public var candidates: [DedupeMatch]

    public init(
        newContacts: [TransferContact] = [],
        duplicates: [DedupeMatch] = [],
        candidates: [DedupeMatch] = []
    ) {
        self.newContacts = newContacts
        self.duplicates = duplicates
        self.candidates = candidates
    }
}

// MARK: - エンジン

public struct DedupeEngine: Sendable {

    public init() {}

    /// 取り込みデータを既存連絡先と突き合わせる。
    /// 既存側の電話キー/メール/氏名で辞書インデックスを構築し O(N+M) で処理する
    /// (5,000件想定)。1つの incoming は「最初にマッチした既存1件」と組にし、
    /// レベルは L1 > L2 > L3 > L4 の順で高い方を優先する。
    public func analyze(existing: [TransferContact], incoming: [TransferContact]) -> DedupeAnalysis {
        // --- 既存側インデックス構築(O(N)) ---
        var phoneIndex: [String: Int] = [:]   // 電話比較キー → 最初の existing index
        var emailIndex: [String: Int] = [:]   // 正規化メール → 最初の existing index
        var nameIndex: [String: [Int]] = [:]  // 姓名キー → existing index 列

        for (index, contact) in existing.enumerated() {
            for phone in contact.phones {
                for key in ContactNormalizer.phoneComparisonKeys(phone.value)
                where phoneIndex[key] == nil {
                    phoneIndex[key] = index
                }
            }
            for email in contact.emails {
                let key = ContactNormalizer.normalizeEmail(email.value)
                if !key.isEmpty, emailIndex[key] == nil {
                    emailIndex[key] = index
                }
            }
            if let key = Self.nameKey(contact) {
                nameIndex[key, default: []].append(index)
            }
        }

        // --- 取り込み側の突き合わせ(O(M)) ---
        var analysis = DedupeAnalysis()

        for candidate in incoming {
            var matched: (index: Int, level: MatchLevel)?

            // L1: 電話キーの交差
            l1: for phone in candidate.phones {
                for key in ContactNormalizer.phoneComparisonKeys(phone.value) {
                    if let index = phoneIndex[key] {
                        matched = (index, .l1Phone)
                        break l1
                    }
                }
            }

            // L2: 正規化メール一致
            if matched == nil {
                for email in candidate.emails {
                    let key = ContactNormalizer.normalizeEmail(email.value)
                    if !key.isEmpty, let index = emailIndex[key] {
                        matched = (index, .l2Email)
                        break
                    }
                }
            }

            // L3/L4: 姓名完全一致(姓名両方空は対象外)
            if matched == nil, let key = Self.nameKey(candidate), let indices = nameIndex[key] {
                if let index = indices.first(where: { Self.auxiliaryMatch(existing[$0], candidate) }) {
                    matched = (index, .l3NamePlus)
                } else if let index = indices.first {
                    matched = (index, .l4NameOnly)
                }
            }

            if let (index, level) = matched {
                let match = DedupeMatch(existing: existing[index], incoming: candidate, level: level)
                if level == .l4NameOnly {
                    analysis.candidates.append(match)
                } else {
                    analysis.duplicates.append(match)
                }
            } else {
                analysis.newContacts.append(candidate)
            }
        }

        return analysis
    }

    /// 端末内重複整理用: L1〜L3 キーで Union-Find グルーピングし、
    /// 2件以上のグループのみ返す(推移閉包: A-B が電話、B-C がメールで
    /// 一致すれば A/B/C は1グループ)。
    /// confidence はグループ形成に使った最高レベル(L1/L2 → .high、L3 → .medium)。
    public func duplicateGroups(in contacts: [TransferContact]) -> [DuplicateGroup] {
        let count = contacts.count
        guard count >= 2 else { return [] }

        var parent = Array(0..<count)
        var groupLevel: [Int: MatchLevel] = [:]  // root index → 最高レベル

        func find(_ x: Int) -> Int {
            var root = x
            while parent[root] != root { root = parent[root] }
            // 経路圧縮
            var current = x
            while parent[current] != root {
                let next = parent[current]
                parent[current] = root
                current = next
            }
            return root
        }

        func union(_ a: Int, _ b: Int, level: MatchLevel) {
            let rootA = find(a)
            let rootB = find(b)
            var best = level
            if let levelA = groupLevel[rootA] { best = max(best, levelA) }
            if let levelB = groupLevel[rootB] { best = max(best, levelB) }
            if rootA != rootB {
                parent[rootB] = rootA
                groupLevel[rootB] = nil
            }
            groupLevel[rootA] = best
        }

        // L1: 電話キー
        var phoneOwner: [String: Int] = [:]
        for (index, contact) in contacts.enumerated() {
            for phone in contact.phones {
                for key in ContactNormalizer.phoneComparisonKeys(phone.value) {
                    if let owner = phoneOwner[key] {
                        union(owner, index, level: .l1Phone)
                    } else {
                        phoneOwner[key] = index
                    }
                }
            }
        }

        // L2: メールキー
        var emailOwner: [String: Int] = [:]
        for (index, contact) in contacts.enumerated() {
            for email in contact.emails {
                let key = ContactNormalizer.normalizeEmail(email.value)
                guard !key.isEmpty else { continue }
                if let owner = emailOwner[key] {
                    union(owner, index, level: .l2Email)
                } else {
                    emailOwner[key] = index
                }
            }
        }

        // L3: 同一姓名バケット内で補助キー(組織/ふりがな/誕生日)一致
        var nameBuckets: [String: [Int]] = [:]
        for (index, contact) in contacts.enumerated() {
            if let key = Self.nameKey(contact) {
                nameBuckets[key, default: []].append(index)
            }
        }
        for indices in nameBuckets.values where indices.count > 1 {
            for i in 0..<(indices.count - 1) {
                for j in (i + 1)..<indices.count
                where Self.auxiliaryMatch(contacts[indices[i]], contacts[indices[j]]) {
                    union(indices[i], indices[j], level: .l3NamePlus)
                }
            }
        }

        // グループ収集(出現順を維持)
        var membersByRoot: [Int: [Int]] = [:]
        var rootOrder: [Int] = []
        for index in 0..<count {
            let root = find(index)
            if membersByRoot[root] == nil { rootOrder.append(root) }
            membersByRoot[root, default: []].append(index)
        }

        var groups: [DuplicateGroup] = []
        for root in rootOrder {
            guard let memberIndices = membersByRoot[root], memberIndices.count >= 2 else { continue }
            let refs: [ContactRef] = memberIndices.map { index in
                let contact = contacts[index]
                if let identifier = contact.sourceIdentifier {
                    return .existing(identifier: identifier, contact: contact)
                }
                return .incoming(contact)
            }
            let level = groupLevel[root] ?? .l3NamePlus
            let confidence: DuplicateGroup.Confidence = level >= .l2Email ? .high : .medium
            groups.append(DuplicateGroup(members: refs, confidence: confidence))
        }
        return groups
    }

    // MARK: - キー生成・補助判定

    /// 姓名キー。姓名とも空なら nil(L3/L4 判定の対象外)。
    static func nameKey(_ contact: TransferContact) -> String? {
        let family = ContactNormalizer.normalizeName(contact.familyName)
        let given = ContactNormalizer.normalizeName(contact.givenName)
        if family.isEmpty && given.isEmpty { return nil }
        return family + "\u{1F}" + given
    }

    /// ふりがなキー(カタカナ統一)。両フィールドとも空なら nil。
    static func kanaKey(_ contact: TransferContact) -> String? {
        let family = ContactNormalizer.normalizeKana(contact.phoneticFamilyName ?? "")
        let given = ContactNormalizer.normalizeKana(contact.phoneticGivenName ?? "")
        if family.isEmpty && given.isEmpty { return nil }
        return family + "\u{1F}" + given
    }

    /// 組織キー。空なら nil。
    static func orgKey(_ contact: TransferContact) -> String? {
        let org = ContactNormalizer.normalizeName(contact.organizationName ?? "")
        return org.isEmpty ? nil : org
    }

    /// 誕生日キー(年・月・日)。未設定なら nil。
    static func birthdayKey(_ contact: TransferContact) -> String? {
        guard let birthday = contact.birthday,
              birthday.year != nil || birthday.month != nil || birthday.day != nil else {
            return nil
        }
        return "\(birthday.year ?? -1)-\(birthday.month ?? -1)-\(birthday.day ?? -1)"
    }

    /// L3 の補助キー判定: 組織一致 or ふりがな一致 or 誕生日一致
    /// (いずれも両側に値がある場合のみ)。
    static func auxiliaryMatch(_ a: TransferContact, _ b: TransferContact) -> Bool {
        if let org = orgKey(a), org == orgKey(b) { return true }
        if let kana = kanaKey(a), kana == kanaKey(b) { return true }
        if let birthday = birthdayKey(a), birthday == birthdayKey(b) { return true }
        return false
    }
}
