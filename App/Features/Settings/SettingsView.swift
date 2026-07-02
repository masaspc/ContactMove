import SwiftUI
import Models
import CSVKit
import ContactsKit

/// 設定画面(仕様書 §8: 画像転送 / 既定の統合戦略 / プリセット管理 / 履歴 / 方針)。
struct SettingsView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var presets: [ColumnMapping] = []
    @State private var history: [AppStorageFiles.TransferHistoryEntry] = []

    var body: some View {
        List {
            Section("転送・書き出し") {
                Picker("連絡先の画像", selection: $appModel.imageOption) {
                    Text("縮小して含める(推奨)").tag(ImageOption.scaled)
                    Text("原寸のまま含める").tag(ImageOption.original)
                    Text("含めない").tag(ImageOption.excluded)
                }
                Picker("既定の統合戦略", selection: $appModel.defaultMergeStrategy) {
                    Text("スキップ").tag(MergeStrategy.skip)
                    Text("マージ").tag(MergeStrategy.merge)
                    Text("上書き").tag(MergeStrategy.overwrite)
                    Text("両方残す").tag(MergeStrategy.keepBoth)
                }
            }

            Section("マッピングプリセット") {
                if presets.isEmpty {
                    Text("保存済みのプリセットはありません")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(presets, id: \.name) { preset in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(preset.name)
                            Text("\(preset.assignments.count)列を割り当て")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { offsets in
                        presets.remove(atOffsets: offsets)
                        AppStorageFiles.saveMappingPresets(presets)
                    }
                }
            }

            Section("転送履歴(直近10件)") {
                if history.isEmpty {
                    Text("履歴はありません").foregroundStyle(.secondary)
                } else {
                    ForEach(history) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.counterpart).font(.subheadline)
                            Text("\(entry.date.formatted(date: .abbreviated, time: .shortened)) ・ 新規\(entry.created) / マージ\(entry.merged) / スキップ\(entry.skipped) / 失敗\(entry.failed)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Button("履歴を消去", role: .destructive) {
                        AppStorageFiles.clearHistory()
                        history = []
                    }
                }
            }

            Section("このアプリについて") {
                NavigationLink("プライバシー方針") {
                    PrivacyPolicyView()
                }
                NavigationLink("できないこと(iOSの制約)") {
                    LimitationsView()
                }
                LabeledContent("バージョン", value: AppModel.versionString)
            }
        }
        .navigationTitle("設定")
        .onAppear {
            presets = AppStorageFiles.loadMappingPresets()
            history = AppStorageFiles.loadHistory()
        }
    }
}

struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                policySection("外部送信ゼロ",
                              "連絡先データを外部サーバへ送信することは一切ありません。端末間転送は2台の端末の間の暗号化された直接通信のみで行われます。")
                policySection("収集ゼロ",
                              "解析SDK・広告SDKを使用していません。App Storeのプライバシー表示は「データを収集しません」です。")
                policySection("一時ファイル",
                              "転送用の一時データは処理の完了または失敗と同時に削除されます。")
                policySection("保存先",
                              "書き出したCSV/vCardファイルの保存先は、あなたが指定した場所のみです。アプリが勝手にクラウドへアップロードすることはありません。")
                policySection("メモ欄について",
                              "連絡先の「メモ」フィールドはAppleの特別な承認が必要なため、本アプリでは読み書きしません。")
            }
            .padding()
        }
        .navigationTitle("プライバシー方針")
    }

    private func policySection(_ title: LocalizedStringKey, _ body: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            Text(body).font(.subheadline).foregroundStyle(.secondary)
        }
    }
}

/// 仕様書 付録A(できないこと一覧)のユーザー向け説明。
struct LimitationsView: View {
    var body: some View {
        List {
            limitation(
                "アプリの入っていない端末からの吸い出し",
                "iOSはカーナビ等が使う電話帳プロファイル(PBAP/OPP)をアプリに開放していないため、相手の端末にこのアプリを入れずにBluetoothで連絡先を取得することはできません。旧端末側でvCard/CSVを書き出し、AirDropやクラウド経由でこの端末に渡して取り込んでください。")
            limitation(
                "連絡先の「メモ」の移行",
                "メモ欄の読み書きにはAppleの承認制の特別な権限が必要なため、現在は対応していません。")
            limitation(
                "バックグラウンドでの転送継続",
                "iOSの制約により、転送中は両方の端末でこのアプリの画面を開いたままにする必要があります(転送中は自動で画面スリープを抑制します)。")
            limitation(
                "「一部のみ許可」のままの全件移行",
                "iOS 18の限定アクセス中は許可された連絡先のみ処理できます。全件を移行するには、設定でフルアクセスに変更してください。")
        }
        .navigationTitle("できないこと")
    }

    private func limitation(_ title: LocalizedStringKey, _ body: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.bold())
            Text(body).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
