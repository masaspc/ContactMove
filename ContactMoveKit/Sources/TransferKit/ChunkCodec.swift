import Foundation
import Models
#if canImport(Compression)
import Compression
#endif

/// チャンク転送の純ロジック(仕様書 §4.4)。Linux でもビルド/テスト可能。
///
/// フレーム形式:
/// ```
/// [1B: 圧縮方式 (0=無圧縮, 1=zlib)]
/// [4B: ヘッダ長 (UInt32 bigEndian)]
/// [ヘッダ JSON: {"index": Int, "count": Int, "sha256": String}]
/// [ペイロード: (圧縮された) JSON([TransferContact])]
/// ```
/// sha256 は**圧縮後ペイロード**の SHA-256(hex)。
public enum ChunkCodec {

    struct FrameHeader: Codable {
        let index: Int
        let count: Int
        let sha256: String
    }

    enum CompressionMethod: UInt8 {
        case raw = 0
        case zlib = 1
    }

    // MARK: - フレーム生成/復元

    /// contacts → 100件ごとのフレーム列(JSON + zlib圧縮 + SHA-256ヘッダ)。
    public static func makeFrames(contacts: [TransferContact],
                                  maxPerChunk: Int = ContactChunk.maxContactsPerChunk) throws -> [Data] {
        guard maxPerChunk > 0 else { return [] }
        var frames: [Data] = []
        var index = 0
        var start = 0
        while start < contacts.count {
            let end = min(start + maxPerChunk, contacts.count)
            let slice = Array(contacts[start..<end])
            frames.append(try encodeFrame(index: index, contacts: slice))
            index += 1
            start = end
        }
        return frames
    }

    static func encodeFrame(index: Int, contacts: [TransferContact]) throws -> Data {
        let json = try JSONEncoder().encode(contacts)

        var method = CompressionMethod.raw
        var payload = json
        #if canImport(Compression)
        if let compressed = zlibCompress(json), compressed.count < json.count {
            method = .zlib
            payload = compressed
        }
        #endif

        let header = FrameHeader(index: index, count: contacts.count,
                                 sha256: sha256Hex(payload))
        let headerData = try JSONEncoder().encode(header)

        var frame = Data()
        frame.append(method.rawValue)
        var lengthBE = UInt32(headerData.count).bigEndian
        withUnsafeBytes(of: &lengthBE) { frame.append(contentsOf: $0) }
        frame.append(headerData)
        frame.append(payload)
        return frame
    }

    /// フレーム検証+復元。チェックサム不一致は `AppError.transferChecksumFailed`。
    public static func decodeFrame(_ data: Data) throws -> ContactChunk {
        let bytes = Data(data)  // スライス由来の index ずれを防ぐためコピー
        guard bytes.count >= 5,
              let method = CompressionMethod(rawValue: bytes[0]) else {
            throw AppError.transferChecksumFailed(chunkIndex: -1)
        }
        let headerLength = Int(UInt32(bigEndian: bytes.subdata(in: 1..<5).withUnsafeBytes {
            $0.load(as: UInt32.self)
        }))
        guard bytes.count >= 5 + headerLength else {
            throw AppError.transferChecksumFailed(chunkIndex: -1)
        }
        let headerData = bytes.subdata(in: 5..<(5 + headerLength))
        guard let header = try? JSONDecoder().decode(FrameHeader.self, from: headerData) else {
            throw AppError.transferChecksumFailed(chunkIndex: -1)
        }
        let payload = bytes.subdata(in: (5 + headerLength)..<bytes.count)

        guard sha256Hex(payload) == header.sha256 else {
            throw AppError.transferChecksumFailed(chunkIndex: header.index)
        }

        let json: Data
        switch method {
        case .raw:
            json = payload
        case .zlib:
            json = try decompress(payload)
        }
        guard let contacts = try? JSONDecoder().decode([TransferContact].self, from: json),
              contacts.count == header.count else {
            throw AppError.transferChecksumFailed(chunkIndex: header.index)
        }
        return ContactChunk(index: header.index, contacts: contacts, sha256: header.sha256)
    }

    // MARK: - ハッシュ・圧縮

    public static func sha256Hex(_ data: Data) -> String {
        SHA256Hasher.hexDigest(data)
    }

    /// zlib(raw deflate)圧縮。Compression framework が使えない環境では
    /// 無圧縮のまま返す(フレームの方式バイトで区別されるため相互運用可能)。
    public static func compress(_ data: Data) throws -> Data {
        #if canImport(Compression)
        return zlibCompress(data) ?? data
        #else
        return data
        #endif
    }

    /// zlib(raw deflate)解凍。
    public static func decompress(_ data: Data) throws -> Data {
        #if canImport(Compression)
        guard let result = zlibDecompress(data) else {
            throw AppError.transferChecksumFailed(chunkIndex: -1)
        }
        return result
        #else
        return data
        #endif
    }

    /// 4桁確認コード生成(0000〜9999)。
    public static func makeVerificationCode() -> String {
        let value = Int.random(in: 0...9999)
        let text = String(value)
        return String(repeating: "0", count: 4 - text.count) + text
    }

    #if canImport(Compression)
    private static func zlibCompress(_ data: Data) -> Data? {
        guard !data.isEmpty else { return nil }
        let source = [UInt8](data)
        let capacity = source.count + 65_536
        var destination = [UInt8](repeating: 0, count: capacity)
        let written = compression_encode_buffer(
            &destination, capacity,
            source, source.count,
            nil, COMPRESSION_ZLIB)
        guard written > 0 else { return nil }
        return Data(destination.prefix(written))
    }

    private static func zlibDecompress(_ data: Data) -> Data? {
        guard !data.isEmpty else { return nil }
        let source = [UInt8](data)
        var capacity = max(source.count * 4, 65_536)
        // 出力バッファが足りない場合は拡大して再試行(上限 512MB)
        while capacity <= 512 * 1_024 * 1_024 {
            var destination = [UInt8](repeating: 0, count: capacity)
            let written = compression_decode_buffer(
                &destination, capacity,
                source, source.count,
                nil, COMPRESSION_ZLIB)
            guard written > 0 else { return nil }
            if written < capacity {
                return Data(destination.prefix(written))
            }
            capacity *= 4
        }
        return nil
    }
    #endif
}
