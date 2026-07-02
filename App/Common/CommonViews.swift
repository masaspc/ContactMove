import SwiftUI
import Models
import ContactsKit

// MARK: - エラー表示(AppError を全画面共通のアラートで出す)

struct ErrorAlertModifier: ViewModifier {
    @Binding var error: AppError?

    func body(content: Content) -> some View {
        content.alert(
            "エラー",
            isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })
        ) {
            Button("OK", role: .cancel) { error = nil }
        } message: {
            Text(error?.errorDescription ?? "不明なエラーが発生しました")
        }
    }
}

extension View {
    func appErrorAlert(_ error: Binding<AppError?>) -> some View {
        modifier(ErrorAlertModifier(error: error))
    }
}

// MARK: - iOS 18 限定アクセスバナー(仕様書 §7.2)

struct LimitedAccessBanner: View {
    @EnvironmentObject private var permissions: ContactsPermissions

    var body: some View {
        if permissions.status == .limited {
            VStack(alignment: .leading, spacing: 8) {
                Label("一部の連絡先のみアクセス許可中", systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.bold())
                Text("全件を移行するには、設定で連絡先アクセスを「フルアクセス」に変更してください。")
                    .font(.caption)
                if let url = ContactsPermissions.settingsURL {
                    Link("設定を開く", destination: url)
                        .font(.caption.bold())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.yellow.opacity(0.2), in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
            .accessibilityElement(children: .combine)
        }
    }
}

// MARK: - 権限リクエスト(機能の実行直前に呼ぶ、仕様書 §7.1)

enum PermissionGate {
    /// 権限を確認し、必要ならリクエストする。利用可能なら true。
    @MainActor
    static func ensureAccess(_ permissions: ContactsPermissions) async -> Bool {
        switch permissions.status {
        case .authorized, .limited:
            return true
        case .notDetermined:
            let status = await permissions.requestAccess()
            return status == .authorized || status == .limited
        case .denied, .restricted:
            return false
        }
    }
}

/// 権限拒否時の説明+設定誘導
struct PermissionDeniedView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.crop.circle.badge.xmark")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("連絡先へのアクセスが必要です")
                .font(.headline)
            Text("この機能を使うには、設定アプリで ContactMove に連絡先へのアクセスを許可してください。連絡先データが外部サーバへ送られることはありません。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let url = ContactsPermissions.settingsURL {
                Link("設定を開く", destination: url)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }
}

// MARK: - 結果レポート(仕様書 FR-11)

struct ResultReportView: View {
    let result: TransferResult
    var onDone: (() -> Void)?

    var body: some View {
        List {
            Section("結果") {
                row("処理対象", count: result.received, symbol: "tray.full")
                row("新規作成", count: result.created, symbol: "person.badge.plus")
                row("マージ", count: result.merged, symbol: "arrow.triangle.merge")
                row("スキップ", count: result.skipped, symbol: "arrow.uturn.right")
                row("失敗", count: result.failed.count, symbol: "xmark.circle")
            }
            if !result.failed.isEmpty {
                Section("失敗の内訳") {
                    ForEach(Array(result.failed.enumerated()), id: \.offset) { _, item in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.displayName).font(.subheadline)
                            Text(item.reason).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if let onDone {
                Section {
                    Button("完了") { onDone() }
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle("結果レポート")
        .navigationBarBackButtonHidden(onDone != nil)
    }

    private func row(_ title: LocalizedStringKey, count: Int, symbol: String) -> some View {
        HStack {
            Label(title, systemImage: symbol)
            Spacer()
            Text("\(count)件").bold().monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 進捗表示

struct ProgressStageView: View {
    let title: LocalizedStringKey
    let done: Int
    let total: Int

    var body: some View {
        VStack(spacing: 16) {
            ProgressView(value: total > 0 ? Double(done) / Double(total) : 0)
                .progressViewStyle(.linear)
                .padding(.horizontal, 40)
            Text(title).font(.headline)
            Text("\(done) / \(total) 件")
                .font(.title3.monospacedDigit())
                .foregroundStyle(.secondary)
                .accessibilityLabel("\(total)件中\(done)件が完了")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - メニューカード(ホーム用)

struct MenuCard: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(tint.gradient, in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline).foregroundStyle(.primary)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote.bold())
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
}
