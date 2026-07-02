import XCTest
import Models
@testable import TransferKit

final class TransferMessageTests: XCTestCase {

    private func roundTrip(_ message: TransferMessage) throws -> TransferMessage {
        try TransferMessage.decode(try message.encode())
    }

    func testHelloRoundTrip() throws {
        let hello = TransferMessage.Hello(
            protocolVersion: TransferManifest.currentProtocolVersion,
            deviceName: "iPhone 15",
            verificationCode: "0427")
        guard case .hello(let decoded) = try roundTrip(.hello(hello)) else {
            return XCTFail("expected hello")
        }
        XCTAssertEqual(decoded.protocolVersion, hello.protocolVersion)
        XCTAssertEqual(decoded.deviceName, "iPhone 15")
        XCTAssertEqual(decoded.verificationCode, "0427")
    }

    func testControlMessagesRoundTrip() throws {
        if case .verifyApprove = try roundTrip(.verifyApprove) {} else { XCTFail("approve") }
        if case .verifyReject = try roundTrip(.verifyReject) {} else { XCTFail("reject") }
        if case .cancel = try roundTrip(.cancel) {} else { XCTFail("cancel") }
    }

    func testManifestRoundTrip() throws {
        let manifest = TransferManifest(deviceName: "iPhone", totalCount: 12,
                                        totalBytes: 3456, includesPhotos: false, chunkCount: 1)
        guard case .manifest(let decoded) = try roundTrip(.manifest(manifest)) else {
            return XCTFail("expected manifest")
        }
        XCTAssertEqual(decoded.totalCount, 12)
        XCTAssertEqual(decoded.chunkCount, 1)
    }

    func testChunkFrameCarriesRawData() throws {
        let contacts = [TransferContact(givenName: "A", familyName: "B")]
        let frame = try ChunkCodec.makeFrames(contacts: contacts)[0]
        guard case .chunkFrame(let decoded) = try roundTrip(.chunkFrame(frame)) else {
            return XCTFail("expected chunkFrame")
        }
        XCTAssertEqual(decoded, frame)
        XCTAssertEqual(try ChunkCodec.decodeFrame(decoded).contacts, contacts)
    }

    func testAckAndResultRoundTrip() throws {
        guard case .ack(let ack) = try roundTrip(.ack(ChunkAck(index: 7, ok: false))) else {
            return XCTFail("expected ack")
        }
        XCTAssertEqual(ack.index, 7)
        XCTAssertFalse(ack.ok)

        let result = TransferResult(received: 10, created: 8, merged: 1, skipped: 1, failed: [])
        guard case .result(let decoded) = try roundTrip(.result(result)) else {
            return XCTFail("expected result")
        }
        XCTAssertEqual(decoded.received, 10)
    }

    func testUnknownTypeByteThrows() {
        XCTAssertThrowsError(try TransferMessage.decode(Data([0xEE])))
        XCTAssertThrowsError(try TransferMessage.decode(Data()))
    }
}
