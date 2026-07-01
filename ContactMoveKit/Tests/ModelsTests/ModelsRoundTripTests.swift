import XCTest
@testable import Models

final class ModelsRoundTripTests: XCTestCase {
    private func roundTrip<T: Codable & Equatable>(_ value: T) throws -> T {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(T.self, from: data)
    }

    func testTransferContactRoundTrip() throws {
        var contact = TransferContact(
            givenName: "太郎",
            familyName: "山田",
            middleName: nil,
            phoneticGivenName: "タロウ",
            phoneticFamilyName: "ヤマダ",
            organizationName: "株式会社サンプル",
            departmentName: "開発部",
            jobTitle: "エンジニア",
            phones: [
                .init(label: .mobile, value: "090-1234-5678"),
                .init(label: .work, value: "03-1234-5678"),
            ],
            emails: [.init(label: .home, value: "taro@example.com")],
            postalAddresses: [
                .init(label: .home, postalCode: "100-0001", state: "東京都",
                      city: "千代田区", street: "千代田1-1", subLocality: "サンプルビル",
                      country: "日本"),
            ],
            urls: [.init(label: .other, value: "https://example.com")],
            birthday: DateComponents(year: 1990, month: 1, day: 2),
            imageData: Data([0xFF, 0xD8, 0xFF, 0xE0]),
            groups: ["友人", "仕事"]
        )
        contact.sourceIdentifier = "ABC-123"

        let decoded = try roundTrip(contact)
        XCTAssertEqual(decoded, contact)
        XCTAssertEqual(decoded.displayName, "山田 太郎")
    }

    func testTransferManifestRoundTrip() throws {
        let manifest = TransferManifest(
            deviceName: "iPhone 15",
            totalCount: 1200,
            totalBytes: 345_678,
            includesPhotos: true,
            chunkCount: 12
        )
        let data = try JSONEncoder().encode(manifest)
        let decoded = try JSONDecoder().decode(TransferManifest.self, from: data)
        XCTAssertEqual(decoded.protocolVersion, TransferManifest.currentProtocolVersion)
        XCTAssertEqual(decoded.deviceName, manifest.deviceName)
        XCTAssertEqual(decoded.totalCount, manifest.totalCount)
        XCTAssertEqual(decoded.chunkCount, manifest.chunkCount)
    }

    func testContactChunkAndAckRoundTrip() throws {
        let chunk = ContactChunk(
            index: 3,
            contacts: [TransferContact(givenName: "A", familyName: "B")],
            sha256: "deadbeef"
        )
        let data = try JSONEncoder().encode(chunk)
        let decoded = try JSONDecoder().decode(ContactChunk.self, from: data)
        XCTAssertEqual(decoded.index, 3)
        XCTAssertEqual(decoded.contacts.count, 1)
        XCTAssertEqual(decoded.sha256, "deadbeef")

        let ack = try JSONDecoder().decode(
            ChunkAck.self,
            from: JSONEncoder().encode(ChunkAck(index: 3, ok: false))
        )
        XCTAssertEqual(ack.index, 3)
        XCTAssertFalse(ack.ok)
    }

    func testTransferResultRoundTrip() throws {
        let result = TransferResult(
            received: 100, created: 80, merged: 15, skipped: 4,
            failed: [.init(displayName: "山田 太郎", reason: "保存エラー")]
        )
        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(TransferResult.self, from: data)
        XCTAssertEqual(decoded.received, 100)
        XCTAssertEqual(decoded.failed.first?.displayName, "山田 太郎")
    }

    func testDisplayNameFallbacks() {
        XCTAssertEqual(
            TransferContact(organizationName: "会社X").displayName, "会社X")
        XCTAssertEqual(
            TransferContact(phones: [.init(label: .mobile, value: "09011112222")]).displayName,
            "09011112222")
        XCTAssertEqual(TransferContact().displayName, "(名前なし)")
        XCTAssertTrue(TransferContact().isEffectivelyEmpty)
    }

    func testMergeStrategyCodable() throws {
        for strategy in MergeStrategy.allCases {
            let decoded = try JSONDecoder().decode(
                MergeStrategy.self, from: JSONEncoder().encode(strategy))
            XCTAssertEqual(decoded, strategy)
        }
    }
}
