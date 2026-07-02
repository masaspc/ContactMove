import XCTest
import Models
@testable import DedupeKit

final class MergePlannerTests: XCTestCase {
    private let engine = DedupeEngine()

    // MARK: - UT-DED-04: フィールドマージ

    /// 同ラベル同値(正規化比較)の重複追加が起きない
    func testMergeDoesNotDuplicateSameLabelSameValue() {
        let existing = makeContact(source: "E1", family: "山田", given: "太郎",
                                   phones: ["090-1234-5678"], emails: ["taro@example.com"])
        let incoming = makeContact(family: "山田", given: "太郎",
                                   phones: ["+81 90-1234-5678"], emails: ["TARO@example.com"])
        let merged = MergePlanner.merge(existing: existing, incoming: incoming, strategy: .merge)
        XCTAssertEqual(merged.phones.count, 1)
        XCTAssertEqual(merged.emails.count, 1)
    }

    /// 新規側にしかない値は追加される
    func testMergeAddsNewValues() {
        let existing = makeContact(source: "E1", family: "山田", given: "太郎",
                                   phones: ["090-1234-5678"])
        let incoming = makeContact(family: "山田", given: "太郎",
                                   phones: ["03-1111-2222"], emails: ["taro@example.com"])
        let merged = MergePlanner.merge(existing: existing, incoming: incoming, strategy: .merge)
        XCTAssertEqual(merged.phones.count, 2)
        XCTAssertEqual(merged.emails.count, 1)
    }

    /// 単一値フィールドは既存優先、空フィールドのみ補完される
    func testMergeFillsOnlyEmptySingleValueFields() {
        var existing = makeContact(source: "E1", family: "山田", given: "太郎")
        existing.jobTitle = "部長"
        var incoming = makeContact(family: "山田", given: "太郎", org: "株式会社A")
        incoming.jobTitle = "課長"
        let merged = MergePlanner.merge(existing: existing, incoming: incoming, strategy: .merge)
        XCTAssertEqual(merged.jobTitle, "部長")           // 既存優先
        XCTAssertEqual(merged.organizationName, "株式会社A") // 空だったので補完
        XCTAssertEqual(merged.sourceIdentifier, "E1")     // ID は既存側を維持
        XCTAssertEqual(merged.id, existing.id)
    }

    /// overwrite: 新規側が空のフィールドは既存維持
    func testOverwriteKeepsExistingWhenIncomingEmpty() {
        var existing = makeContact(source: "E1", family: "山田", given: "太郎",
                                   org: "株式会社A", phones: ["090-1111-1111"])
        existing.jobTitle = "部長"
        var incoming = makeContact(family: "山田", given: "次郎")
        incoming.organizationName = nil
        let merged = MergePlanner.merge(existing: existing, incoming: incoming, strategy: .overwrite)
        XCTAssertEqual(merged.givenName, "次郎")            // 非空 → 置換
        XCTAssertEqual(merged.organizationName, "株式会社A") // 空 → 既存維持
        XCTAssertEqual(merged.jobTitle, "部長")
        XCTAssertEqual(merged.phones.first?.value, "090-1111-1111") // 空配列 → 既存維持
    }

    func testSkipAndKeepBothMergeBehavior() {
        let existing = makeContact(source: "E1", family: "山田", given: "太郎")
        let incoming = makeContact(family: "山田", given: "次郎")
        XCTAssertEqual(MergePlanner.merge(existing: existing, incoming: incoming, strategy: .skip),
                       existing)
        XCTAssertEqual(MergePlanner.merge(existing: existing, incoming: incoming, strategy: .keepBoth),
                       incoming)
    }

    // MARK: - plan(analysis:)

    private func sampleAnalysis() -> DedupeAnalysis {
        let existing = [
            makeContact(source: "E1", family: "山田", given: "太郎", phones: ["090-1111-1111"]),
            makeContact(source: "E2", family: "佐藤", given: "花子", org: "会社B"),
        ]
        let incoming = [
            makeContact(family: "山田", given: "太郎", phones: ["090-1111-1111"]),  // L1
            makeContact(family: "佐藤", given: "花子", org: "会社X"),               // L4 候補
            makeContact(family: "鈴木", given: "一郎"),                             // 新規
        ]
        return engine.analyze(existing: existing, incoming: incoming)
    }

    func testPlanSkipStrategy() {
        let analysis = sampleAnalysis()
        let plan = MergePlanner.plan(analysis: analysis, strategy: .skip, acceptedCandidates: [])
        XCTAssertEqual(plan.skippedCount, 1)          // L1 をスキップ
        XCTAssertEqual(plan.updates.count, 0)
        XCTAssertEqual(plan.creates.count, 2)         // 新規 + 却下されたL4候補
    }

    func testPlanMergeStrategyWithAcceptedCandidate() {
        let analysis = sampleAnalysis()
        let candidateID = analysis.candidates.first!.id
        let plan = MergePlanner.plan(analysis: analysis, strategy: .merge,
                                     acceptedCandidates: [candidateID])
        XCTAssertEqual(plan.updates.count, 2)         // L1マージ + 受理されたL4
        XCTAssertEqual(plan.creates.count, 1)         // 新規のみ
        XCTAssertEqual(plan.skippedCount, 0)
        XCTAssertTrue(plan.updates.allSatisfy { $0.existing.sourceIdentifier != nil })
    }

    func testPlanKeepBothStrategy() {
        let analysis = sampleAnalysis()
        let plan = MergePlanner.plan(analysis: analysis, strategy: .keepBoth, acceptedCandidates: [])
        XCTAssertEqual(plan.creates.count, 3)         // 重複も新規作成
        XCTAssertEqual(plan.updates.count, 0)
    }

    func testPlanSummaryText() {
        let analysis = sampleAnalysis()
        let plan = MergePlanner.plan(analysis: analysis, strategy: .merge, acceptedCandidates: [])
        XCTAssertTrue(plan.summary.contains("2件を新規作成"))
        XCTAssertTrue(plan.summary.contains("1件をマージ"))
        XCTAssertFalse(plan.summary.contains("スキップ"))
    }

    // MARK: - plan(groups:) 端末内整理

    func testGroupPlanMergesIntoRichestMember() {
        let rich = makeContact(source: "A", family: "山田", given: "太郎",
                               org: "株式会社A", phones: ["090-1111-1111"],
                               emails: ["a@example.com"], groups: ["友人"])
        let poor = makeContact(source: "B", family: "山田", given: "太郎",
                               phones: ["090-1111-1111"], emails: ["b@example.com"])
        let groups = engine.duplicateGroups(in: [poor, rich])
        XCTAssertEqual(groups.count, 1)

        let plan = MergePlanner.plan(groups: groups, acceptedGroupIDs: [groups[0].id])
        XCTAssertEqual(plan.updates.count, 1)
        XCTAssertEqual(plan.deletes.count, 1)
        // 情報量最大の rich がベースになり、poor 側のメールが追加される
        XCTAssertEqual(plan.updates.first?.existing.sourceIdentifier, "A")
        XCTAssertEqual(plan.deletes.first?.sourceIdentifier, "B")
        XCTAssertEqual(plan.updates.first?.merged.emails.count, 2)
        XCTAssertEqual(plan.updates.first?.merged.phones.count, 1)  // 同番号は増えない
    }

    func testGroupPlanSkipsUnacceptedGroups() {
        let a = makeContact(source: "A", family: "山田", given: "太郎", phones: ["090-1111-1111"])
        let b = makeContact(source: "B", family: "山田", given: "太郎", phones: ["090-1111-1111"])
        let groups = engine.duplicateGroups(in: [a, b])
        let plan = MergePlanner.plan(groups: groups, acceptedGroupIDs: [])
        XCTAssertTrue(plan.updates.isEmpty)
        XCTAssertTrue(plan.deletes.isEmpty)
        XCTAssertEqual(plan.skippedCount, 1)
    }
}
