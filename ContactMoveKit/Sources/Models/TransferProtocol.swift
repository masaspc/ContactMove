import Foundation

// MARK: - 転送プロトコルモデル(仕様書 §9.2 / §4.4)

/// ハンドシェイク時に送信するマニフェスト
public struct TransferManifest: Codable, Sendable {
    /// プロトコルバージョン(現行: 1)
    public let protocolVersion: Int
    public let deviceName: String
    public let totalCount: Int
    public let totalBytes: Int
    public let includesPhotos: Bool
    public let chunkCount: Int

    public static let currentProtocolVersion = 1

    public init(
        protocolVersion: Int = TransferManifest.currentProtocolVersion,
        deviceName: String,
        totalCount: Int,
        totalBytes: Int,
        includesPhotos: Bool,
        chunkCount: Int
    ) {
        self.protocolVersion = protocolVersion
        self.deviceName = deviceName
        self.totalCount = totalCount
        self.totalBytes = totalBytes
        self.includesPhotos = includesPhotos
        self.chunkCount = chunkCount
    }
}

/// 連絡先のチャンク(最大100件/チャンク)
public struct ContactChunk: Codable, Sendable {
    public let index: Int
    public let contacts: [TransferContact]
    /// 圧縮後ペイロードの SHA-256(hex)
    public let sha256: String

    public static let maxContactsPerChunk = 100

    public init(index: Int, contacts: [TransferContact], sha256: String) {
        self.index = index
        self.contacts = contacts
        self.sha256 = sha256
    }
}

/// チャンクごとの受信確認
public struct ChunkAck: Codable, Sendable {
    public let index: Int
    public let ok: Bool

    public init(index: Int, ok: Bool) {
        self.index = index
        self.ok = ok
    }
}

/// 転送完了時に受信側から送信側へ返す結果
public struct TransferResult: Codable, Sendable {
    public let received: Int
    public let created: Int
    public let merged: Int
    public let skipped: Int
    public let failed: [FailedItem]

    public struct FailedItem: Codable, Sendable {
        public let displayName: String
        public let reason: String

        public init(displayName: String, reason: String) {
            self.displayName = displayName
            self.reason = reason
        }
    }

    public init(received: Int, created: Int, merged: Int, skipped: Int, failed: [FailedItem]) {
        self.received = received
        self.created = created
        self.merged = merged
        self.skipped = skipped
        self.failed = failed
    }
}
