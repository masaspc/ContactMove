import SwiftUI
import UniformTypeIdentifiers
import Models
import CSVKit
import DedupeKit
import ContactsKit

/// インポートフローの状態管理(仕様書 §5.2 / §8)。
/// ファイル選択 → (マッピング) → プレビュー → 戦略選択 → 取り込み → 候補確認 → レポート
@MainActor
final class ImportViewModel: ObservableObject {

    enum Phase {
        case pickFile
        case parsing
        case mapping(table: CSVTable, initial: ColumnMapping)
        case preview
        case applying
        case candidates
        case report
    }

    @Published var phase: Phase = .pickFile
    @Published var error: AppError?

    // プレビュー用
    @Published private(set) var table: CSVTable?
    @Published private(set) var importResult: CSVImportResult?
    @Published private(set) var estimatedDuplicates = 0
    @Published var strategy: MergeStrategy = .skip
    @Published private(set) var fileName = ""

    // 取り込み実行用
    @Published private(set) var analysis: DedupeAnalysis?
    @Published var acceptedCandidateIDs: Set<UUID> = []
    @Published private(set) var progress: (done: Int, total: Int) = (0, 0)
    @Published private(set) var result: TransferResult?

    static let maxFileSizeMB = 100

    // MARK: - ファイル読み込み

    func handlePickedFile(url: URL) async {
        phase = .parsing
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        fileName = url.lastPathComponent
        do {
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            if let size = attributes?[.size] as? Int,
               size > Self.maxFileSizeMB * 1_024 * 1_024 {
                throw AppError.fileTooLarge(limitMB: Self.maxFileSizeMB)
            }
            let data = try Data(contentsOf: url)

            if url.pathExtension.lowercased() == "vcf" {
                let contacts = try VCardCoder.contacts(from: data)
                importResult = CSVImportResult(contacts: contacts, skipped: [])
                table = nil
                phase = .preview
                return
            }

            let (parsedTable, _) = try CSVCoding.parse(data: data)
            table = parsedTable
            if let preset = CSVSchema.detectPreset(headers: parsedTable.headers) {
                applyMapping(CSVSchema.defaultMapping(for: preset, headers: parsedTable.headers))
            } else {
                // 判定不能 → カラムマッピングUIへ(空の初期マッピング)
                phase = .mapping(table: parsedTable,
                                 initial: ColumnMapping(name: "カスタム", assignments: [:]))
            }
        } catch let appError as AppError {
            error = appError
            phase = .pickFile
        } catch {
            self.error = .csvParseFailed(reason: error.localizedDescription)
            phase = .pickFile
        }
    }

    func applyMapping(_ mapping: ColumnMapping) {
        guard let table else { return }
        let result = CSVSchema.contacts(from: table, mapping: mapping)
        importResult = result
        if result.contacts.isEmpty {
            error = .emptyImport(hint: "文字コードやヘッダー行、列の割り当てを確認してください。")
            phase = .pickFile
        } else {
            phase = .preview
        }
    }

    // MARK: - 取り込み実行

    func startImport(permissions: ContactsPermissions, imageOption: ImageOption) async {
        guard let incoming = importResult?.contacts, !incoming.isEmpty else { return }
        guard await PermissionGate.ensureAccess(permissions) else {
            error = .contactsAccessDenied
            return
        }
        phase = .applying
        progress = (0, incoming.count)
        do {
            let existing = try await ContactsReader().fetchAll(imageOption: .excluded)
            let analysis = DedupeEngine().analyze(existing: existing, incoming: incoming)
            self.analysis = analysis
            estimatedDuplicates = analysis.duplicates.count + analysis.candidates.count

            if analysis.candidates.isEmpty {
                await executePlan()
            } else {
                acceptedCandidateIDs = []
                phase = .candidates
            }
        } catch let appError as AppError {
            error = appError
            phase = .preview
        } catch {
            self.error = .saveFailed(underlying: error.localizedDescription)
            phase = .preview
        }
    }

    func executePlan() async {
        guard let analysis else { return }
        phase = .applying
        let plan = MergePlanner.plan(analysis: analysis, strategy: strategy,
                                     acceptedCandidates: acceptedCandidateIDs)
        do {
            let applyResult = try await ContactsApplier().apply(plan) { [weak self] progress in
                Task { @MainActor in
                    self?.progress = (progress.processed, progress.total)
                }
            }
            result = applyResult
            AppStorageFiles.appendHistory(.init(
                date: Date(),
                counterpart: "ファイル取り込み(\(fileName))",
                created: applyResult.created,
                merged: applyResult.merged,
                skipped: applyResult.skipped,
                failed: applyResult.failed.count))
            phase = .report
        } catch let appError as AppError {
            if case .cancelled(let count) = appError {
                result = TransferResult(received: count, created: count, merged: 0,
                                        skipped: 0, failed: [])
                phase = .report
            } else {
                error = appError
                phase = .preview
            }
        } catch {
            self.error = .saveFailed(underlying: error.localizedDescription)
            phase = .preview
        }
    }

    func reset() {
        phase = .pickFile
        table = nil
        importResult = nil
        analysis = nil
        result = nil
        acceptedCandidateIDs = []
        estimatedDuplicates = 0
    }
}

/// インポート画面本体。
struct ImportFlowView: View {
    @EnvironmentObject private var permissions: ContactsPermissions
    @EnvironmentObject private var appModel: AppModel
    @StateObject private var model = ImportViewModel()
    @State private var importerPresented = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            switch model.phase {
            case .pickFile:
                filePickerStage
            case .parsing:
                ProgressView("ファイルを解析中…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .mapping(let table, let initial):
                MappingEditorView(table: table, initialMapping: initial) { mapping in
                    model.applyMapping(mapping)
                }
            case .preview:
                ImportPreviewView(model: model) {
                    Task { await model.startImport(permissions: permissions,
                                                   imageOption: appModel.imageOption) }
                }
            case .applying:
                ProgressStageView(title: "取り込み中…",
                                  done: model.progress.done, total: model.progress.total)
            case .candidates:
                CandidateReviewView(model: model) {
                    Task { await model.executePlan() }
                }
            case .report:
                if let result = model.result {
                    ResultReportView(result: result) { dismiss() }
                }
            }
        }
        .navigationTitle("インポート")
        .appErrorAlert($model.error)
        .onAppear { model.strategy = appModel.defaultMergeStrategy }
        .fileImporter(
            isPresented: $importerPresented,
            allowedContentTypes: [.commaSeparatedText, .vCard, .plainText],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                Task { await model.handlePickedFile(url: url) }
            }
        }
    }

    private var filePickerStage: some View {
        VStack(spacing: 20) {
            Image(systemName: "square.and.arrow.down")
                .font(.system(size: 56))
                .foregroundStyle(Color.accentColor)
            Text("CSV または vCard ファイルを選択してください")
                .font(.headline)
            Text("対応形式: 本アプリ標準CSV / Googleコンタクト / Outlook / 汎用CSV(カラム割り当て可)/ .vcf\n文字コードはUTF-8・Shift_JIS・EUC-JPを自動判定します。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                importerPresented = true
            } label: {
                Text("ファイルを選ぶ")
                    .frame(maxWidth: 240)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// プレビュー画面(総行数 / 取り込み対象 / エラー行 / 先頭20件 / 戦略選択)。
struct ImportPreviewView: View {
    @ObservedObject var model: ImportViewModel
    var onStart: () -> Void

    var body: some View {
        List {
            Section("概要") {
                LabeledContent("ファイル", value: model.fileName)
                if let table = model.table {
                    LabeledContent("総データ行数", value: "\(table.rows.count)行")
                }
                LabeledContent("取り込み対象", value: "\(model.importResult?.contacts.count ?? 0)件")
                LabeledContent("スキップ行", value: "\(model.importResult?.skipped.count ?? 0)行")
            }

            if let skipped = model.importResult?.skipped, !skipped.isEmpty {
                Section("スキップされた行") {
                    ForEach(Array(skipped.prefix(20).enumerated()), id: \.offset) { _, row in
                        Text("\(row.line)行目: \(row.reason)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if skipped.count > 20 {
                        Text("ほか\(skipped.count - 20)行").font(.caption)
                    }
                }
            }

            Section("重複したときの扱い") {
                Picker("統合戦略", selection: $model.strategy) {
                    Text("スキップ(既存を優先)").tag(MergeStrategy.skip)
                    Text("マージ(推奨・不足分を補完)").tag(MergeStrategy.merge)
                    Text("上書き(取り込み側を優先)").tag(MergeStrategy.overwrite)
                    Text("両方残す").tag(MergeStrategy.keepBoth)
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }

            Section("サンプル(先頭20件)") {
                ForEach(Array(model.importResult?.contacts.prefix(20) ?? []), id: \.id) { contact in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(contact.displayName).font(.subheadline)
                        Text([contact.phones.first?.value, contact.emails.first?.value]
                            .compactMap { $0 }.joined(separator: " / "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Button {
                    onStart()
                } label: {
                    Text("取り込みを開始")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}

/// L4 候補(同姓同名のみ)の確認リスト(仕様書 §6.3)。
struct CandidateReviewView: View {
    @ObservedObject var model: ImportViewModel
    var onConfirm: () -> Void

    var body: some View {
        List {
            Section {
                Text("同姓同名の連絡先が見つかりました。同一人物として統合するものを選んでください。選ばなかったものは別の連絡先として新規作成されます。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                HStack {
                    Button("全選択") {
                        model.acceptedCandidateIDs = Set(model.analysis?.candidates.map(\.id) ?? [])
                    }
                    Spacer()
                    Button("全解除") { model.acceptedCandidateIDs = [] }
                }
                .font(.subheadline)
            }
            Section("候補(\(model.analysis?.candidates.count ?? 0)件)") {
                ForEach(model.analysis?.candidates ?? []) { match in
                    Button {
                        if model.acceptedCandidateIDs.contains(match.id) {
                            model.acceptedCandidateIDs.remove(match.id)
                        } else {
                            model.acceptedCandidateIDs.insert(match.id)
                        }
                    } label: {
                        HStack {
                            Image(systemName: model.acceptedCandidateIDs.contains(match.id)
                                  ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(model.acceptedCandidateIDs.contains(match.id)
                                                 ? Color.accentColor : Color.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(match.incoming.displayName)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                Text("既存: \(detail(match.existing)) / 取込: \(detail(match.incoming))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            Section {
                Button {
                    onConfirm()
                } label: {
                    Text("この内容で実行")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .navigationTitle("重複の確認")
    }

    private func detail(_ contact: Models.TransferContact) -> String {
        if let org = contact.organizationName, !org.isEmpty { return org }
        if let phone = contact.phones.first?.value, !phone.isEmpty { return phone }
        if let email = contact.emails.first?.value, !email.isEmpty { return email }
        return "情報なし"
    }
}
