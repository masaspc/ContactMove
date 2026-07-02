import Foundation
import Models

/// 転送ロール。
public enum TransferRole: Sendable {
    case sender, receiver
}

/// セッションから UI へ流すイベント(仕様書 §4.4 / §8)。
public enum TransferEvent: Sendable {
    /// 発見済みピア表示名(送信側)
    case peersChanged([String])
    case connecting(peer: String)
    /// 双方の画面に同じ4桁コードを表示し、両者の承認を待つ
    case verificationRequired(code: String, peer: String)
    case verified
    /// 受信側: これから受け取る内容の概要
    case manifestReceived(TransferManifest)
    /// 件数ベースの進捗(送受共通)
    case progress(done: Int, total: Int)
    /// 受信側: 全件受信完了
    case contactsReceived([TransferContact])
    /// 送信側: 受信側での取り込み結果
    case resultReceived(TransferResult)
    case finished
    case failed(AppError)
}

/// ピア間で交換するアプリケーション層メッセージ。
/// ワイヤ形式: `[1B: type][JSON または フレームデータ]`
enum TransferMessage {
    /// 接続直後に送信側から送る挨拶(バージョン照合+確認コード共有)
    case hello(Hello)
    /// 確認コードの承認/拒否
    case verifyApprove
    case verifyReject
    /// データ送信開始宣言
    case manifest(TransferManifest)
    /// 連絡先チャンク(ChunkCodec のフレーム)
    case chunkFrame(Data)
    /// チャンク受信確認
    case ack(ChunkAck)
    /// 受信側の最終結果
    case result(TransferResult)
    /// 中断通知
    case cancel

    struct Hello: Codable {
        let protocolVersion: Int
        let deviceName: String
        let verificationCode: String
    }

    private enum TypeByte: UInt8 {
        case hello = 0x01
        case verifyApprove = 0x02
        case verifyReject = 0x03
        case manifest = 0x04
        case chunkFrame = 0x10
        case ack = 0x11
        case result = 0x20
        case cancel = 0x30
    }

    func encode() throws -> Data {
        var data = Data()
        switch self {
        case .hello(let hello):
            data.append(TypeByte.hello.rawValue)
            data.append(try JSONEncoder().encode(hello))
        case .verifyApprove:
            data.append(TypeByte.verifyApprove.rawValue)
        case .verifyReject:
            data.append(TypeByte.verifyReject.rawValue)
        case .manifest(let manifest):
            data.append(TypeByte.manifest.rawValue)
            data.append(try JSONEncoder().encode(manifest))
        case .chunkFrame(let frame):
            data.append(TypeByte.chunkFrame.rawValue)
            data.append(frame)
        case .ack(let ack):
            data.append(TypeByte.ack.rawValue)
            data.append(try JSONEncoder().encode(ack))
        case .result(let result):
            data.append(TypeByte.result.rawValue)
            data.append(try JSONEncoder().encode(result))
        case .cancel:
            data.append(TypeByte.cancel.rawValue)
        }
        return data
    }

    static func decode(_ data: Data) throws -> TransferMessage {
        let bytes = Data(data)
        guard let first = bytes.first, let type = TypeByte(rawValue: first) else {
            throw AppError.transferConnectionLost
        }
        let body = bytes.dropFirst()
        switch type {
        case .hello:
            return .hello(try JSONDecoder().decode(Hello.self, from: body))
        case .verifyApprove:
            return .verifyApprove
        case .verifyReject:
            return .verifyReject
        case .manifest:
            return .manifest(try JSONDecoder().decode(TransferManifest.self, from: body))
        case .chunkFrame:
            return .chunkFrame(Data(body))
        case .ack:
            return .ack(try JSONDecoder().decode(ChunkAck.self, from: body))
        case .result:
            return .result(try JSONDecoder().decode(TransferResult.self, from: body))
        case .cancel:
            return .cancel
        }
    }
}
