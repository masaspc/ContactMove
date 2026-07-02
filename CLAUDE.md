# ContactMove — iOS 電話帳移行アプリ

詳細仕様は `docs/仕様書.md` を必ず参照すること(§5 CSV仕様 / §6 重複統合 / §9 データモデル)。

## 構成

```
ContactMove.xcodeproj      … Xcode 16 (objectVersion 70, FileSystemSynchronizedRootGroup)
App/                       … アプリ本体 (SwiftUI, iOS 16+)。フォルダ同期でターゲットに自動追加
Support/Info.plist         … 権限キー (INFOPLIST_FILE で参照。プロジェクトナビゲータには出ない)
ContactMoveKit/            … ローカル Swift Package
  Sources/Models           … 中間モデル (TransferContact 等) — 実装済み
  Sources/CSVKit           … RFC4180 パーサ/ライタ、文字コード判定、スキーマ/マッピング
  Sources/DedupeKit        … 正規化、L1〜L4 マッチング、マージ計画
  Sources/ContactsKit      … CNContactStore ラッパ (権限/読取/書込/vCard)
  Sources/TransferKit      … MultipeerConnectivity セッション、チャンク転送
  Tests/…                  … 各 Kit の XCTest
```

## コーディング規約

- Swift 5.10 / swift-tools-version 5.10(言語モードは Swift 5)。外部依存ゼロ。
- iOS 16.0 サポート。iOS 17+ 専用 API(`@Observable` 等)は使わず `ObservableObject` を使う。
  iOS 18 API(limited アクセス等)は `#available` でガード。
- Apple 専用フレームワーク(Contacts / MultipeerConnectivity / CryptoKit / Compression /
  UIKit)は必ず `#if canImport(...)` でガードし、**Linux でも `swift build` が通る**構造を保つ
  (純ロジックは非ガード領域に置く)。
- 公開 API には `public` を明示。値型は可能な限り `Sendable`。
- ユーザー向け文字列は日本語を第一言語とする(App 側では String Catalog で ja/en 対応)。
- note フィールドは Entitlement 承認が必要なため **一切扱わない**。

## モジュール間 API 契約(必ずこのシグネチャで実装する)

Models は実装済み: `TransferContact` / `TransferManifest` / `ContactChunk` / `ChunkAck` /
`TransferResult` / `ContactRef` / `DuplicateGroup` / `MergeStrategy` / `AppError`。

### CSVKit

```swift
public struct CSVTable: Sendable, Equatable {
    public var headers: [String]
    public var rows: [[String]]        // headers を除いたデータ行
    public init(headers: [String], rows: [[String]])
}

public enum CSVCoding {
    /// RFC 4180 準拠パース(クォート内カンマ/改行/"" エスケープ対応)。1行目をヘッダーとする。
    public static func parse(text: String) throws -> CSVTable
    /// BOM検出 → UTF-8 → Shift_JIS → EUC-JP の順に試行。全滅なら AppError.unreadableEncoding
    public static func parse(data: Data) throws -> (table: CSVTable, encoding: String.Encoding)
    /// CRLF 改行・必要時のみクォート
    public static func write(table: CSVTable) -> String
    /// UTF-8 BOM 付き Data
    public static func encodeUTF8BOM(_ text: String) -> Data
}

public enum CSVPreset: String, CaseIterable, Sendable { case standard, google, outlook }

public enum ContactField: String, Codable, CaseIterable, Sendable {
    case familyName, givenName, phoneticFamilyName, phoneticGivenName, middleName
    case namePrefix, nameSuffix, organizationName, departmentName, jobTitle
    case phone1, phone1Label, phone2, phone2Label, phone3, phone3Label, phoneOther
    case email1, email1Label, email2, email2Label, emailOther
    case postalCode, state, city, street, subLocality, country, addressLabel
    case url, birthday, groups
}

/// 列番号 → フィールドの割り当て(ユーザー編集可能・プリセット保存対応)
public struct ColumnMapping: Codable, Sendable, Equatable {
    public var name: String                       // プリセット名
    public var assignments: [Int: ContactField]   // 列index → フィールド
    public init(name: String, assignments: [Int: ContactField])
}

public struct CSVImportResult: Sendable {
    public var contacts: [TransferContact]
    public var skipped: [SkippedRow]
    public struct SkippedRow: Sendable { public let line: Int; public let reason: String }
}

public enum CSVSchema {
    public static let standardHeaders: [String]                       // 仕様書 §5.1 の32列
    public static func detectPreset(headers: [String]) -> CSVPreset?  // standard/google/outlook 自動判定
    public static func defaultMapping(for preset: CSVPreset, headers: [String]) -> ColumnMapping
    /// バリデーション込み変換(空行・列数不一致スキップ、電話番号クレンジング、不正誕生日無視)
    public static func contacts(from table: CSVTable, mapping: ColumnMapping) -> CSVImportResult
    public static func table(from contacts: [TransferContact]) -> CSVTable
    /// UTF-8 BOM + CRLF の完成品(エクスポート用)
    public static func exportData(contacts: [TransferContact]) -> Data
    public static func exportFileName(date: Date = Date()) -> String  // 連絡先_YYYYMMDD_HHmm.csv
}

/// ラベル変換表: 自宅/勤務先/携帯/iPhone/メイン/その他 ⇄ ContactLabel
public enum LabelMapper {
    public static func japaneseText(for label: TransferContact.ContactLabel) -> String
    public static func label(fromCSVText text: String) -> TransferContact.ContactLabel
}
```

### DedupeKit

```swift
public enum ContactNormalizer {
    /// 記号除去 → 日本番号は E.164 化(090… → +8190…)
    public static func normalizePhone(_ raw: String) -> String
    /// 比較キー集合(E.164 と 下10桁)— どれか一致で L1
    public static func phoneComparisonKeys(_ raw: String) -> Set<String>
    public static func normalizeEmail(_ raw: String) -> String   // 小文字化・trim
    public static func normalizeName(_ raw: String) -> String    // NFKC・全半角統一・trim
    public static func normalizeKana(_ raw: String) -> String    // ひらがな→カタカナ統一
}

public enum MatchLevel: Int, Sendable, Comparable {
    case l4NameOnly = 1, l3NamePlus, l2Email, l1Phone
}

public struct DedupeMatch: Sendable, Identifiable {
    public let id: UUID                    // incoming.id と同一にする
    public var existing: TransferContact
    public var incoming: TransferContact
    public var level: MatchLevel
}

public struct DedupeAnalysis: Sendable {
    public var newContacts: [TransferContact]   // 重複なし → 新規作成
    public var duplicates: [DedupeMatch]        // L1〜L3(戦略に従い自動処理)
    public var candidates: [DedupeMatch]        // L4(ユーザーが1件ずつ確認)
}

public struct DedupeEngine {
    public init()
    public func analyze(existing: [TransferContact], incoming: [TransferContact]) -> DedupeAnalysis
    /// 端末内重複整理用: L1〜L3 でグルーピング
    public func duplicateGroups(in contacts: [TransferContact]) -> [DuplicateGroup]
}

public struct MergePlan: Sendable {
    public var creates: [TransferContact]
    public var updates: [MergeUpdate]           // existing.sourceIdentifier 必須
    public var deletes: [TransferContact]       // 端末内整理でグループ統合後に削除する側
    public var skippedCount: Int
    public struct MergeUpdate: Sendable {
        public var existing: TransferContact
        public var merged: TransferContact      // 適用後の完成形
    }
    public var summary: String                  // 例:「3件をマージ、10件を新規作成」
}

public enum MergePlanner {
    /// acceptedCandidates: L4 のうちユーザーが「統合する」を選んだ DedupeMatch.id
    public static func plan(analysis: DedupeAnalysis, strategy: MergeStrategy,
                            acceptedCandidates: Set<UUID>) -> MergePlan
    /// フィールド単位マージ(§6.3 の表どおり。同ラベル同値は重複追加しない)
    public static func merge(existing: TransferContact, incoming: TransferContact,
                             strategy: MergeStrategy) -> TransferContact
    /// 端末内整理: 各グループを先頭(情報量最大)に統合し残りを deletes へ
    public static func plan(groups: [DuplicateGroup], acceptedGroupIDs: Set<UUID>) -> MergePlan
}
```

### ContactsKit(Contacts framework は `#if canImport(Contacts)` ガード)

```swift
public enum ContactsAccessStatus: String, Sendable {
    case notDetermined, denied, restricted, authorized, limited
}

@MainActor
public final class ContactsPermissions: ObservableObject {
    @Published public private(set) var status: ContactsAccessStatus
    public init()
    public func refresh()
    @discardableResult
    public func requestAccess() async -> ContactsAccessStatus
    public static var settingsURL: URL? { get }   // UIApplication.openSettingsURLString
}

public enum ImageOption: String, Codable, CaseIterable, Sendable {
    case scaled      // 長辺512px JPEG 0.7(既定)
    case original
    case excluded
}

public struct ContactsReader: Sendable {
    public init()
    public func authorizedCount() throws -> Int
    /// CNContactFetchRequest ストリーム読取 + TransferContact 変換(sourceIdentifier に CNContact.identifier)
    public func fetchAll(imageOption: ImageOption,
                         onProgress: (@Sendable (Int) -> Void)?) async throws -> [TransferContact]
}

public struct ContactsApplier: Sendable {
    public init()
    public struct ApplyProgress: Sendable { public let processed: Int; public let total: Int }
    /// CNSaveRequest を100件単位でバッチ実行。Task キャンセルで完了バッチまで確定。
    /// deletes も処理する。戻り値 TransferResult に成功/失敗内訳。
    public func apply(_ plan: MergePlan,
                      onProgress: (@Sendable (ApplyProgress) -> Void)?) async throws -> TransferResult
}

public enum VCardCoder {
    public static func exportData(_ contacts: [TransferContact]) throws -> Data
    public static func contacts(from data: Data) throws -> [TransferContact]
    public static func exportFileName(date: Date = Date()) -> String  // 連絡先_YYYYMMDD_HHmm.vcf
}
```

### TransferKit(MultipeerConnectivity は `#if canImport(MultipeerConnectivity)` ガード)

```swift
/// 純ロジック(Linux でもビルド/テスト可能)
public enum ChunkCodec {
    /// contacts → 100件ごとのフレーム列(JSON + zlib圧縮 + SHA-256ヘッダ)
    public static func makeFrames(contacts: [TransferContact],
                                  maxPerChunk: Int = 100) throws -> [Data]
    /// フレーム検証+復元。チェックサム不一致は AppError.transferChecksumFailed
    public static func decodeFrame(_ data: Data) throws -> ContactChunk
    public static func sha256Hex(_ data: Data) -> String
    public static func compress(_ data: Data) throws -> Data
    public static func decompress(_ data: Data) throws -> Data
    /// 4桁確認コード生成
    public static func makeVerificationCode() -> String
}

public enum TransferRole: Sendable { case sender, receiver }

public enum TransferEvent: Sendable {
    case peersChanged([String])                      // 発見済みピア表示名
    case connecting(peer: String)
    case verificationRequired(code: String, peer: String)  // 双方同じコードを表示
    case verified
    case manifestReceived(TransferManifest)          // 受信側
    case progress(done: Int, total: Int)             // 件数ベース(送受共通)
    case contactsReceived([TransferContact])         // 受信側: 全件受信完了
    case resultReceived(TransferResult)              // 送信側: 最終結果
    case finished
    case failed(AppError)
}

@MainActor
public final class TransferSession: ObservableObject {
    public let events: AsyncStream<TransferEvent>
    @Published public private(set) var discoveredPeers: [String]
    public init(role: TransferRole, deviceName: String)
    public func start()                              // sender: browse / receiver: advertise
    public func invite(peerNamed name: String)       // 送信側がピア選択
    public func approveVerification()
    public func rejectVerification()
    public func send(contacts: [TransferContact], includesPhotos: Bool) async
    public func sendResult(_ result: TransferResult) async   // 受信側→送信側
    public func cancel()
    public func stop()
}
```

## App 側の永続化キー(UserDefaults)

- `settings.defaultMergeStrategy` : MergeStrategy.rawValue(既定 "skip")
- `settings.imageOption` : ImageOption.rawValue(既定 "scaled")
- `onboarding.completed` : Bool
- マッピングプリセット: Application Support/`mapping-presets.json`([ColumnMapping])
- 転送履歴: Application Support/`transfer-history.json`(直近10件、表示名と件数のみ)

## ビルド・テスト

- ロジックのみ: `cd ContactMoveKit && swift test`(Mac / Linux)
- アプリ: `xcodebuild -project ContactMove.xcodeproj -scheme ContactMove -destination 'platform=iOS Simulator,name=iPhone 16' build`
- `scripts/test.sh` 参照
