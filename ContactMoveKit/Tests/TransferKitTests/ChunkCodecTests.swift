import XCTest
import Models
@testable import TransferKit

final class ChunkCodecTests: XCTestCase {

    private func makeContacts(_ count: Int) -> [TransferContact] {
        (0..<count).map { index in
            TransferContact(
                givenName: "名\(index)",
                familyName: "姓\(index)",
                phones: [.init(label: .mobile, value: "090-0000-\(String(format: "%04d", index))")],
                emails: [.init(label: .home, value: "user\(index)@example.com")]
            )
        }
    }

    // MARK: - UT-TRN-01: 分割→結合の完全一致と SHA-256 検証

    func testSingleFrameRoundTrip() throws {
        let contacts = makeContacts(3)
        let frames = try ChunkCodec.makeFrames(contacts: contacts)
        XCTAssertEqual(frames.count, 1)
        let chunk = try ChunkCodec.decodeFrame(frames[0])
        XCTAssertEqual(chunk.index, 0)
        XCTAssertEqual(chunk.contacts, contacts)
    }

    func testMultiFrameSplitAndJoin() throws {
        let contacts = makeContacts(250)
        let frames = try ChunkCodec.makeFrames(contacts: contacts)
        XCTAssertEqual(frames.count, 3)  // 100 + 100 + 50

        var reassembled: [TransferContact] = []
        for (expectedIndex, frame) in frames.enumerated() {
            let chunk = try ChunkCodec.decodeFrame(frame)
            XCTAssertEqual(chunk.index, expectedIndex)
            reassembled.append(contentsOf: chunk.contacts)
        }
        XCTAssertEqual(reassembled, contacts)
        XCTAssertEqual(try ChunkCodec.decodeFrame(frames[2]).contacts.count, 50)
    }

    func testExactChunkBoundary() throws {
        let frames = try ChunkCodec.makeFrames(contacts: makeContacts(100))
        XCTAssertEqual(frames.count, 1)
        let frames2 = try ChunkCodec.makeFrames(contacts: makeContacts(101))
        XCTAssertEqual(frames2.count, 2)
        XCTAssertEqual(try ChunkCodec.decodeFrame(frames2[1]).contacts.count, 1)
    }

    func testEmptyContactsMakesNoFrames() throws {
        XCTAssertTrue(try ChunkCodec.makeFrames(contacts: []).isEmpty)
    }

    func testCustomChunkSize() throws {
        let frames = try ChunkCodec.makeFrames(contacts: makeContacts(10), maxPerChunk: 4)
        XCTAssertEqual(frames.count, 3)  // 4 + 4 + 2
    }

    /// ペイロード破損 → transferChecksumFailed(破損注入テスト)
    func testCorruptedPayloadThrowsChecksumError() throws {
        let frames = try ChunkCodec.makeFrames(contacts: makeContacts(5))
        var corrupted = frames[0]
        corrupted[corrupted.count - 1] ^= 0xFF  // 末尾1バイト反転
        XCTAssertThrowsError(try ChunkCodec.decodeFrame(corrupted)) { error in
            guard case AppError.transferChecksumFailed = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }
    }

    func testTruncatedFrameThrows() throws {
        let frames = try ChunkCodec.makeFrames(contacts: makeContacts(5))
        XCTAssertThrowsError(try ChunkCodec.decodeFrame(frames[0].prefix(10)))
        XCTAssertThrowsError(try ChunkCodec.decodeFrame(Data([0x00, 0x01])))
        XCTAssertThrowsError(try ChunkCodec.decodeFrame(Data()))
    }

    /// 画像データ(バイナリ)入りでも往復一致
    func testFrameWithImageData() throws {
        var contact = makeContacts(1)[0]
        contact.imageData = Data((0..<1024).map { UInt8($0 % 256) })
        let frames = try ChunkCodec.makeFrames(contacts: [contact])
        XCTAssertEqual(try ChunkCodec.decodeFrame(frames[0]).contacts, [contact])
    }

    // MARK: - SHA-256

    func testSHA256KnownVectors() {
        XCTAssertEqual(
            ChunkCodec.sha256Hex(Data()),
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        XCTAssertEqual(
            ChunkCodec.sha256Hex(Data("abc".utf8)),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(
            ChunkCodec.sha256Hex(Data("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq".utf8)),
            "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
    }

    /// 純Swift実装がプラットフォーム実装(CryptoKit)と同一結果を返す
    func testPureSwiftSHA256MatchesPlatform() {
        for size in [0, 1, 55, 56, 63, 64, 65, 1000] {
            let data = Data((0..<size).map { UInt8($0 % 251) })
            let pure = PureSHA256.digest([UInt8](data))
                .map { String(format: "%02x", $0) }.joined()
            XCTAssertEqual(pure, ChunkCodec.sha256Hex(data), "size=\(size)")
        }
    }

    // MARK: - 圧縮

    func testCompressionRoundTrip() throws {
        let original = Data(String(repeating: "連絡先データ0123456789", count: 500).utf8)
        let compressed = try ChunkCodec.compress(original)
        let restored = try ChunkCodec.decompress(compressed)
        XCTAssertEqual(restored, original)
        #if canImport(Compression)
        XCTAssertLessThan(compressed.count, original.count)
        #endif
    }

    // MARK: - 確認コード

    func testVerificationCodeIsAlwaysFourDigits() {
        for _ in 0..<200 {
            let code = ChunkCodec.makeVerificationCode()
            XCTAssertEqual(code.count, 4)
            XCTAssertTrue(code.allSatisfy(\.isNumber))
        }
    }
}
