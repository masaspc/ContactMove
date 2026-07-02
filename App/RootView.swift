import SwiftUI

/// アプリのルート。オンボーディング完了状態(UserDefaults: onboarding.completed)で分岐する。
struct RootView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        if appModel.onboardingCompleted {
            HomeView()
        } else {
            OnboardingView()
        }
    }
}
