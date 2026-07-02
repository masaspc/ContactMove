import SwiftUI
import UniformTypeIdentifiers
import Models
import CSVKit
import ContactsKit

/// fileExporter 用の汎用データドキュメント。
struct ExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText, .vCard, .data] }
    static var writableContentTypes: [UTType] { [.commaSeparatedText, .vCard, .data] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// エクスポート(仕様書 UC-02/UC-08: 対象選択 → 形式選択 → 保存先選択)。
struct ExportView: View {
    @EnvironmentObject private var permissions: ContactsPermissions
    @EnvironmentObject private var appModel: AppModel

    enum Phase {
        case loading
        case denied
        case ready
    }

    enum Format: String, CaseIterable, Identifiable {
        case csv, vcard
        var id: String { rawValue }
    }

    @State private var phase: Phase = .loading
    @State private var contacts: [TransferContact] = []
    @State private var selectedIDs: Set<UUID> = []
    @State private var loadedCount = 0
    @State private var format: Format = .csv
    @State private var error: AppError?
    @State private var exporterPresented = false
    @State private var exportDocument: ExportDocument?
    @State private var exportFileName = ""
    @State private var exportedToast = false

    var body: some View {
        Group {
            switch phase {
            case .loading:
                ProgressStageView(title: "連絡先を読み込み中…",
                                  done: loadedCount, total: max(loadedCount, 1))
            case .denied:
                PermissionDeniedView()
            case .ready:
                VStack(spacing: 0) {
                    Picker("形式", selection: $format) {
                        Text("CSV(Excel対応)").tag(Format.csv)
                        Text("vCard(画像含む)").tag(Format.vcard)
                    }
                    .pickerStyle(.segmented)
                    .padding()

                    ContactSelectionView(contacts: contacts, selectedIDs: $selectedIDs)

                    Button {
                        prepareExport()
                    } label: {
                        Text("\(selectedIDs.count)件を書き出す")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(selectedIDs.isEmpty)
                    .padding()
                }
            }
        }
        .navigationTitle("エクスポート")
        .task { await load() }
        .appErrorAlert($error)
        .fileExporter(
            isPresented: $exporterPresented,
            document: exportDocument,
            contentType: format == .csv ? .commaSeparatedText : .vCard,
            defaultFilename: exportFileName
        ) { result in
            if case .success = result {
                exportedToast = true
            }
        }
        .alert("書き出しました", isPresented: $exportedToast) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("ファイル「\(exportFileName)」を保存しました。")
        }
    }

    private func load() async {
        guard await PermissionGate.ensureAccess(permissions) else {
            phase = .denied
            return
        }
        do {
            // vCard 選択時に画像を含められるよう、設定に従って読み込む(CSVでは使われない)
            let all = try await ContactsReader().fetchAll(imageOption: appModel.imageOption) { count in
                Task { @MainActor in loadedCount = count }
            }
            contacts = all
            selectedIDs = Set(all.map(\.id))  // 既定: 全件
            phase = .ready
        } catch let appError as AppError {
            error = appError
            phase = .denied
        } catch {
            self.error = .saveFailed(underlying: error.localizedDescription)
            phase = .denied
        }
    }

    private func prepareExport() {
        let selected = contacts.filter { selectedIDs.contains($0.id) }
        do {
            switch format {
            case .csv:
                exportDocument = ExportDocument(data: CSVSchema.exportData(contacts: selected))
                exportFileName = CSVSchema.exportFileName()
            case .vcard:
                exportDocument = ExportDocument(data: try VCardCoder.exportData(selected))
                exportFileName = VCardCoder.exportFileName()
            }
            exporterPresented = true
        } catch let appError as AppError {
            error = appError
        } catch {
            self.error = .saveFailed(underlying: error.localizedDescription)
        }
    }
}
