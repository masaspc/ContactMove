import Foundation

/// アプリ全体のエラー型(仕様書 §10.2)。全画面共通のエラーシートで表示する。
public enum AppError: LocalizedError, Sendable {
    case contactsAccessDenied
    case contactsAccessRestricted
    case fileTooLarge(limitMB: Int)
    case unreadableEncoding
    case emptyImport(hint: String)
    case csvParseFailed(reason: String)
    case vCardParseFailed
    case transferProtocolMismatch(remoteVersion: Int)
    case transferConnectionLost
    case transferVerificationRejected
    case transferChecksumFailed(chunkIndex: Int)
    case cancelled(completedCount: Int)
    case saveFailed(underlying: String)

    public var errorDescription: String? {
        switch self {
        case .contactsAccessDenied:
            return "連絡先へのアクセスが許可されていません。設定アプリから許可してください。"
        case .contactsAccessRestricted:
            return "この端末では連絡先へのアクセスが制限されています。"
        case .fileTooLarge(let limitMB):
            return "ファイルが大きすぎます(上限 \(limitMB)MB)。"
        case .unreadableEncoding:
            return "文字コードを判定できませんでした(UTF-8 / Shift_JIS / EUC-JP に対応)。"
        case .emptyImport(let hint):
            return "取り込める行がありません。\(hint)"
        case .csvParseFailed(let reason):
            return "CSVの解析に失敗しました: \(reason)"
        case .vCardParseFailed:
            return "vCardの解析に失敗しました。"
        case .transferProtocolMismatch(let remoteVersion):
            return "相手のアプリのバージョンが異なります(プロトコル v\(remoteVersion))。両方の端末でアプリを最新にしてください。"
        case .transferConnectionLost:
            return "接続が切断されました。両端末を近づけて再度お試しください。"
        case .transferVerificationRejected:
            return "確認コードが承認されなかったため、接続を中止しました。"
        case .transferChecksumFailed(let chunkIndex):
            return "データ検証に失敗しました(チャンク \(chunkIndex))。再送も失敗したため転送を中止しました。"
        case .cancelled(let completedCount):
            return "処理をキャンセルしました。\(completedCount)件まで取り込み済みです。"
        case .saveFailed(let underlying):
            return "連絡先の保存に失敗しました: \(underlying)"
        }
    }
}
