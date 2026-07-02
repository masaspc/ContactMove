import XCTest
import Models
@testable import DedupeKit

final class DedupeEngineTests: XCTestCase {
    private let engine = DedupeEngine()

    // MARK: - UT-DED-03: L1〜L4 の判定境界

    func testL1PhoneMatchEvenIfNameDiffers() {
        let existing = [makeContact(source: "E1", family: "山田", given: "太郎",
                                    phones: ["090-1234-5678"])]
        let incoming = [makeContact(family: "佐藤", given: "花子",
                                    phones: ["+819012345678"])]
        let result = engine.analyze(existing: existing, incoming: incoming)
        XCTAssertEqual(result.duplicates.count, 1)
        XCTAssertEqual(result.duplicates.first?.level, .l1Phone)
        XCTAssertTrue(result.newContacts.isEmpty)
    }

    func testL2EmailMatch() {
        let existing = [makeContact(source: "E1", family: "山田", given: "太郎",
                                    emails: ["Taro@Example.com"])]
        let incoming = [makeContact(family: "山田", given: "太郎",
                                    emails: ["taro@example.com"])]
        let result = engine.analyze(existing: existing, incoming: incoming)
        XCTAssertEqual(result.duplicates.first?.level, .l2Email)
    }

    func testL3NamePlusOrganization() {
        let existing = [makeContact(source: "E1", family: "山田", given: "太郎", org: "株式会社A")]
        let incoming = [makeContact(family: "山田", given: "太郎", org: "株式会社A")]
        let result = engine.analyze(existing: existing, incoming: incoming)
        XCTAssertEqual(result.duplicates.first?.level, .l3NamePlus)
    }

    func testL3NamePlusKana() {
        let existing = [makeContact(source: "E1", family: "山田", given: "太郎",
                                    kanaFamily: "やまだ", kanaGiven: "たろう")]
        let incoming = [makeContact(family: "山田", given: "太郎",
                                    kanaFamily: "ヤマダ", kanaGiven: "タロウ")]
        let result = engine.analyze(existing: existing, incoming: incoming)
        XCTAssertEqual(result.duplicates.first?.level, .l3NamePlus)
    }

    func testL3NamePlusBirthday() {
        let birthday = DateComponents(year: 1990, month: 1, day: 2)
        let existing = [makeContact(source: "E1", family: "山田", given: "太郎", birthday: birthday)]
        let incoming = [makeContact(family: "山田", given: "太郎", birthday: birthday)]
        let result = engine.analyze(existing: existing, incoming: incoming)
        XCTAssertEqual(result.duplicates.first?.level, .l3NamePlus)
    }

    /// 同姓同名の別人(補助キー全滅)は L4 止まり → candidates へ
    func testSameNameDifferentPersonStaysL4() {
        let existing = [makeContact(source: "E1", family: "山田", given: "太郎",
                                    org: "株式会社A", phones: ["090-1111-1111"])]
        let incoming = [makeContact(family: "山田", given: "太郎",
                                    org: "株式会社B", phones: ["090-2222-2222"])]
        let result = engine.analyze(existing: existing, incoming: incoming)
        XCTAssertTrue(result.duplicates.isEmpty)
        XCTAssertEqual(result.candidates.count, 1)
        XCTAssertEqual(result.candidates.first?.level, .l4NameOnly)
    }

    func testNoMatchGoesToNewContacts() {
        let existing = [makeContact(source: "E1", family: "山田", given: "太郎")]
        let incoming = [makeContact(family: "佐藤", given: "花子", phones: ["090-9999-0000"])]
        let result = engine.analyze(existing: existing, incoming: incoming)
        XCTAssertEqual(result.newContacts.count, 1)
        XCTAssertTrue(result.duplicates.isEmpty)
        XCTAssertTrue(result.candidates.isEmpty)
    }

    /// 姓名両方空は L3/L4 判定の対象外(電話だけの連絡先が誤って名前一致しない)
    func testEmptyNamesAreNotNameMatched() {
        let existing = [makeContact(source: "E1", phones: ["090-1111-1111"])]
        let incoming = [makeContact(phones: ["090-2222-2222"])]
        let result = engine.analyze(existing: existing, incoming: incoming)
        XCTAssertEqual(result.newContacts.count, 1)
    }

    /// レベル優先: 電話もメールも一致する場合は L1
    func testHigherLevelWins() {
        let existing = [makeContact(source: "E1", family: "山田", given: "太郎",
                                    phones: ["09011112222"], emails: ["a@example.com"])]
        let incoming = [makeContact(family: "山田", given: "太郎",
                                    phones: ["090-1111-2222"], emails: ["A@EXAMPLE.COM"])]
        let result = engine.analyze(existing: existing, incoming: incoming)
        XCTAssertEqual(result.duplicates.first?.level, .l1Phone)
    }

    // MARK: - IT-07 相当: 冪等性

    func testIdempotentReimport() {
        let contacts = (0..<50).map { index in
            makeContact(source: "E\(index)", family: "姓\(index)", given: "名\(index)",
                        phones: ["090-0000-\(String(format: "%04d", index))"])
        }
        // 2回目のインポート(全件が既存と同一)→ 全件 L1 重複
        var reimported = contacts
        for index in reimported.indices { reimported[index].sourceIdentifier = nil }
        let result = engine.analyze(existing: contacts, incoming: reimported)
        XCTAssertEqual(result.duplicates.count, 50)
        XCTAssertTrue(result.newContacts.isEmpty)

        let plan = MergePlanner.plan(analysis: result, strategy: .skip, acceptedCandidates: [])
        XCTAssertEqual(plan.skippedCount, 50)
        XCTAssertTrue(plan.creates.isEmpty)
        XCTAssertTrue(plan.updates.isEmpty)
    }

    // MARK: - duplicateGroups(端末内整理)

    /// 電話とメールで連鎖的に3件が1グループ(推移閉包)
    func testTransitiveGrouping() {
        let a = makeContact(source: "A", family: "山田", given: "太郎",
                            phones: ["090-1111-1111"], emails: ["a@example.com"])
        let b = makeContact(source: "B", family: "山田", given: "太郎",
                            phones: ["090-1111-1111"], emails: ["b@example.com"])
        let c = makeContact(source: "C", family: "ヤマダ", given: "タロウ",
                            emails: ["B@example.com"])
        let groups = engine.duplicateGroups(in: [a, b, c])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.members.count, 3)
        XCTAssertEqual(groups.first?.confidence, .high)
    }

    func testL3GroupIsMediumConfidence() {
        let a = makeContact(source: "A", family: "山田", given: "太郎", org: "株式会社A")
        let b = makeContact(source: "B", family: "山田", given: "太郎", org: "株式会社A")
        let groups = engine.duplicateGroups(in: [a, b])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.confidence, .medium)
    }

    func testNoGroupsForDistinctContacts() {
        let a = makeContact(source: "A", family: "山田", given: "太郎", phones: ["090-1111-1111"])
        let b = makeContact(source: "B", family: "佐藤", given: "花子", phones: ["090-2222-2222"])
        XCTAssertTrue(engine.duplicateGroups(in: [a, b]).isEmpty)
    }

    /// 同姓同名のみ(L4相当)は端末内整理ではグループ化しない
    func testL4IsNotGroupedInDeviceScan() {
        let a = makeContact(source: "A", family: "山田", given: "太郎", org: "会社A")
        let b = makeContact(source: "B", family: "山田", given: "太郎", org: "会社B")
        XCTAssertTrue(engine.duplicateGroups(in: [a, b]).isEmpty)
    }
}
