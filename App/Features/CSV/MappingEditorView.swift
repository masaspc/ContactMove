import SwiftUI
import CSVKit

/// カラムマッピング編集(仕様書 §5.2 手順4)。
/// 「この列=電話番号」のように列ごとにフィールドを割り当てる。
/// 割り当てはプリセットとして保存・再利用できる。
struct MappingEditorView: View {
    let table: CSVTable
    let initialMapping: ColumnMapping
    var onApply: (ColumnMapping) -> Void

    @State private var assignments: [Int: ContactField] = [:]
    @State private var presets: [ColumnMapping] = []
    @State private var savePresented = false
    @State private var presetName = ""

    var body: some View {
        List {
            Section {
                Text("列の割り当てを確認・編集してください。「割り当てない」列は取り込まれません。氏名・電話・メールのいずれかを割り当てる必要があります。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !presets.isEmpty {
                Section("保存済みプリセット") {
                    ForEach(presets, id: \.name) { preset in
                        Button(preset.name) {
                            assignments = preset.assignments
                        }
                    }
                }
            }

            Section("列の割り当て(全\(table.headers.count)列)") {
                ForEach(Array(table.headers.enumerated()), id: \.offset) { index, header in
                    VStack(alignment: .leading, spacing: 4) {
                        Picker(selection: Binding(
                            get: { assignments[index] },
                            set: { newValue in
                                if let newValue {
                                    // 同じフィールドの二重割り当てを解除
                                    for (column, field) in assignments where field == newValue {
                                        assignments.removeValue(forKey: column)
                                    }
                                    assignments[index] = newValue
                                } else {
                                    assignments.removeValue(forKey: index)
                                }
                            }
                        )) {
                            Text("割り当てない").tag(ContactField?.none)
                            ForEach(ContactField.allCases, id: \.self) { field in
                                Text(field.displayName).tag(ContactField?.some(field))
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(header.isEmpty ? "(第\(index + 1)列)" : header)
                                    .font(.subheadline)
                                if let sample = sampleValue(column: index) {
                                    Text("例: \(sample)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }

            Section {
                Button {
                    savePresented = true
                } label: {
                    Label("この割り当てをプリセット保存", systemImage: "square.and.arrow.down")
                }
                .disabled(assignments.isEmpty)

                Button {
                    onApply(ColumnMapping(name: "カスタム", assignments: assignments))
                } label: {
                    Text("この割り当てで続行")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!hasRequiredField)
            }
        }
        .navigationTitle("カラムの割り当て")
        .onAppear {
            assignments = initialMapping.assignments
            presets = AppStorageFiles.loadMappingPresets()
        }
        .alert("プリセット名", isPresented: $savePresented) {
            TextField("名前", text: $presetName)
            Button("保存") {
                let name = presetName.isEmpty ? "プリセット\(presets.count + 1)" : presetName
                var updated = presets.filter { $0.name != name }
                updated.append(ColumnMapping(name: name, assignments: assignments))
                AppStorageFiles.saveMappingPresets(updated)
                presets = updated
                presetName = ""
            }
            Button("キャンセル", role: .cancel) { presetName = "" }
        }
    }

    /// 氏名・電話・メールのいずれかが割り当てられているか
    private var hasRequiredField: Bool {
        let required: Set<ContactField> = [.familyName, .givenName, .organizationName,
                                           .phone1, .phone2, .phone3, .email1, .email2]
        return !required.isDisjoint(with: assignments.values)
    }

    private func sampleValue(column: Int) -> String? {
        for row in table.rows.prefix(3) where column < row.count && !row[column].isEmpty {
            return String(row[column].prefix(24))
        }
        return nil
    }
}
