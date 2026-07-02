import SwiftUI
import Models
import ContactsKit

/// UserDefaults キー(CLAUDE.md「App 側の永続化キー」参照)
enum DefaultsKey {
    static let onboardingCompleted = "onboarding.completed"
    static let defaultMergeStrategy = "settings.defaultMergeStrategy"
    static let imageOption = "settings.imageOption"
}

/// アプリ全体で共有する軽量設定モデル。
/// 連絡先の実体は常に CNContactStore 側にあり、ここでは設定値のみを持つ。
@MainActor
final class AppModel: ObservableObject {

    @Published var onboardingCompleted: Bool {
        didSet {
            UserDefaults.standard.set(onboardingCompleted, forKey: DefaultsKey.onboardingCompleted)
        }
    }

    /// 画像転送オプション(既定: scaled)
    @Published var imageOption: ImageOption {
        didSet {
            UserDefaults.standard.set(imageOption.rawValue, forKey: DefaultsKey.imageOption)
        }
    }

    /// 既定の統合戦略(既定: skip)
    @Published var defaultMergeStrategy: MergeStrategy {
        didSet {
            UserDefaults.standard.set(defaultMergeStrategy.rawValue, forKey: DefaultsKey.defaultMergeStrategy)
        }
    }

    init() {
        let defaults = UserDefaults.standard
        onboardingCompleted = defaults.bool(forKey: DefaultsKey.onboardingCompleted)
        imageOption = ImageOption(
            rawValue: defaults.string(forKey: DefaultsKey.imageOption) ?? ""
        ) ?? .scaled
        defaultMergeStrategy = MergeStrategy(
            rawValue: defaults.string(forKey: DefaultsKey.defaultMergeStrategy) ?? ""
        ) ?? .skip
    }

    /// アプリのバージョン表示用文字列
    static var versionString: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }
}
