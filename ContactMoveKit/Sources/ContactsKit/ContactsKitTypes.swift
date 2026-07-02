// プラットフォーム中立な型。Apple フレームワークに依存しないため
// ガードなしで Linux でもビルドされる。

/// 連絡先アクセス権限の状態(CNAuthorizationStatus のプラットフォーム中立表現)。
/// iOS 18 の限定アクセス(仕様書 §7.2)は `.limited` で表す。
public enum ContactsAccessStatus: String, CaseIterable, Sendable {
    case notDetermined, denied, restricted, authorized, limited
}

/// 連絡先画像の取り扱い(仕様書 §2.2)。
public enum ImageOption: String, Codable, CaseIterable, Sendable {
    /// 長辺 512px・JPEG 品質 0.7 に縮小(既定)
    case scaled
    /// 原寸のまま
    case original
    /// 画像を含めない
    case excluded
}
