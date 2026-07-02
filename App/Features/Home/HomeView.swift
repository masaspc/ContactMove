import SwiftUI
import ContactsKit

/// ホーム画面(仕様書 §8)。4つの主要機能への入口と limited バナー。
struct HomeView: View {
    @EnvironmentObject private var permissions: ContactsPermissions

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    LimitedAccessBanner()

                    NavigationLink {
                        TransferRoleView()
                    } label: {
                        MenuCard(
                            title: "端末間転送",
                            subtitle: "近くのiPhoneへ連絡先を直接送受信(Bluetooth/Wi-Fi)",
                            systemImage: "person.2.wave.2.fill",
                            tint: .blue)
                    }

                    NavigationLink {
                        CSVHomeView()
                    } label: {
                        MenuCard(
                            title: "CSV / vCard",
                            subtitle: "ファイルへの書き出しと取り込み(Excel・Google・Outlook対応)",
                            systemImage: "doc.text.fill",
                            tint: .green)
                    }

                    NavigationLink {
                        DedupeView()
                    } label: {
                        MenuCard(
                            title: "重複整理",
                            subtitle: "端末内の重複した連絡先を検出して統合",
                            systemImage: "person.crop.circle.badge.checkmark",
                            tint: .orange)
                    }

                    NavigationLink {
                        SettingsView()
                    } label: {
                        MenuCard(
                            title: "設定",
                            subtitle: "画像転送・統合戦略・プリセット・履歴",
                            systemImage: "gearshape.fill",
                            tint: .gray)
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("ContactMove")
            .onAppear { permissions.refresh() }
        }
    }
}
