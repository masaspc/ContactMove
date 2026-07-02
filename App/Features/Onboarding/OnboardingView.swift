import SwiftUI

/// 初回起動時のオンボーディング(3枚)+ プライバシー方針の同意(仕様書 §7.3 / §8)。
struct OnboardingView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var page = 0

    var body: some View {
        VStack {
            TabView(selection: $page) {
                onboardingPage(
                    symbol: "person.2.wave.2.fill",
                    title: "近くの端末へ直接転送",
                    text: "旧iPhoneから新iPhoneへ、連絡先をBluetooth/Wi-Fiで直接送れます。両方の端末にこのアプリを入れて、画面の確認コードを照合するだけ。")
                    .tag(0)
                onboardingPage(
                    symbol: "doc.text.fill",
                    title: "CSV・vCardで自由に入出力",
                    text: "Excelで開けるCSVや、標準のvCard形式で書き出し・取り込みができます。GoogleコンタクトやOutlookのCSVにも対応。Androidからの乗り換えにも。")
                    .tag(1)
                onboardingPage(
                    symbol: "person.crop.circle.badge.checkmark",
                    title: "重複はかしこく統合",
                    text: "電話番号・メール・氏名から重複を自動検出。スキップ/マージ/上書きなど、あなたが選んだ方針で整理します。")
                    .tag(2)
                privacyPage.tag(3)
            }
            .tabViewStyle(.page)
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            if page < 3 {
                Button {
                    withAnimation { page += 1 }
                } label: {
                    Text("次へ")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal, 32)
                .padding(.bottom, 24)
            } else {
                Button {
                    appModel.onboardingCompleted = true
                } label: {
                    Text("同意してはじめる")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal, 32)
                .padding(.bottom, 24)
                .accessibilityHint("プライバシー方針に同意してアプリの利用を開始します")
            }
        }
    }

    private func onboardingPage(symbol: String, title: LocalizedStringKey,
                                text: LocalizedStringKey) -> some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: symbol)
                .font(.system(size: 72))
                .foregroundStyle(Color.accentColor.gradient)
            Text(title).font(.title2.bold())
            Text(text)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
            Spacer()
        }
    }

    private var privacyPage: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 72))
                .foregroundStyle(Color.accentColor.gradient)
            Text("プライバシーについて").font(.title2.bold())
            VStack(alignment: .leading, spacing: 12) {
                privacyRow("連絡先データを外部サーバへ送信しません(完全ローカル/端末間直接通信のみ)")
                privacyRow("解析SDK・広告SDKは一切使用していません")
                privacyRow("書き出したファイルの保存先はあなたが指定した場所のみです")
                privacyRow("端末間転送は暗号化され、確認コードの照合後にのみ始まります")
            }
            .padding(.horizontal, 32)
            Spacer()
            Spacer()
        }
    }

    private func privacyRow(_ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .padding(.top, 2)
            Text(text).font(.subheadline)
        }
    }
}
