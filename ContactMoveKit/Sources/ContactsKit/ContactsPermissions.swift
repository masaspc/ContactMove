import Foundation

#if canImport(Contacts)
import Contacts
#if canImport(UIKit)
import UIKit
#endif

/// 連絡先アクセス権限の管理(仕様書 §7)。
/// 権限は起動時ではなく「エクスポート/転送/インポート実行」直前に取得する。
@MainActor
public final class ContactsPermissions: ObservableObject {

    @Published public private(set) var status: ContactsAccessStatus

    public init() {
        status = Self.currentStatus()
    }

    /// 現在の権限状態を読み直す(設定アプリから戻った時などに呼ぶ)。
    public func refresh() {
        status = Self.currentStatus()
    }

    /// 権限をリクエストし、確定後の状態を返す。
    @discardableResult
    public func requestAccess() async -> ContactsAccessStatus {
        let store = CNContactStore()
        _ = try? await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
            store.requestAccess(for: .contacts) { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
        refresh()
        return status
    }

    /// 設定アプリの本アプリページへのディープリンク(limited/denied からの誘導用)。
    public static var settingsURL: URL? {
        #if canImport(UIKit)
        return URL(string: UIApplication.openSettingsURLString)
        #else
        return nil
        #endif
    }

    static func currentStatus() -> ContactsAccessStatus {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        #if os(iOS)
        if #available(iOS 18.0, *) {
            if status == .limited { return .limited }
        }
        #endif
        switch status {
        case .notDetermined: return .notDetermined
        case .restricted: return .restricted
        case .denied: return .denied
        case .authorized: return .authorized
        default: return .notDetermined
        }
    }
}

#else

/// Contacts framework が使えない環境(Linux 等)向けのスタブ。
@MainActor
public final class ContactsPermissions {
    public private(set) var status: ContactsAccessStatus = .denied
    public init() {}
    public func refresh() {}
    @discardableResult
    public func requestAccess() async -> ContactsAccessStatus { .denied }
    public static var settingsURL: URL? { nil }
}

#endif
