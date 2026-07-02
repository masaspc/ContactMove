import SwiftUI
import Models
import DedupeKit
import ContactsKit

/// 端末内の重複整理(仕様書 §8: スキャン → グループ一覧 → プレビュー → 実行 → レポート)。
@MainActor
final class DedupeViewModel: ObservableObject {

    enum Phase {
        case idle
        case scanning
        case groups
        case confirm(MergePlan)
        case applying
        case report(TransferResult)
        case denied
    }

    @Published var phase: Phase = .idle
    @Published var error: AppError?
    @Published private(set) var groups: [DuplicateGroup] = []
    @Published var acceptedGroupIDs: Set<UUID> = []
    @Published private(set) var scannedCount = 0
    @Published private(set) var progress: (done: Int, total: Int) = (0, 0)

    func scan(permissions: ContactsPermissions) async {
        guard await PermissionGate.ensureAccess(permissions) else {
            phase = .denied
            return
        }
        phase = .scanning
        do {
            let contacts = try await ContactsReader().fetchAll(imageOption: .excluded) { count in
                Task { @MainActor in self.scannedCount = count }
            }
            groups = DedupeEngine().duplicateGroups(in: contacts)
            acceptedGroupIDs = Set(groups.map(\.id))  // 既定: 全グループ選択
            phase = .groups
        } catch let appError as AppError {
            error = appError
            phase = .idle
        } catch {
            self.error = .saveFailed(underlying: error.localizedDescription)
            phase = .idle
        }
    }

    func preparePlan() {
        let plan = MergePlanner.plan(groups: groups, acceptedGroupIDs: acceptedGroupIDs)
        phase = .confirm(plan)
    }

    func execute(_ plan: MergePlan) async {
        phase = .applying
        progress = (0, plan.updates.count + plan.deletes.count)
        do {
            let result = try await ContactsApplier().apply(plan) { [weak self] progress in
                Task { @MainActor in
                    self?.progress = (progress.processed, progress.total)
                }
            }
            AppStorageFiles.appendHistory(.init(
                date: Date(), counterpart: "端末内の重複整理",
                created: result.created, merged: result.merged,
                skipped: result.skipped, failed: result.failed.count))
            phase = .report(result)
        } catch let appError as AppError {
            error = appError
            phase = .groups
        } catch {
            self.error = .saveFailed(underlying: error.localizedDescription)
            phase = .groups
        }
    }
}

struct DedupeView: View {
    @EnvironmentObject private var permissions: ContactsPermissions
    @StateObject private var model = DedupeViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            switch model.phase {
            case .idle:
                startStage
            case .scanning:
                VStack(spacing: 12) {
                    ProgressView()
                    Text("スキャン中…(\(model.scannedCount)件を確認)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .groups:
                groupListStage
            case .confirm(let plan):
                confirmStage(plan)
            case .applying:
                ProgressStageView(title: "統合を実行中…",
                                  done: model.progress.done, total: model.progress.total)
            case .report(let result):
                ResultReportView(result: result) { dismiss() }
            case .denied:
                PermissionDeniedView()
            }
        }
        .navigationTitle("重複整理")
        .appErrorAlert($model.error)
    }

    private var startStage: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(.system(size: 56))
                .foregroundStyle(Color.accentColor)
            Text("端末内の重複した連絡先を検出します")
                .font(.headline)
            Text("電話番号・メールアドレス・氏名+補助情報の一致から重複を判定します。統合を実行する前に、必ず内容のプレビューを確認できます。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                Task { await model.scan(permissions: permissions) }
            } label: {
                Text("スキャン開始").frame(maxWidth: 240)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var groupListStage: some View {
        Group {
            if model.groups.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.green)
                    Text("重複は見つかりませんでした").font(.headline)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    Section {
                        Text("\(model.groups.count)組の重複候補が見つかりました。統合するグループを選んでください。各グループは情報量が最も多い連絡先へまとめられます。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Section {
                        ForEach(model.groups) { group in
                            Button {
                                if model.acceptedGroupIDs.contains(group.id) {
                                    model.acceptedGroupIDs.remove(group.id)
                                } else {
                                    model.acceptedGroupIDs.insert(group.id)
                                }
                            } label: {
                                HStack(alignment: .top) {
                                    Image(systemName: model.acceptedGroupIDs.contains(group.id)
                                          ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(model.acceptedGroupIDs.contains(group.id)
                                                         ? Color.accentColor : Color.secondary)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(group.members.first?.contact.displayName ?? "")
                                            .font(.subheadline)
                                            .foregroundStyle(.primary)
                                        Text("\(group.members.count)件 ・ 確度: \(confidenceText(group.confidence))")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    Section {
                        Button {
                            model.preparePlan()
                        } label: {
                            Text("マージ内容を確認")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.acceptedGroupIDs.isEmpty)
                    }
                }
            }
        }
    }

    private func confirmStage(_ plan: MergePlan) -> some View {
        List {
            Section("実行内容の要約") {
                Text(plan.summary).font(.headline)
                Text("統合後、重複していた側の連絡先は削除されます。この操作は元に戻せません。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("統合後の連絡先(\(plan.updates.count)件)") {
                ForEach(Array(plan.updates.enumerated()), id: \.offset) { _, update in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(update.merged.displayName).font(.subheadline)
                        Text("電話\(update.merged.phones.count)件 / メール\(update.merged.emails.count)件")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                Button(role: .destructive) {
                    Task { await model.execute(plan) }
                } label: {
                    Text("統合を実行(\(plan.deletes.count)件を削除)")
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle("マージプレビュー")
    }

    private func confidenceText(_ confidence: DuplicateGroup.Confidence) -> String {
        switch confidence {
        case .high: return "高"
        case .medium: return "中"
        case .candidate: return "要確認"
        }
    }
}
