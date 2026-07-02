import XCTest
import Models
@testable import DedupeKit

final class ContactNormalizerTests: XCTestCase {

    // UT-DED-01: 電話番号正規化
    func testPhoneE164Equivalence() {
        let a = ContactNormalizer.phoneComparisonKeys("090-1234-5678")
        let b = ContactNormalizer.phoneComparisonKeys("+819012345678")
        XCTAssertFalse(a.isDisjoint(with: b))
    }

    func testPhoneNormalizationForms() {
        XCTAssertEqual(ContactNormalizer.normalizePhone("090-1234-5678"), "+819012345678")
        XCTAssertEqual(ContactNormalizer.normalizePhone("(03) 1234-5678"), "+81312345678")
        XCTAssertEqual(ContactNormalizer.normalizePhone("+81 90 1234 5678"), "+819012345678")
        // 全角数字も NFKC で半角化される
        XCTAssertEqual(ContactNormalizer.normalizePhone("090-1234-5678"), "+819012345678")
        // 桁不足(短縮番号等)はそのまま数字列
        XCTAssertEqual(ContactNormalizer.normalizePhone("110"), "110")
        XCTAssertEqual(ContactNormalizer.normalizePhone(""), "")
        XCTAssertEqual(ContactNormalizer.normalizePhone("abc"), "")
    }

    func testPhoneComparisonKeysLast10Digits() {
        let keys = ContactNormalizer.phoneComparisonKeys("09012345678")
        XCTAssertTrue(keys.contains("9012345678"))   // 下10桁
        XCTAssertTrue(keys.contains("+819012345678"))
    }

    // UT-DED-02: メール・氏名の正規化
    func testEmailNormalization() {
        XCTAssertEqual(ContactNormalizer.normalizeEmail("  Taro@Example.COM "), "taro@example.com")
    }

    func testNameNFKCNormalization() {
        // 全角英数 → 半角
        XCTAssertEqual(ContactNormalizer.normalizeName("Yamada Taro"), "Yamada Taro")
        // 連続空白の統合と trim
        XCTAssertEqual(ContactNormalizer.normalizeName("  山田   太郎 "), "山田 太郎")
        // 半角カナ → 全角カナ(NFKC)
        XCTAssertEqual(ContactNormalizer.normalizeName("ヤマダ"), "ヤマダ")
    }

    func testKanaUnification() {
        XCTAssertEqual(ContactNormalizer.normalizeKana("やまだ たろう"),
                       ContactNormalizer.normalizeKana("ヤマダ タロウ"))
        XCTAssertEqual(ContactNormalizer.normalizeKana("ゔ"), "ヴ")
    }
}
